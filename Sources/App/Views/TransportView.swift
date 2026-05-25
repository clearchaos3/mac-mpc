import SwiftUI
import MMAudio

struct TransportView: View {
    @Environment(AppState.self) private var state

    private let quantizeOptions = [4, 8, 16, 32, 64]

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 16) {
            transportButtons

            Divider().frame(height: 30).overlay(Color.white.opacity(0.15))

            // BPM
            field(label: "BPM") {
                HStack(spacing: 4) {
                    Text(String(format: "%.0f", state.activeSequenceBPM))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 42)
                    Stepper("", value: Binding(
                        get: { state.activeSequenceBPM },
                        set: { state.activeSequenceBPM = $0 }),
                        in: 20...300, step: 1)
                        .labelsHidden()
                }
            }

            // Bars
            field(label: "Bars") {
                Picker("", selection: Binding(
                    get: { state.activeSequenceBars },
                    set: { state.activeSequenceBars = $0 })) {
                    ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 60)
            }

            // Tap tempo
            field(label: "Tap") {
                Button {
                    state.tapTempo()
                } label: {
                    Image(systemName: "hand.tap")
                        .frame(width: 22, height: 18)
                }
                .controlSize(.large)
                .keyboardShortcut("t", modifiers: [])
                .help("Tap tempo")
            }

            // Quantize
            field(label: "Q") {
                Picker("", selection: Binding(
                    get: { state.activeSequenceQuantize },
                    set: { state.activeSequenceQuantize = $0 })) {
                    ForEach(quantizeOptions, id: \.self) { Text("1/\($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 72)
            }

            Divider().frame(height: 30).overlay(Color.white.opacity(0.15))

            // Playhead
            field(label: "Pos") {
                Text(state.playheadDisplay)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(transportColor)
                    .frame(minWidth: 64, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.12), in: .rect(cornerRadius: 10))
    }

    private var transportButtons: some View {
        HStack(spacing: 8) {
            // Play / Stop
            Button {
                state.togglePlay()
            } label: {
                Image(systemName: state.transport == .stopped ? "play.fill" : "stop.fill")
                    .frame(width: 18)
            }
            .help(state.transport == .stopped ? "Play" : "Stop")

            // Record
            Button {
                if state.transport == .recording {
                    state.stopTransport()
                } else {
                    state.recordSequence()
                }
            } label: {
                Image(systemName: "record.circle")
                    .foregroundStyle(state.transport == .recording ? Color.red : Color.white)
                    .frame(width: 18)
            }
            .help("Record")
        }
        .controlSize(.large)
        .font(.title3)
    }

    private var transportColor: Color {
        switch state.transport {
        case .stopped: return .white.opacity(0.6)
        case .playing: return .green
        case .recording: return .red
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            content()
        }
    }
}
