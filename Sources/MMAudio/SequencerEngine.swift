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

    public typealias PlayheadHandler = @Sendable (Int) -> Void
    public typealias TransportHandler = @Sendable (Transport) -> Void
    public typealias EventHandler = @Sendable (SequenceEvent) -> Void

    public var onPlayhead: PlayheadHandler?
    public var onTransport: TransportHandler?
    public var onEventRecorded: EventHandler?

    private let audio: AudioEngine
    private let lock = NSLock()
    private let timerQueue = DispatchQueue(label: "mac-mpc.sequencer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    // All access guarded by `lock`.
    private var transport: Transport = .stopped
    private var events: [SequenceEvent] = []
    private var bpm: Double = 90
    private var loopLengthTicks: Int = Timing.loopLengthTicks(bars: 4, numerator: 4, denominator: 4)
    private var quantizeDivision: Int = 16
    private var quantizeOnRecord: Bool = true

    private var startHostSeconds: Double = 0
    private var lastLoopTick: Int = 0
    /// Last step index reported to `onPlayhead`, to throttle UI updates to
    /// step granularity instead of every 2ms tick.
    private var lastReportedStep: Int = -1

    public init(audio: AudioEngine) {
        self.audio = audio
    }

    // MARK: - Config

    public func setTempo(_ newBPM: Double) {
        lock.lock(); bpm = max(20, min(300, newBPM)); lock.unlock()
    }

    public func setLoop(bars: Int, numerator: Int, denominator: Int) {
        lock.lock()
        loopLengthTicks = Timing.loopLengthTicks(bars: bars, numerator: numerator, denominator: denominator)
        lock.unlock()
    }

    public func setQuantize(division: Int, enabled: Bool) {
        lock.lock(); quantizeDivision = division; quantizeOnRecord = enabled; lock.unlock()
    }

    public func loadEvents(_ newEvents: [SequenceEvent]) {
        lock.lock(); events = newEvents.sorted { $0.tick < $1.tick }; lock.unlock()
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

    public func play() { begin(.playing) }
    public func record() { begin(.recording) }

    public func stop() {
        lock.lock()
        transport = .stopped
        timer?.cancel()
        timer = nil
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
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        timer?.cancel()
        timer = t
        lock.unlock()
        t.resume()
        onTransport?(mode)
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
        lock.unlock()
        onEventRecorded?(event)
    }

    // MARK: - Clock

    private func tick() {
        lock.lock()
        guard transport != .stopped else { lock.unlock(); return }
        let spt = Timing.secondsPerTick(bpm: bpm)
        let loopLen = max(1, loopLengthTicks)
        let elapsed = nowSeconds() - startHostSeconds
        let absoluteTick = spt > 0 ? Int(elapsed / spt) : 0
        let currentLoopTick = absoluteTick % loopLen
        let previous = lastLoopTick
        lastLoopTick = currentLoopTick
        let stepSize = Timing.ticksPerStep(division: quantizeDivision)
        let currentStep = currentLoopTick / max(1, stepSize)
        let stepChanged = currentStep != lastReportedStep
        if stepChanged { lastReportedStep = currentStep }

        // Collect events crossed in (previous, currentLoopTick], handling wrap.
        var toFire: [SequenceEvent] = []
        if currentLoopTick >= previous {
            for e in events where e.tick > previous && e.tick <= currentLoopTick { toFire.append(e) }
        } else {
            // Wrapped around the loop boundary.
            for e in events where e.tick > previous && e.tick < loopLen { toFire.append(e) }
            for e in events where e.tick >= 0 && e.tick <= currentLoopTick { toFire.append(e) }
        }
        lock.unlock()

        for e in toFire {
            audio.triggerPad(PadAddress(bank: e.bank, pad: e.pad), velocity: e.velocity)
        }
        if stepChanged { onPlayhead?(currentLoopTick) }
    }

    private func nowSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
