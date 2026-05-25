import Foundation
import Observation
import AVFoundation
import AppKit
import MMAudio
import MMMidi
import MMModels

/// Single root state object. All app-level mutable state lives here so
/// SwiftUI views can observe it via `@Environment(AppState.self)`.
@MainActor
@Observable
final class AppState {

    var project = Project()
    let audio = AudioEngine()

    /// MF64 device wrapper (nil until `start()` is called).
    var mf64: MidiFighter64?
    /// Korg nanoKONTROL device wrapper.
    var nano: KorgNanoKontrol?

    var mf64Status: ConnectionStatus = .disconnected
    var nanoStatus: ConnectionStatus = .disconnected

    /// Pads currently held down on the MF64.
    var pressedCoords: Set<PadCoord> = []

    /// The pad that's currently the editing focus.
    var selectedPad: PadAddress = PadAddress(bank: .A, pad: PadIndex(0)) {
        didSet {
            if selectedPad != oldValue {
                recomputeWaveform()
                refreshMF64LEDs()
            }
        }
    }

    /// Active page in the LCD display panel.
    var currentPage: SamplePage = .trim

    /// Cached waveform peaks for the selected pad. Recomputed on selection
    /// change, load, or destructive edit.
    var waveformPeaks: WaveformPeaks = WaveformPeaks(peaks: [], frameCount: 0, sampleRate: 0)

    /// Sample browser state.
    var browser: SampleBrowser
    var isBrowserOpen: Bool = false

    /// Transport / sequencer.
    let sequencer: SequencerEngine
    var transport: SequencerEngine.Transport = .stopped
    var playheadTick: Int = 0

    /// Song mode: sheet visibility + index of the currently-playing entry.
    var isSongOpen: Bool = false
    var currentSongIndex: Int = 0

    /// Master compressor sheet visibility.
    var isCompressorOpen: Bool = false

    /// Metronome + count-in (recording aids).
    var metronome: SequencerEngine.Metronome = .off { didSet { sequencer.setMetronome(metronome) } }
    var countIn: Bool = false { didSet { sequencer.setCountIn(countIn) } }

    /// Knob FX (master bus). Session state for now.
    var knobFXType: KnobFXType = .none { didSet { applyKnobFX() } }
    var knobFXK1: Double = 0.5 { didSet { applyKnobFX() } }
    var knobFXK2: Double = 0.5 { didSet { applyKnobFX() } }
    var knobFXK3: Double = 0.5 { didSet { applyKnobFX() } }
    var isKnobFXOpen: Bool = false

    func applyKnobFX() {
        audio.setKnobFX(knobFXType, k1: knobFXK1, k2: knobFXK2, k3: knobFXK3)
    }

    // MARK: - Pad FX mode

    /// When active, pad presses toggle momentary master effects instead of
    /// playing samples. v1 maps the first six pads to the available master
    /// effects (full 16-effect DSP + simultaneity still to come).
    var padFXActive: Bool = false
    /// Which pad's effect is currently engaged (nil = none).
    var activePadFX: Int?

    static let padFXMap: [Int: KnobFXType] = [
        0: .lowpass, 1: .highpass, 2: .bandpass,
        3: .delay,   4: .reverb,   5: .distortion,
    ]

    func togglePadFXMode() {
        padFXActive.toggle()
        audio.setPlaybackEnabled(!padFXActive)
        if !padFXActive {
            // Leaving the mode clears any engaged effect.
            activePadFX = nil
            knobFXType = .none
        }
        lastEvent = padFXActive ? "Pad FX mode ON" : "Pad FX mode OFF"
    }

    /// Toggle the effect mapped to a pad index (0-15).
    private func handlePadFXPress(_ index: Int) {
        guard let fx = Self.padFXMap[index] else { return }
        if activePadFX == index {
            activePadFX = nil
            knobFXType = .none
        } else {
            activePadFX = index
            knobFXType = fx   // didSet applies it with current K1-K3
        }
    }

    var lastEvent: String = "—"

    enum ConnectionStatus: Equatable {
        case disconnected
        case connected(name: String)
    }

    init() {
        audio.start()
        browser = SampleBrowser(audio: audio)
        sequencer = SequencerEngine(audio: audio)
        wireSequencer()
    }

    func start() {
        startMF64()
        startNano()
    }

    // MARK: - Transport

