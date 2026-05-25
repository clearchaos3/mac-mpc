import SwiftUI
import MMModels

struct LoFiView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 18) {
            HStack {
                Text("Lo-Fi")
                    .font(.system(.headline, design: .monospaced, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("Bypass", isOn: Binding(
                    get: { !state.lofiBinding.enabled },
                    set: { state.lofiBinding.enabled = !$0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 34) {
                KnobView(label: "Tone", value: Binding(
                    get: { state.lofiBinding.tone },
                    set: { state.lofiBinding.tone = $0 }),
                    displayValue: pct(state.lofiBinding.tone))

                KnobView(label: "Drive", value: Binding(
                    get: { state.lofiBinding.drive },
                    set: { state.lofiBinding.drive = $0 }),
                    displayValue: pct(state.lofiBinding.drive))

                KnobView(label: "Noise", value: Binding(
                    get: { state.lofiBinding.noise },
                    set: { state.lofiBinding.noise = $0 }),
                    displayValue: pct(state.lofiBinding.noise))
            }

            HStack {
                Text("Tone darkens • Drive saturates • Noise = vinyl crackle")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(white: 0.10))
    }

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
