import Foundation
import AVFoundation
import MMModels

/// A timer-driven step sequencer.
///
/// A high-priority `DispatchSourceTimer` ticks every few milliseconds; on
/// each fire it advances a tick playhead derived from wall-clock elapsed
/// time and fires any events crossed since the last fire. Events trigger the
/// `AudioEngine` directly (its trigger path is thread-safe), so there's no
/// main-thread hop on the audio path. Playhead + transport changes are
/// surfaced via `@Sendable` callbacks that the owner marshals to the UI.
///
/// Timing is wall-clock/look-back rather than sample-accurate scheduling —
/// fine for v1 (≈ timer-interval jitter); a sample-clock rework can come
/// later without changing this interface.
public final class SequencerEngine: @unchecked Sendable {

    public enum Transport: Sendable, Equatable { case stopped, playing, recording }
    public enum Metronome: Sendable, Equatable { case off, on, recordOnly }

    /// One step of a song: a sequence's events + its timing.
    public struct SongEntry: Sendable {
        public var events: [SequenceEvent]
        public var bars: Int
        public var bpm: Double
        public var swing: Double
        public var numerator: Int
        public var denominator: Int
        public init(events: [SequenceEvent], bars: Int, bpm: Double, swing: Double,
                    numerator: Int, denominator: Int) {
            self.events = events; self.bars = bars; self.bpm = bpm; self.swing = swing
            self.numerator = numerator; self.denominator = denominator
        }
    }

    public typealias PlayheadHandler = @Sendable (Int) -> Void
    public typealias TransportHandler = @Sendable (Transport) -> Void
    public typealias EventHandler = @Sendable (SequenceEvent) -> Void
    public typealias SongAdvanceHandler = @Sendable (Int) -> Void

    public var onPlayhead: PlayheadHandler?
    public var onTransport: TransportHandler?
    public var onEventRecorded: EventHandler?
    /// Fired when song playback advances to a new entry (passes its index).
    public var onSongAdvance: SongAdvanceHandler?

