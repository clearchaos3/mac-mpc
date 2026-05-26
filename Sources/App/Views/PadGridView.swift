import SwiftUI
import MMMidi
import MMModels

/// 8×8 pad grid mirroring the MF64. Pad fill colors come from the SAME
/// `ledColor` source that drives the hardware LEDs, so the screen always
/// matches the physical pads: lit/playing = white, muted = dim red, loaded =
/// bank color, empty = dark. The selected pad gets a yellow outline (an
/// on-screen-only editing cursor). Clicking a pad selects + triggers it.
struct PadGridView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<8) { row in
                HStack(spacing: 8) {
                    ForEach(0..<8) { col in
                        let coord = PadCoord(row: row, col: col)
                        let address = PadMapping.address(for: coord)
                        let led = state.ledColor(for: address)
                        PadCell(
                            address: address,
                            fill: Self.color(led),
                            textColor: Self.textColor(led),
                            selected: state.selectedPad == address,
                            shiftLabel: state.shiftActive ? AppState.shiftLabels[address.pad.raw] : nil
                        )
                        .onTapGesture {
                            if state.shiftActive {
                                state.handleShiftPad(address.pad.raw)
                            } else {
                                state.selectAndTrigger(address)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: .rect(cornerRadius: 12))
    }

    /// Convert an MF64 palette color to a SwiftUI Color (exact LED match).
    /// `.off` renders as a dark neutral so empty pads read as recessed.
    static func color(_ padColor: PadColor) -> Color {
        let rgb = padColor.rgb
        if rgb == (0, 0, 0) { return Color(white: 0.16) }
        return Color(.sRGB,
                     red: Double(rgb.r) / 255.0,
                     green: Double(rgb.g) / 255.0,
                     blue: Double(rgb.b) / 255.0)
    }

    /// Black label on bright pads, white on dark/empty ones, by luminance.
    static func textColor(_ padColor: PadColor) -> Color {
        let rgb = padColor.rgb
        let lum = (0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)) / 255.0
        return lum > 0.55 ? .black.opacity(0.7) : .white.opacity(0.75)
    }
}

private struct PadCell: View {
    let address: PadAddress
    let fill: Color
    let textColor: Color
    let selected: Bool
    var shiftLabel: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(shiftLabel != nil ? Color.indigo.opacity(0.30) : fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.yellow : Color.white.opacity(0.12),
                                lineWidth: selected ? 2.5 : 1)
                )

            if let shiftLabel {
                Text(shiftLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(2)
            } else {
                VStack(spacing: 2) {
                    Text(address.bank.description)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.85))
                    Text("\(address.pad.label)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(textColor)
                }
            }
        }
        .frame(width: 64, height: 64)
        .animation(.easeOut(duration: 0.08), value: fill)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
