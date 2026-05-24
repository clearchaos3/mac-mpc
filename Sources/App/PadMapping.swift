import Foundation
import MMMidi
import MMModels

/// Bridge between the MF64's 8×8 grid and MPC-style banks/pads.
///
/// Each quadrant of the MF64 grid maps to one MPC bank — so four banks
/// are visible on the device at once without bank-switching:
///
///   bottom-left  → Bank A
///   bottom-right → Bank B
///   top-left     → Bank C
///   top-right    → Bank D
///
/// Within each 4×4 quadrant, pad labels follow the MPC layout (1-16
/// counted bottom-left to top-right):
///
///   13 14 15 16
///    9 10 11 12
///    5  6  7  8
///    1  2  3  4
enum PadMapping {

    static let quadrantBank: [Quadrant: BankIndex] = [
        .bottomLeft:  .A,
        .bottomRight: .B,
        .topLeft:     .C,
        .topRight:    .D,
    ]

    static func address(for coord: PadCoord) -> PadAddress {
        let q = Quadrant.containing(row: coord.row, col: coord.col)
        let bank = quadrantBank[q]!
        let origin = q.origin
        let localRow = coord.row - origin.row   // 0 = top of quadrant
        let localCol = coord.col - origin.col   // 0 = left of quadrant
        // MPC label = (rows-from-bottom)*4 + col + 1
        let label = (3 - localRow) * 4 + localCol + 1
        return PadAddress(bank: bank, pad: PadIndex(label - 1))
    }

    static func coord(for address: PadAddress) -> PadCoord? {
        guard let q = quadrantBank.first(where: { $0.value == address.bank })?.key else { return nil }
        let origin = q.origin
        let label = address.pad.label
        let localRow = 3 - ((label - 1) / 4)
        let localCol = (label - 1) % 4
        return PadCoord(row: origin.row + localRow, col: origin.col + localCol)
    }
}