    private let audio: AudioEngine
    private let lock = NSLock()
    private let timerQueue = DispatchQueue(label: "flipside.sequencer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    // All access guarded by `lock`.
    private var transport: Transport = .stopped
    private var events: [SequenceEvent] = []
    private var bpm: Double = 90
    private var loopLengthTicks: Int = Timing.loopLengthTicks(bars: 4, numerator: 4, denominator: 4)
    private var quantizeDivision: Int = 16
    private var quantizeOnRecord: Bool = true
    /// Swing amount 0…1. 0 = straight; higher delays off-beat 1/16 notes,
    /// up to half a 1/16 at 1.0 (the classic MPC "shuffle").
    private var swing: Double = 0
    /// Events with swing applied to their ticks — what playback actually
    /// fires. Rebuilt from `events` whenever events or swing change.
    private var playbackEvents: [SequenceEvent] = []

    // Song playback: when non-nil, the loop boundary advances to the next
    // entry instead of repeating.
    private var songEntries: [SongEntry]?
    private var songIndex: Int = 0
    private var songLoops: Bool = false

    private var numerator: Int = 4
    private var metronome: Metronome = .off
    private var countInEnabled: Bool = false
    private var countingIn: Bool = false
    private var countInDurationSec: Double = 0

    private var startHostSeconds: Double = 0
    private var lastLoopTick: Int = 0
    /// Last step index reported to `onPlayhead`, to throttle UI updates to
    /// step granularity instead of every 2ms tick.
    private var lastReportedStep: Int = -1
    /// Last beat index a click fired on (-1 = none yet this run).
    private var lastClickedBeat: Int = -1

    public init(audio: AudioEngine) {
        self.audio = audio
    }

    // MARK: - Config

    public func setTempo(_ newBPM: Double) {
        lock.lock(); bpm = max(20, min(300, newBPM)); lock.unlock()
    }

    public func setLoop(bars: Int, numerator: Int, denominator: Int) {
        lock.lock()
        self.numerator = numerator
        loopLengthTicks = Timing.loopLengthTicks(bars: bars, numerator: numerator, denominator: denominator)
        lock.unlock()
    }

    public func setMetronome(_ m: Metronome) {
        lock.lock(); metronome = m; lock.unlock()
    }

    public func setCountIn(_ on: Bool) {
        lock.lock(); countInEnabled = on; lock.unlock()
    }

    public func setQuantize(division: Int, enabled: Bool) {
        lock.lock(); quantizeDivision = division; quantizeOnRecord = enabled; lock.unlock()
    }

    public func setSwing(_ amount: Double) {
        lock.lock()
        swing = max(0, min(1, amount))
        rebuildPlayback()
        lock.unlock()
    }

    public func loadEvents(_ newEvents: [SequenceEvent]) {
        lock.lock()
        events = newEvents.sorted { $0.tick < $1.tick }
        rebuildPlayback()
        lock.unlock()
    }

    /// Recompute swung playback ticks. Caller must hold `lock`.
    /// Off-beat 1/16 notes (odd 1/16 step index) are pushed later by up to
    /// half a 1/16 note at swing = 1.
    private func rebuildPlayback() {
        let s16 = Timing.ticksPerStep(division: 16)
        let maxDelay = Double(s16) * 0.5
        let delay = Int((swing * maxDelay).rounded())
        if delay == 0 {
            playbackEvents = events
            return
        }
        playbackEvents = events.map { e in
            let stepIndex = Int((Double(e.tick) / Double(s16)).rounded())
            guard stepIndex % 2 == 1 else { return e }
            var swung = e
            swung.tick = e.tick + delay
            return swung
        }.sorted { $0.tick < $1.tick }
    }

    public func currentEvents() -> [SequenceEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    public var currentTransport: Transport {
        lock.lock(); defer { lock.unlock() }
        return transport
    }

    // MARK: - Transport

    public func play() {
        lock.lock(); songEntries = nil; lock.unlock()
        begin(.playing)
    }
    public func record() {
        lock.lock(); songEntries = nil; lock.unlock()
        begin(.recording)
    }

    /// Play an ordered list of sequences as a song, auto-advancing at each
    /// loop boundary. Stops at the end unless `loop` is true.
    public func playSong(_ entries: [SongEntry], loop: Bool = false) {
        guard !entries.isEmpty else { return }
        lock.lock()
        songEntries = entries
        songIndex = 0
        songLoops = loop
        loadSongEntryLocked(0)
        lock.unlock()
        onSongAdvance?(0)
        begin(.playing)
    }

    /// Load a song entry's events + timing. Caller must hold `lock`.
    private func loadSongEntryLocked(_ i: Int) {
        guard let entries = songEntries, entries.indices.contains(i) else { return }
        let e = entries[i]
        bpm = max(20, min(300, e.bpm))
        numerator = e.numerator
        loopLengthTicks = Timing.loopLengthTicks(bars: e.bars, numerator: e.numerator, denominator: e.denominator)
        swing = max(0, min(1, e.swing))
        events = e.events.sorted { $0.tick < $1.tick }
        rebuildPlayback()
    }

    public func stop() {
        lock.lock()
        transport = .stopped
        timer?.cancel()
        timer = nil
        songEntries = nil
        lock.unlock()
        audio.stopAll()
        onTransport?(.stopped)
        onPlayhead?(0)
    }

    private func begin(_ mode: Transport) {
        lock.lock()
        transport = mode
        startHostSeconds = nowSeconds()
        lastLoopTick = 0
        lastReportedStep = -1
        lastClickedBeat = -1
        // One-bar count-in before recording, if enabled.
        if mode == .recording && countInEnabled {
            countingIn = true
            let secPerTick = Timing.secondsPerTick(bpm: bpm)
            let oneBarTicks = numerator * Timing.ticksPerQuarter
            countInDurationSec = secPerTick * Double(oneBarTicks)
        } else {
            countingIn = false
        }
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        timer?.cancel()
        timer = t
        lock.unlock()
        t.resume()
        onTransport?(mode)
    }

    /// Whether the metronome should sound in the current transport state.
    /// Caller must hold `lock`.
    private func clickAudible() -> Bool {
        switch metronome {
        case .off: return false
        case .on: return true
        case .recordOnly: return transport == .recording || countingIn
        }
    }

    // MARK: - Recording input

    /// Record a pad hit at the current playhead (any thread). No-op unless
    /// recording.
    public func recordHit(bank: BankIndex, pad: PadIndex, velocity: UInt8) {
        lock.lock()
        guard transport == .recording else { lock.unlock(); return }
        let spt = Timing.secondsPerTick(bpm: bpm)
        let elapsed = nowSeconds() - startHostSeconds
        var tick = spt > 0 ? Int(elapsed / spt) % max(1, loopLengthTicks) : 0
        if quantizeOnRecord {
            tick = Timing.quantize(tick, division: quantizeDivision) % max(1, loopLengthTicks)
        }
        let event = SequenceEvent(tick: tick, bank: bank, pad: pad, velocity: velocity)
        events.append(event)
        events.sort { $0.tick < $1.tick }
        rebuildPlayback()
        lock.unlock()
        onEventRecorded?(event)
    }

    // MARK: - Clock

    private func tick() {
        lock.lock()
        guard transport != .stopped else { lock.unlock(); return }
        let spt = Timing.secondsPerTick(bpm: bpm)
        let loopLen = max(1, loopLengthTicks)
        let beatTicks = Timing.ticksPerQuarter

        // Count-in phase: clicks only, no events, no normal playhead.
        if countingIn {
            let elapsed = nowSeconds() - startHostSeconds
            if elapsed >= countInDurationSec {
                // Count-in done — restart the clock for the real take.
                countingIn = false
                startHostSeconds = nowSeconds()
                lastLoopTick = 0
                lastReportedStep = -1
                lastClickedBeat = -1
                lock.unlock()
                return
            }
            let countTick = spt > 0 ? Int(elapsed / spt) : 0
            let beat = countTick / beatTicks
            let audible = clickAudible()
            let fireClick = beat != lastClickedBeat
            if fireClick { lastClickedBeat = beat }
            let accent = beat % max(1, numerator) == 0
            lock.unlock()
            if fireClick && audible { audio.playClick(accent: accent) }
            return
        }

        let elapsed = nowSeconds() - startHostSeconds
        let absoluteTick = spt > 0 ? Int(elapsed / spt) : 0
        let currentLoopTick = absoluteTick % loopLen
        let previous = lastLoopTick

        // Song mode: on a loop wrap, advance to the next entry (clean seam at
        // tick 0; quantized events sit well before the boundary so nothing
        // audible is lost in the sub-tick tail).
        if let entries = songEntries, currentLoopTick < previous {
            var next = songIndex + 1
            if next >= entries.count {
                if songLoops { next = 0 }
                else {
                    lock.unlock()
                    stop()
                    return
                }
            }
            songIndex = next
            loadSongEntryLocked(next)
            startHostSeconds = nowSeconds()
            lastLoopTick = 0
            lastReportedStep = -1
            lastClickedBeat = -1
            lock.unlock()
            onSongAdvance?(next)
            return
        }

        lastLoopTick = currentLoopTick
        let stepSize = Timing.ticksPerStep(division: quantizeDivision)
        let currentStep = currentLoopTick / max(1, stepSize)
        let stepChanged = currentStep != lastReportedStep
        if stepChanged { lastReportedStep = currentStep }

        // Metronome: click when the beat index changes.
        let beat = absoluteTick / beatTicks
        let fireClick = beat != lastClickedBeat
        if fireClick { lastClickedBeat = beat }
        let accent = (currentLoopTick / beatTicks) % max(1, numerator) == 0
        let clickOn = clickAudible()

        // Collect events crossed in (previous, currentLoopTick], handling wrap.
        // Uses the swing-adjusted playback list.
        var toFire: [SequenceEvent] = []
        if currentLoopTick >= previous {
            for e in playbackEvents where e.tick > previous && e.tick <= currentLoopTick { toFire.append(e) }
        } else {
            for e in playbackEvents where e.tick > previous && e.tick < loopLen { toFire.append(e) }
            for e in playbackEvents where e.tick >= 0 && e.tick <= currentLoopTick { toFire.append(e) }
        }
        lock.unlock()

        if fireClick && clickOn { audio.playClick(accent: accent) }
        for e in toFire {
            audio.triggerPad(PadAddress(bank: e.bank, pad: e.pad), velocity: e.velocity)
        }
        if stepChanged { onPlayhead?(currentLoopTick) }
    }

    private func nowSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