    private func wireSequencer() {
        sequencer.onTransport = { [weak self] t in
            Task { @MainActor in self?.transport = t }
        }
        sequencer.onPlayhead = { [weak self] tick in
            Task { @MainActor in self?.playheadTick = tick }
        }
        sequencer.onEventRecorded = { [weak self] event in
            Task { @MainActor in
                self?.project.sequences[self?.project.activeSequence ?? PadAddress(bank: .A, pad: PadIndex(0))]?.events.append(event)
            }
        }
        sequencer.onSongAdvance = { [weak self] idx in
            Task { @MainActor in self?.currentSongIndex = idx }
        }
    }

    // MARK: - Song mode

    func insertIntoSong(_ addr: PadAddress) {
        project.song.append(addr)
        lastEvent = "Song: added \(addr)"
    }

    func removeFromSong(at index: Int) {
        guard project.song.indices.contains(index) else { return }
        project.song.remove(at: index)
    }

    func clearSong() { project.song.removeAll() }

    /// Play the song: build engine entries from each referenced sequence.
    func playSong() {
        let entries: [SequencerEngine.SongEntry] = project.song.compactMap { addr in
            guard let seq = project.sequences[addr] else { return nil }
            return SequencerEngine.SongEntry(
                events: seq.events,
                bars: seq.bars,
                bpm: seq.bpm,
                swing: seq.swing,
                numerator: project.timeSigNumerator,
                denominator: project.timeSigDenominator)
        }
        guard !entries.isEmpty else { lastEvent = "Song is empty"; return }
        currentSongIndex = 0
        sequencer.playSong(entries)
    }

    /// Flatten the song into a single new sequence placed in the first empty
    /// slot — concatenating each entry's events at its bar offset.
    func flattenSongToNewSequence() {
        guard !project.song.isEmpty else { lastEvent = "Song is empty"; return }
        var flat = MMSequence()
        var tickOffset = 0
        var totalBars = 0
        for addr in project.song {
            guard let seq = project.sequences[addr] else { continue }
            for e in seq.events {
                var shifted = e
                shifted.tick += tickOffset
                flat.events.append(shifted)
            }
            let barTicks = project.timeSigNumerator * (Timing.ticksPerQuarter * 4 / project.timeSigDenominator)
            tickOffset += seq.bars * barTicks
            totalBars += seq.bars
        }
        flat.bars = max(1, min(128, totalBars))
        flat.bpm = project.sequences[project.song.first!]?.bpm ?? project.globalBPM
        flat.name = "Song Flat"
        // Find the first empty sequence slot.
        for bank in BankIndex.allCases {
            for i in 0..<16 {
                let slot = PadAddress(bank: bank, pad: PadIndex(i))
                if project.sequences[slot]?.isEmpty ?? true {
                    project.sequences[slot] = flat
                    project.activeSequence = slot
                    lastEvent = "Flattened song → \(slot) (\(flat.bars) bars)"
                    return
                }
            }
        }
        lastEvent = "No empty sequence slot for flatten"
    }

    /// Push tempo / loop length / quantize from the active sequence into the engine.
    private func configureSequencerFromActiveSequence() {
        let seq = project.sequences[project.activeSequence] ?? MMSequence()
        sequencer.setTempo(seq.bpm)
        sequencer.setLoop(bars: seq.bars,
                          numerator: project.timeSigNumerator,
                          denominator: project.timeSigDenominator)
        sequencer.setQuantize(division: seq.quantizeDivision, enabled: true)
        sequencer.setSwing(seq.swing)
        sequencer.loadEvents(seq.events)
    }

    func playSequence() {
        configureSequencerFromActiveSequence()
        sequencer.play()
    }

    func recordSequence() {
        configureSequencerFromActiveSequence()
        sequencer.record()
    }

    func stopTransport() {
        sequencer.stop()
        playheadTick = 0
    }

    func togglePlay() {
        if transport == .stopped { playSequence() } else { stopTransport() }
    }

    /// Tap-tempo state: recent tap timestamps (seconds).
    private var tapTimes: [Double] = []

    /// Register a tempo tap. Averages the last few inter-tap intervals into
    /// a BPM and applies it to the active sequence. Resets if you pause >2s.
    func tapTempo() {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
        if let last = tapTimes.last, now - last > 2.0 { tapTimes.removeAll() }
        tapTimes.append(now)
        if tapTimes.count > 5 { tapTimes.removeFirst(tapTimes.count - 5) }
        guard tapTimes.count >= 2 else { lastEvent = "Tap…"; return }

        var intervals: [Double] = []
        for i in 1..<tapTimes.count { intervals.append(tapTimes[i] - tapTimes[i - 1]) }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0 else { return }
        let bpm = (60.0 / avg).rounded()
        activeSequenceBPM = max(20, min(300, bpm))
        lastEvent = "Tap tempo → \(Int(activeSequenceBPM)) BPM"
    }

