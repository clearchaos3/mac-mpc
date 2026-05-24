import Foundation
import Observation
import AVFoundation
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
            if selectedPad != oldValue { recomputeWaveform() }
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

    var lastEvent: String = "—"

    enum ConnectionStatus: Equatable {
        case disconnected
        case connected(name: String)
    }

    init() {
        audio.start()
        browser = SampleBrowser(audio: audio)
    }

    func start() {
        startMF64()
        startNano()
    }

    // MARK: - Pad operations

    func selectAndTrigger(_ pad: PadAddress, velocity: UInt8 = 127) {
        selectedPad = pad
        audio.triggerPad(pad, velocity: velocity)
    }

    func openBrowser() {
        browser.refresh()
        isBrowserOpen = true
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
            lastEvent = "Loaded \(entry.displayName) → \(selectedPad)"
        } catch {
            NSLog("loadSample failed: \(error)")
            lastEvent = "Load failed: \(error.localizedDescription)"
        }
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
        lastEvent = "Trimmed \(selectedPad)"
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

    private func handleMF(_ event: MidiFighter64.Event) {
        switch event {
        case .connected(let name):
            mf64Status = .connected(name: name)
        case .disconnected:
            mf64Status = .disconnected
        case .padPressed(let coord, _, let vel):
            pressedCoords.insert(coord)
            selectedPad = PadMapping.address(for: coord)
            lastEvent = "MF64 press \(coord) vel \(vel)"
        case .padReleased(let coord, _):
            pressedCoords.remove(coord)
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
        case .controlChange(let ch, let cc, let val):
            lastEvent = "nano CC ch=\(ch) cc=\(cc) val=\(val)"
        case .note(let ch, let note, let vel, let on):
            lastEvent = "nano \(on ? "on" : "off") ch=\(ch) note=\(note) vel=\(vel)"
        case .sysEx(let bytes):
            lastEvent = "nano SysEx \(bytes.count) bytes"
        }
    }
}
