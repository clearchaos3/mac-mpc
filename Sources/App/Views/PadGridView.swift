import SwiftUI
import MMMidi

/// 8×8 pad grid mirroring the MF64. Each 4×4 quadrant is tinted to indicate
/// which MPC bank it maps to (A bottom-left, B bottom-right, C top-left,
/// D top-right). Pads flash white when held down on the hardware.
struct PadGridView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<8) { row in
                HStack(spacing: 8) {
                    ForEach(0..<8) { col in
                        let coord = PadCoord(row: row, col: col)
                        PadCell(coord: coord, pressed: state.pressedCoords.contains(coord))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: .rect(cornerRadius: 12))
    }
}

private struct PadCell: View {
    let coord: PadCoord
    let pressed: Bool

    var body: some View {
        let address = PadMapping.address(for: coord)
        let bankColor = Self.color(for: address.bank.rawValue)

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(pressed ? Color.white : bankColor.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(bankColor.opacity(0.6), lineWidth: 1)
                )

            VStack(spacing: 2) {
                Text(address.bank.description)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle((pressed ? Color.black : Color.white).opacity(0.7))
                Text("\(address.pad.label)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle((pressed ? Color.black : Color.white).opacity(0.85))
            }
        }
        .frame(width: 64, height: 64)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    static func color(for bankIndex: Int) -> Color {
        switch bankIndex % 8 {
        case 0: return .red       // A
        case 1: return .orange    // B
        case 2: return .yellow    // C
        case 3: return .green     // D
        case 4: return .mint
        case 5: return .cyan
        case 6: return .blue
        case 7: return .purple
        default: return .gray
        }
    }
}
