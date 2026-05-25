import SwiftUI
import MMModels

struct KnobFXView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        let labels = state.knobFXType.knobLabels

        VStack(spacing: 18) {
            HStack {
                Text("Knob FX")
                    .font(.system(.headline, design: .monospaced, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Picker("", selection: $state.knobFXType) {
                    ForEach(KnobFXType.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack(spacing: 34) {
                if !labels.0.isEmpty {
                    KnobView(label: labels.0, value: $state.knobFXK1,
                             displayValue: pct(state.knobFXK1))
                }
                if !labels.1.isEmpty {
                    KnobView(label: labels.1, value: $state.knobFXK2,
                             displayValue: pct(state.knobFXK2))
                }
                if !labels.2.isEmpty {
                    KnobView(label: labels.2, value: $state.knobFXK3,
                             displayValue: pct(state.knobFXK3))
                }
                if state.knobFXType == .none {
                    Text("Select an effect")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(height: 90)
                }
            }
            .frame(minHeight: 100)

            HStack {
                Text("Applied to master bus")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(white: 0.10))
    }

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