    var activeSequenceBPM: Double {
        get { project.sequences[project.activeSequence]?.bpm ?? project.globalBPM }
        set {
            project.sequences[project.activeSequence]?.bpm = newValue
            sequencer.setTempo(newValue)
        }
    }

    var activeSequenceBars: Int {
        get { project.sequences[project.activeSequence]?.bars ?? 4 }
        set {
            project.sequences[project.activeSequence]?.bars = newValue
            sequencer.setLoop(bars: newValue,
                              numerator: project.timeSigNumerator,
                              denominator: project.timeSigDenominator)
        }
    }

    var activeSequenceQuantize: Int {
        get { project.sequences[project.activeSequence]?.quantizeDivision ?? 16 }
        set {
            project.sequences[project.activeSequence]?.quantizeDivision = newValue
            sequencer.setQuantize(division: newValue, enabled: true)
        }
    }

    /// Swing 0…1 for the active sequence. Live — affects playback immediately.
    var activeSequenceSwing: Double {
        get { project.sequences[project.activeSequence]?.swing ?? 0 }
        set {
            project.sequences[project.activeSequence]?.swing = newValue
            sequencer.setSwing(newValue)
        }
    }

    /// 1-based bar.beat readout for the playhead.
    var playheadDisplay: String {
        let ticksPerBeat = Timing.ticksPerQuarter
        let beatsPerBar = project.timeSigNumerator
        let beat = playheadTick / ticksPerBeat
        let bar = beat / beatsPerBar
        let beatInBar = beat % beatsPerBar
        return String(format: "%03d.%d", bar + 1, beatInBar + 1)
    }

    // MARK: - Pad operations

    func selectAndTrigger(_ pad: PadAddress, velocity: UInt8 = 127) {
        if padFXActive {
            handlePadFXPress(pad.pad.raw)
            return
        }
        selectedPad = pad
        audio.triggerPad(pad, velocity: velocity)
        sequencer.recordHit(bank: pad.bank, pad: pad.pad, velocity: velocity)
    }

    // MARK: - Pad Play toggles (act on the selected pad)

    func toggleLoop() {
        project.pads[selectedPad]?.loop.toggle()
        syncPadToEngine(selectedPad)
    }

    func toggleReverse() {
        project.pads[selectedPad]?.reverse.toggle()
        syncPadToEngine(selectedPad)
    }

    func toggleNoteOn() {
        project.pads[selectedPad]?.noteOn.toggle()
        syncPadToEngine(selectedPad)
    }

    func toggleMute() {
        project.pads[selectedPad]?.muted.toggle()
        syncPadToEngine(selectedPad)
        refreshMF64LEDs()
    }

    func openBrowser() {
        browser.refresh()
        isBrowserOpen = true
    }

    // MARK: - Master compressor

    /// Push the project's compressor settings to the engine.
    func applyCompressor() {
        audio.setCompressor(project.compressor)
    }

    var compressorBinding: CompressorSettings {
        get { project.compressor }
        set {
            project.compressor = newValue
            applyCompressor()
        }
    }

    // MARK: - Lo-Fi

    var isLoFiOpen: Bool = false

    func applyLoFi() { audio.setLoFi(project.lofi) }

    // MARK: - Bounce (master output → WAV)

    var isBouncing: Bool = false
    private(set) var lastBounceURL: URL?

