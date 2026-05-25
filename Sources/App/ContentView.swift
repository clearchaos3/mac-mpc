import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 14) {
            header
            DisplayPanelView()
            TransportView()
            PadGridView()
            controls
            statusBar
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 1100)
        .background(Color(white: 0.08))
        .sheet(isPresented: $state.isBrowserOpen) {
            SampleBrowserView()
                .environment(state)
        }
        .sheet(isPresented: $state.isCompressorOpen) {
            CompressorView()
                .environment(state)
        }
        .sheet(isPresented: $state.isKnobFXOpen) {
            KnobFXView()
                .environment(state)
        }
    }

    private var header: some View {
        HStack {
            Text("mac-mpc")
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
                Button("Regions: 2")  { state.chopSelectedPad(.regions(2)) }
                Button("Regions: 4")  { state.chopSelectedPad(.regions(4)) }
                Button("Regions: 8")  { state.chopSelectedPad(.regions(8)) }
                Button("Regions: 16") { state.chopSelectedPad(.regions(16)) }
                Divider()
                Button("Threshold (more)") { state.chopSelectedPad(.threshold(0.2)) }
                Button("Threshold (med)")  { state.chopSelectedPad(.threshold(0.5)) }
                Button("Threshold (fewer)"){ state.chopSelectedPad(.threshold(0.8)) }
            } label: {
                Label("Chop", systemImage: "square.split.2x2")
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
                state.isKnobFXOpen = true
            } label: {
                Label("Knob FX", systemImage: "dial.medium")
                    .font(.system(.body, design: .monospaced))
            }
            .controlSize(.large)

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
