import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 14) {
            header
            DisplayPanelView()
            TransportView()
            padPlay
            PadGridView()
            controls
            statusBar
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 1100)
        .background(Color(white: 0.08))
        .sheet(isPresented: $state.isCompressorOpen) {
            CompressorView()
                .environment(state)
        }
        .sheet(isPresented: $state.isKnobFXOpen) {
            KnobFXView()
                .environment(state)
        }
        .sheet(isPresented: $state.isLoFiOpen) {
            LoFiView()
                .environment(state)
        }
        .sheet(isPresented: $state.isSongOpen) {
            SongView()
                .environment(state)
        }
    }

    private var padPlay: some View {
        let pad = state.project.pads[state.selectedPad]
        return HStack(spacing: 10) {
            Text("PAD PLAY")
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                .foregroundStyle(.white.opacity(0.4))
            padPlayToggle("Loop", system: "repeat", on: pad?.loop ?? false) { state.toggleLoop() }
            padPlayToggle("Reverse", system: "arrow.uturn.backward", on: pad?.reverse ?? false) { state.toggleReverse() }
            padPlayToggle("Note On", system: "hand.point.up.left", on: pad?.noteOn ?? false) { state.toggleNoteOn() }
            padPlayToggle("Mute", system: "speaker.slash", on: pad?.muted ?? false) { state.toggleMute() }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.12), in: .rect(cornerRadius: 10))
    }

    private func padPlayToggle(_ label: String, system: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system)
                .font(.system(.caption, design: .monospaced, weight: on ? .bold : .regular))
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.cyan : Color.white.opacity(0.08), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(state.project.pads[state.selectedPad]?.sampleURL == nil)
    }

    private var header: some View {
        HStack {
            Text("Flipside")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            connectionBadge("MF64", state.mf64Status)
            connectionBadge("nano", state.nanoStatus)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                state.openBrowser()
            } label: {
                Label("Sample Select", systemImage: "waveform.path.badge.plus")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)
            .keyboardShortcut("b", modifiers: [.command])

            Button {
                state.commitTrim()
            } label: {
                Label("Trim Sample", systemImage: "scissors")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(state.project.pads[state.selectedPad]?.sampleURL == nil)

            Menu {
                let bpm = state.activeSequenceBPM
                Section("Tempo grid (\(Int(bpm)) BPM)") {
                    Button("1 bar / slice")  { state.chopSelectedPad(.grid(bpm: bpm, beatsPerSlice: 4)) }
                    Button("½ bar / slice")  { state.chopSelectedPad(.grid(bpm: bpm, beatsPerSlice: 2)) }
                    Button("1 beat / slice") { state.chopSelectedPad(.grid(bpm: bpm, beatsPerSlice: 1)) }
                }
                Section("Equal regions") {
                    Button("Regions: 2")  { state.chopSelectedPad(.regions(2)) }
                    Button("Regions: 4")  { state.chopSelectedPad(.regions(4)) }
                    Button("Regions: 8")  { state.chopSelectedPad(.regions(8)) }
                    Button("Regions: 16") { state.chopSelectedPad(.regions(16)) }
                }
                Section("Transient (rhythmic)") {
                    Button("Threshold (more)") { state.chopSelectedPad(.threshold(0.2)) }
                    Button("Threshold (med)")  { state.chopSelectedPad(.threshold(0.5)) }
                    Button("Threshold (fewer)"){ state.chopSelectedPad(.threshold(0.8)) }
                }
            } label: {
                Label("Chop", systemImage: "square.split.2x2")
                    .font(.system(.body, design: .monospaced))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(state.project.pads[state.selectedPad]?.sampleURL == nil)

            Menu {
                Button("Velocity") { state.applySixteenLevels(.velocity) }
                Button("Filter")   { state.applySixteenLevels(.filter) }
                Button("Tune")     { state.applySixteenLevels(.tune) }
            } label: {
                Label("16 Lvl", systemImage: "square.grid.4x3.fill")
                    .font(.system(.body, design: .monospaced))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(state.project.pads[state.selectedPad]?.sampleURL == nil)

            Button {
                state.isCompressorOpen = true
            } label: {
                Label("Comp", systemImage: "waveform.badge.minus")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)

            Button {
                state.isLoFiOpen = true
            } label: {
                Label("Lo-Fi", systemImage: "circle.dotted")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(state.lofiBinding.enabled ? Color.orange : Color.white)
            }
            .controlSize(.large)

            Button {
                state.isKnobFXOpen = true
            } label: {
                Label("Knob FX", systemImage: "dial.medium")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)

            Button {
                state.togglePadFXMode()
            } label: {
                Label("Pad FX", systemImage: "square.grid.3x3.middle.filled")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(state.padFXActive ? Color.black : Color.white)
            }
            .controlSize(.large)
            .tint(state.padFXActive ? .orange : nil)
            .buttonStyle(.borderedProminent)
            .opacity(state.padFXActive ? 1 : 0.85)

            Button {
                state.isSongOpen = true
            } label: {
                Label("Song", systemImage: "music.note.list")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)

            Button {
                state.testLEDs()
            } label: {
                Label("Test LEDs", systemImage: "lightbulb")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)
            .help("Paint all MF64 rings white + show the output channel (LED diagnostic)")

            Button {
                state.shiftActive.toggle()
            } label: {
                Label("SHIFT", systemImage: "shift")
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(state.shiftActive ? Color.black : Color.white)
            }
            .controlSize(.large)
            .tint(state.shiftActive ? .indigo : nil)
            .buttonStyle(.borderedProminent)
            .help("Show secondary pad functions")

            Text(state.selectedPad.description)
                .font(.system(.body, design: .monospaced, weight: .heavy))
                .foregroundStyle(.yellow)

            Spacer()

            Text(state.currentProjectURL?.deletingPathExtension().lastPathComponent ?? "unsaved")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.lastEvent)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(height: 22)
    }

    private func connectionBadge(_ label: String, _ status: AppState.ConnectionStatus) -> some View {
        let connected: Bool = { if case .connected = status { true } else { false } }()
        return HStack(spacing: 6) {
            Circle()
                .fill(connected ? .green : .red.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: .capsule)
    }
}
