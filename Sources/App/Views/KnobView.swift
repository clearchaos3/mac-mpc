import SwiftUI

/// A simple rotary knob. Drag vertically to change the value.
/// Range is normalised [0, 1]; callers map to whatever they need.
struct KnobView: View {
    let label: String
    @Binding var value: Double
    let displayValue: String
    var tint: Color = .yellow
    var size: CGFloat = 56

    @State private var dragStartValue: Double?

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.06)],
                        startPoint: .top, endPoint: .bottom))
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)

                // Value arc.
                Circle()
                    .trim(from: 0, to: max(0.001, value))
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Pointer.
                Rectangle()
                    .fill(tint)
                    .frame(width: 2.5, height: size * 0.28)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(-135 + value * 270))
            }
            .frame(width: size, height: size)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = -Double(drag.translation.height) / 200.0
                        value = max(0, min(1, (dragStartValue ?? 0) + delta))
                    }
                    .onEnded { _ in dragStartValue = nil }
            )

            Text(displayValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 50)
        }
    }
}