    /// Toggle master-output recording. Auto-names into ~/Music/Flipside/bounces.
    func toggleBounce() {
        if isBouncing {
            audio.stopOutputRecording()
            isBouncing = false
            if let url = lastBounceURL {
                lastEvent = "Bounced → \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Flipside/bounces", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let name = "\((project.name.isEmpty ? "Untitled" : project.name))-\(stamp).wav"
            let url = dir.appendingPathComponent(name)
            do {
                try audio.startOutputRecording(to: url)
                lastBounceURL = url
                isBouncing = true
                lastEvent = "Bouncing → \(name)"
            } catch {
                lastEvent = "Bounce failed: \(error.localizedDescription)"
            }
        }
    }

    var lofiBinding: LoFiSettings {
        get { project.lofi }
        set {
            project.lofi = newValue
            applyLoFi()
        }
    }

    // MARK: - Project save / load

    var currentProjectURL: URL?

    func newProject() {
        sequencer.stop()
        clearAllPadsInEngine()
        project = Project()
        currentProjectURL = nil
        selectedPad = PadAddress(bank: .A, pad: PadIndex(0))
        recomputeWaveform()
        refreshMF64LEDs()
        lastEvent = "New project"
    }

    func saveProject() {
        if let url = currentProjectURL { write(to: url) } else { presentSavePanel() }
    }

    func presentSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.name).\(ProjectStore.fileExtension)"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension != ProjectStore.fileExtension {
            url = url.appendingPathExtension(ProjectStore.fileExtension)
        }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try ProjectStore.save(project, to: url)
            currentProjectURL = url
            project.name = url.deletingPathExtension().lastPathComponent
            lastEvent = "Saved \(project.name)"
        } catch {
            lastEvent = "Save failed: \(error.localizedDescription)"
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    func loadProject(from url: URL) {
        do {
            let loaded = try ProjectStore.load(from: url)
            sequencer.stop()
            clearAllPadsInEngine()
            project = loaded
            currentProjectURL = url
            for (addr, pad) in project.pads {
                guard let sampleURL = pad.sampleURL else { continue }
                try? audio.loadSample(url: sampleURL, into: addr)
                syncPadToEngine(addr)
            }
            selectedPad = PadAddress(bank: .A, pad: PadIndex(0))
            recomputeWaveform()
            refreshMF64LEDs()
            applyCompressor()
            applyLoFi()
            lastEvent = "Loaded \(project.name)"
        } catch {
            lastEvent = "Load failed: \(error.localizedDescription)"
        }
    }

    private func clearAllPadsInEngine() {
        for bank in BankIndex.allCases {
            for i in 0..<16 {
                audio.clearPad(PadAddress(bank: bank, pad: PadIndex(i)))
            }
        }
    }

    func loadHighlightedToSelectedPad() {
        guard let entry = browser.highlightedEntry, entry.kind == .file else { return }
        do {
            try audio.loadSample(url: entry.url, into: selectedPad)
            project.pads[selectedPad]?.sampleURL = entry.url
            // Reset trim markers when a new sample lands.
            project.pads[selectedPad]?.start = 0
            project.pads[selectedPad]?.end = 1
            project.pads[selectedPad]?.loopStart = 0
            audio.stopPreview()
            recomputeWaveform()
            syncPadToEngine(selectedPad)
            refreshMF64LEDs()
            lastEvent = "Loaded \(entry.displayName) → \(selectedPad)"
        } catch {
            NSLog("loadSample failed: \(error)")
            lastEvent = "Load failed: \(error.localizedDescription)"
        }
    }

    /// Chop the selected pad's sample (honoring its current start/end) into
    /// slices and distribute them across pads 1..N of the selected pad's
    /// bank. Slices are baked to temp .wav files so they behave like any
    /// other loaded sample (sequencable, editable, saveable).
    func chopSelectedPad(_ type: ChopType) {
        guard let full = audio.buffer(for: selectedPad),
              let pad = project.pads[selectedPad] else {
            lastEvent = "Nothing to chop"
            return
        }
        let source: AVAudioPCMBuffer
        if pad.start > 0 || pad.end < 1 {
            source = AudioEngine.slice(full, startFraction: pad.start, endFraction: pad.end) ?? full
        } else {
            source = full
        }

        let ranges = Chopper.slices(buffer: source, type: type, maxSlices: 16)
        guard !ranges.isEmpty else { lastEvent = "Chop produced no slices"; return }

        let dir = chopsTempDir()
        let bank = selectedPad.bank
        var made = 0
        for (i, range) in ranges.enumerated() where i < 16 {
            guard let sliceBuf = AudioEngine.slice(source, startFraction: range.start, endFraction: range.end)
            else { continue }
            let url = dir.appendingPathComponent("slice\(i + 1).wav")
            do {
                try SampleLoader.write(sliceBuf, to: url)
                let dest = PadAddress(bank: bank, pad: PadIndex(i))
                try audio.loadSample(url: url, into: dest)
                project.pads[dest]?.sampleURL = url
                project.pads[dest]?.start = 0
                project.pads[dest]?.end = 1
                syncPadToEngine(dest)
                made += 1
            } catch {
                NSLog("chop slice \(i) failed: \(error)")
            }
        }
        selectedPad = PadAddress(bank: bank, pad: PadIndex(0))
        recomputeWaveform()
        refreshMF64LEDs()
        lastEvent = "Chopped into \(made) slices on bank \(bank)"
    }

    enum SixteenLevelsType: String, CaseIterable { case velocity, filter, tune }

    /// 16 Levels: copy the selected pad's sample across all 16 pads of its
    /// bank, varying one parameter. Tune puts the root on pad 4 (index 3).
    func applySixteenLevels(_ type: SixteenLevelsType) {
        guard let src = project.pads[selectedPad], let url = src.sampleURL else {
            lastEvent = "Load a sample first"
            return
        }
        let bank = selectedPad.bank
        for i in 0..<16 {
            let dest = PadAddress(bank: bank, pad: PadIndex(i))
            try? audio.loadSample(url: url, into: dest)
            var pad = src
            pad.sampleURL = url
            switch type {
            case .tune:
                pad.semiTune = i - 3                          // pad 4 (idx 3) = root
            case .velocity:
                let frac = Double(i + 1) / 16.0
                pad.volume_dB = -40.0 * (1.0 - frac)          // soft → full
            case .filter:
                pad.filterType = (src.filterType == .off) ? .lpf2 : src.filterType
                pad.filterCutoff = Double(i) / 15.0           // closed → open
            }
            project.pads[dest] = pad
            syncPadToEngine(dest)
        }
        selectedPad = PadAddress(bank: bank, pad: PadIndex(type == .tune ? 3 : 0))
        recomputeWaveform()
        refreshMF64LEDs()
        lastEvent = "16 Levels (\(type.rawValue)) on bank \(bank)"
    }

    private func chopsTempDir() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Flipside/chops/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Destructive trim — render [start, end] into a new buffer, replace
    /// the pad's buffer, and reset the trim markers. MPC SHIFT+pad-13.
    func commitTrim() {
        guard let buf = audio.buffer(for: selectedPad),
              let pad = project.pads[selectedPad] else {
            lastEvent = "Nothing to trim"
            return
        }
        guard let trimmed = AudioEngine.slice(buf, startFraction: pad.start, endFraction: pad.end) else {
            lastEvent = "Trim failed"
            return
        }
        audio.replaceBuffer(for: selectedPad, with: trimmed)
        project.pads[selectedPad]?.start = 0
        project.pads[selectedPad]?.end = 1
        project.pads[selectedPad]?.loopStart = 0
        recomputeWaveform()
        syncPadToEngine(selectedPad)
        lastEvent = "Trimmed \(selectedPad)"
    }

    /// Push the pad's playback params (start/end/gain/pan/reverse) to the
    /// audio engine so triggers — including from the MIDI thread — honor edits.
    private func syncPadToEngine(_ pad: PadAddress) {
        guard let p = project.pads[pad] else { return }
        var params = TriggerParams()
        params.startFraction = p.start
        params.endFraction = p.end
        params.gain = gainFromDB(p.volume_dB)
        params.pan = Float(max(-1, min(1, p.pan)))
        params.reverse = p.reverse
        params.pitchRatio = pitchRatio(semi: p.semiTune, fine: p.fineTune)
        params.filter = filterSpec(type: p.filterType, cutoff: p.filterCutoff, resonance: p.filterResonance)
        params.ampAttack = p.ampAttack
        params.ampDecay = p.ampDecayOrRelease
        params.loop = p.loop
        params.noteOn = p.noteOn
        params.muted = p.muted
        params.muteGroup = p.muteGroup
        audio.setTriggerParams(params, for: pad)
    }

    private func gainFromDB(_ dB: Double) -> Float {
        dB <= -74 ? 0 : Float(pow(10.0, dB / 20.0))
    }

    private func pitchRatio(semi: Int, fine: Int) -> Double {
        let semitones = Double(semi) + Double(fine) / 100.0
        return pow(2.0, semitones / 12.0)
    }

    /// Map a pad's filter settings to a bakeable FilterSpec (nil = bypass).
    /// Cutoff is a log sweep 20 Hz … 20 kHz; resonance maps to Q 0.7 … 12.
    private func filterSpec(type: Pad.FilterType, cutoff: Double, resonance: Double) -> FilterSpec? {
        let kind: Biquad.Kind
        let passes: Int
        switch type {
        case .off:                    return nil
        case .classic, .lpf2:         kind = .lowpass;  passes = 1
        case .lpf4:                   kind = .lowpass;  passes = 2
        case .hpf2:                   kind = .highpass; passes = 1
        case .hpf4:                   kind = .highpass; passes = 2
        case .bpf2:                   kind = .bandpass; passes = 1
        case .bpf4:                   kind = .bandpass; passes = 2
        }
        let c = max(0, min(1, cutoff))
        let cutoffHz = 20.0 * pow(1000.0, c)          // 20 Hz … 20 kHz
        let q = 0.7 + max(0, min(1, resonance)) * 11.3 // 0.7 … 12
        return FilterSpec(kind: kind, cutoffHz: cutoffHz, q: q, passes: passes)
    }

    private func recomputeWaveform() {
        guard let buf = audio.buffer(for: selectedPad) else {
            waveformPeaks = WaveformPeaks(peaks: [], frameCount: 0, sampleRate: 0)
            return
        }
        waveformPeaks = WaveformExtractor.extract(buffer: buf, bins: 600)
    }

    // MARK: - Page parameters

    struct PageParameter {
        let label: String
        let displayValue: String
        let normalisedValue: Double
    }

    var currentPageParameters: [PageParameter] {
        let pad = project.pads[selectedPad] ?? Pad()
        switch currentPage {
        case .trim:
            return [
                PageParameter(label: "Start", displayValue: percent(pad.start), normalisedValue: pad.start),
                PageParameter(label: "End",   displayValue: percent(pad.end),   normalisedValue: pad.end),
                PageParameter(label: "Loop",  displayValue: percent(pad.loopStart), normalisedValue: pad.loopStart),
            ]
        case .mix:
            return [
                PageParameter(label: "Volume", displayValue: dB(pad.volume_dB), normalisedValue: normaliseDB(pad.volume_dB)),
                PageParameter(label: "Pan",    displayValue: panLabel(pad.pan), normalisedValue: (pad.pan + 1) / 2),
                PageParameter(label: "—",      displayValue: "", normalisedValue: 0),
            ]
        case .ampEnv:
            return [
                PageParameter(label: "Attack",  displayValue: zeroOneToInt(pad.ampAttack), normalisedValue: pad.ampAttack),
                PageParameter(label: "Decay",   displayValue: zeroOneToInt(pad.ampDecayOrRelease), normalisedValue: pad.ampDecayOrRelease),
                PageParameter(label: "Vel Sens", displayValue: zeroOneToInt(pad.velocitySensitivity), normalisedValue: pad.velocitySensitivity),
            ]
        case .tune:
            return [
                PageParameter(label: "Semi", displayValue: semiLabel(pad.semiTune), normalisedValue: Double(pad.semiTune + 24) / 48),
                PageParameter(label: "Fine", displayValue: fineLabel(pad.fineTune), normalisedValue: Double(pad.fineTune + 90) / 180),
                PageParameter(label: "Warp", displayValue: warpLabel(pad.warp), normalisedValue: 0),
            ]
        case .play:
            return [
                PageParameter(label: "Poly", displayValue: pad.polyphony.rawValue, normalisedValue: pad.polyphony == .mono ? 0 : 1),
                PageParameter(label: "Mute G", displayValue: groupLabel(pad.muteGroup), normalisedValue: Double(pad.muteGroup) / 16),
                PageParameter(label: "Offset", displayValue: percent(pad.triggerOffset), normalisedValue: pad.triggerOffset),
            ]
        case .filter:
            return [
                PageParameter(label: "Cutoff", displayValue: zeroOneToInt(pad.filterCutoff), normalisedValue: pad.filterCutoff),
                PageParameter(label: "Reso",   displayValue: zeroOneToInt(pad.filterResonance), normalisedValue: pad.filterResonance),
                PageParameter(label: "Type",   displayValue: pad.filterType.rawValue.uppercased(), normalisedValue: filterTypeNormalised(pad.filterType)),
            ]
        case .fltEnv:
            return [
                PageParameter(label: "Attack", displayValue: zeroOneToInt(pad.filterAttack), normalisedValue: pad.filterAttack),
                PageParameter(label: "Decay",  displayValue: zeroOneToInt(pad.filterDecayOrRelease), normalisedValue: pad.filterDecayOrRelease),
                PageParameter(label: "Depth",  displayValue: zeroOneToInt(pad.filterEnvDepth), normalisedValue: pad.filterEnvDepth),
            ]
        }
    }

    /// Apply a normalised [0,1] value to the K1/K2/K3 slot of the current page.
    func setParameter(at slot: Int, normalised: Double) {
        guard project.pads[selectedPad] != nil else { return }
        let v = max(0, min(1, normalised))

        switch (currentPage, slot) {
        case (.trim, 0): project.pads[selectedPad]?.start = v
        case (.trim, 1): project.pads[selectedPad]?.end = v
        case (.trim, 2): project.pads[selectedPad]?.loopStart = v

        case (.mix, 0): project.pads[selectedPad]?.volume_dB = denormaliseDB(v)
        case (.mix, 1): project.pads[selectedPad]?.pan = v * 2 - 1

        case (.ampEnv, 0): project.pads[selectedPad]?.ampAttack = v
        case (.ampEnv, 1): project.pads[selectedPad]?.ampDecayOrRelease = v
        case (.ampEnv, 2): project.pads[selectedPad]?.velocitySensitivity = v

        case (.tune, 0): project.pads[selectedPad]?.semiTune = Int(round(v * 48 - 24))
        case (.tune, 1): project.pads[selectedPad]?.fineTune = Int(round(v * 180 - 90))

        case (.play, 0): project.pads[selectedPad]?.polyphony = v < 0.5 ? .mono : .poly
        case (.play, 1): project.pads[selectedPad]?.muteGroup = Int(round(v * 16))
        case (.play, 2): project.pads[selectedPad]?.triggerOffset = v

        case (.filter, 0): project.pads[selectedPad]?.filterCutoff = v
        case (.filter, 1): project.pads[selectedPad]?.filterResonance = v
        case (.filter, 2): project.pads[selectedPad]?.filterType = filterTypeFromNormalised(v)

        case (.fltEnv, 0): project.pads[selectedPad]?.filterAttack = v
        case (.fltEnv, 1): project.pads[selectedPad]?.filterDecayOrRelease = v
        case (.fltEnv, 2): project.pads[selectedPad]?.filterEnvDepth = v

        default: break
        }

        // Push start/end/volume/pan/reverse to the engine so the change is
        // audible on the next trigger. (Pitch/filter/envelope DSP still TODO.)
        syncPadToEngine(selectedPad)
    }

    // MARK: - Formatters

    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private func dB(_ v: Double) -> String {
        if v <= -74 { return "-INF" }
        return String(format: "%+.1f dB", v)
    }
    private func normaliseDB(_ dB: Double) -> Double { (dB + 74) / 80 }
    private func denormaliseDB(_ n: Double) -> Double { n * 80 - 74 }
    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.01 { return "C" }
        return pan < 0
            ? String(format: "%dL", Int(-pan * 50))
            : String(format: "%dR", Int(pan * 50))
    }
    private func zeroOneToInt(_ v: Double) -> String { "\(Int(round(v * 127)))" }
    private func semiLabel(_ s: Int) -> String { s >= 0 ? "+\(s)" : "\(s)" }
    private func fineLabel(_ f: Int) -> String { f >= 0 ? "+\(f)c" : "\(f)c" }
    private func groupLabel(_ g: Int) -> String { g == 0 ? "Off" : "\(g)" }
    private func warpLabel(_ w: Pad.Warp) -> String {
        switch w {
        case .off: return "Off"
        case .timeStretch(let p): return "TS \(Int(p))%"
        case .pitch(let p):       return "P \(Int(p))%"
        case .seq:                return "Seq"
        }
    }

    private func filterTypeNormalised(_ type: Pad.FilterType) -> Double {
        guard let idx = Pad.FilterType.allCases.firstIndex(of: type) else { return 0 }
        let count = max(1, Pad.FilterType.allCases.count - 1)
        return Double(idx) / Double(count)
    }
    private func filterTypeFromNormalised(_ v: Double) -> Pad.FilterType {
        let cases = Pad.FilterType.allCases
        let idx = max(0, min(cases.count - 1, Int(round(v * Double(cases.count - 1)))))
        return cases[idx]
    }

    // MARK: - MIDI wiring

    private func startMF64() {
        let mf64 = MidiFighter64(
            onEvent: { [weak self] event in
                guard let self else { return }
                Task { @MainActor in self.handleMF(event) }
            },
            onFastTrigger: { [weak self] coord, velocity in
                guard let self else { return }
                let addr = PadMapping.address(for: coord)
                self.audio.triggerPad(addr, velocity: velocity)
                self.sequencer.recordHit(bank: addr.bank, pad: addr.pad, velocity: velocity)
            }
        )
        do {
            try mf64.start()
            self.mf64 = mf64
        } catch {
            NSLog("MF64 start failed: \(error)")
        }
    }

    private func startNano() {
        let nano = KorgNanoKontrol { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handleNano(event) }
        }
        do {
            try nano.start()
            self.nano = nano
        } catch {
            NSLog("nanoKONTROL start failed: \(error)")
        }
    }

    /// Paint the MF64 pad LEDs: selected pad white, loaded pads in their
    /// bank colour, empty pads off.
    func refreshMF64LEDs() {
        guard let mf64, mf64.isConnected else { return }
        let project = self.project
        let selected = self.selectedPad
        mf64.setAllPadColors { coord in
            let addr = PadMapping.address(for: coord)
            if addr == selected { return .white }
            if project.pads[addr]?.sampleURL != nil { return Self.bankColor(addr.bank) }
            return .off
        }
    }

    private static func bankColor(_ bank: BankIndex) -> PadColor {
        switch bank {
        case .A: return .red
        case .B: return .orange
        case .C: return .yellow
        case .D: return .green
        case .E: return .mint
        case .F: return .cyan
        case .G: return .blue
        case .H: return .violet
        }
    }

    private func handleMF(_ event: MidiFighter64.Event) {
        switch event {
        case .connected(let name):
            mf64Status = .connected(name: name)
            refreshMF64LEDs()
        case .disconnected:
            mf64Status = .disconnected
        case .padPressed(let coord, _, let vel):
            pressedCoords.insert(coord)
            let addr = PadMapping.address(for: coord)
            if padFXActive {
                handlePadFXPress(addr.pad.raw)
            } else {
                selectedPad = addr
            }
            lastEvent = "MF64 press \(coord) vel \(vel)"
        case .padReleased(let coord, _):
            pressedCoords.remove(coord)
            let addr = PadMapping.address(for: coord)
            // Note-On pads gate: stop the voice when the pad is released.
            if project.pads[addr]?.noteOn == true { audio.stopPad(addr) }
            lastEvent = "MF64 release \(coord)"
        case .unknownNote(let note, let vel):
            lastEvent = "MF64 unknown note \(note) vel \(vel)"
        }
    }

    private func handleNano(_ event: KorgNanoKontrol.Event) {
        switch event {
        case .connected(let name):
            nanoStatus = .connected(name: name)
        case .disconnected:
            nanoStatus = .disconnected
        case .controlChange(_, let cc, let val):
            routeNanoCC(cc: cc, value: val)
        case .note(let ch, let note, let vel, let on):
            lastEvent = "nano \(on ? "on" : "off") ch=\(ch) note=\(note) vel=\(vel)"
        case .sysEx(let bytes):
            lastEvent = "nano SysEx \(bytes.count) bytes"
        }
    }

    /// Map an incoming nanoKONTROL CC to a Flipside action.
    /// Knobs/sliders are absolute (0…127) — used directly as normalised
    /// values (soft-takeover can come later). Transport buttons send 127
    /// on press, 0 on release; we act on press.
    private func routeNanoCC(cc: UInt8, value: UInt8) {
        let norm = Double(value) / 127.0
        switch cc {
        case NanoCC.k1: setParameter(at: 0, normalised: norm)
        case NanoCC.k2: setParameter(at: 1, normalised: norm)
        case NanoCC.k3: setParameter(at: 2, normalised: norm)

        case NanoCC.dataWheel:
            // Knob 9 acts as the "data wheel": when the browser is open its
            // absolute position scrolls the list.
            if isBrowserOpen, !browser.entries.isEmpty {
                let idx = Int((norm * Double(browser.entries.count - 1)).rounded())
                browser.highlightedIndex = max(0, min(browser.entries.count - 1, idx))
            }

        case NanoCC.fader:
            // Fader → selected pad volume (default fader assignment).
            project.pads[selectedPad]?.volume_dB = (norm * 80) - 74
            syncPadToEngine(selectedPad)

        case NanoCC.play where value == 127:
            togglePlay()
        case NanoCC.stop where value == 127:
            stopTransport()
        case NanoCC.rec where value == 127:
            if transport == .recording { stopTransport() } else { recordSequence() }

        default:
            lastEvent = "nano CC \(cc) = \(value)"
        }
    }
}
