import Foundation

/// One pad position on the MF64's 8×8 grid. Row 0 = top, col 0 = leftmost.
public struct PadCoord: Hashable, Sendable, Codable, CustomStringConvertible {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        precondition((0..<8).contains(row) && (0..<8).contains(col),
                     "PadCoord out of range: \(row),\(col)")
        self.row = row
        self.col = col
    }

    public var description: String { "(\(row),\(col))" }
}

/// One of the four 4×4 quadrants of the MF64 grid.
/// In `mac-mpc` these double as bank selectors — each quadrant maps to one
/// MPC bank, so four banks are visible at once with no bank-switch needed.
public enum Quadrant: Int, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public static func containing(row: Int, col: Int) -> Quadrant {
        switch (row < 4, col < 4) {
        case (true,  true):  return .topLeft
        case (true,  false): return .topRight
        case (false, true):  return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    public var label: String {
        switch self {
        case .topLeft:     return "Q1"
        case .topRight:    return "Q2"
        case .bottomLeft:  return "Q3"
        case .bottomRight: return "Q4"
        }
    }

    /// (row, col) of the quadrant's top-left corner.
    public var origin: (row: Int, col: Int) {
        switch self {
        case .topLeft:     return (0, 0)
        case .topRight:    return (0, 4)
        case .bottomLeft:  return (4, 0)
        case .bottomRight: return (4, 4)
        }
    }
}

/// Default Midi Fighter 64 note layout (verified empirically against firmware).
///
/// Notes 36..99 fill the grid one quadrant at a time, in this order:
///   1. bottom-left  (notes 36..51)
///   2. top-left     (notes 52..67)
///   3. bottom-right (notes 68..83)
///   4. top-right    (notes 84..99)
///
/// Within each quadrant, scanning starts at the quadrant's bottom-left,
/// fills the bottom row left-to-right, then steps up a row, etc. — so the
/// top-right pad of each quadrant holds the highest note in that quadrant.
public enum MFNoteMap {
    public static let baseNote: UInt8 = 36

    private static let quadrantSequence: [Quadrant] = [
        .bottomLeft, .topLeft, .bottomRight, .topRight
    ]

    public static func note(for pad: PadCoord) -> UInt8 {
        let q = Quadrant.containing(row: pad.row, col: pad.col)
        let qIndex = quadrantSequence.firstIndex(of: q) ?? 0
        let localRow = pad.row % 4
        let localCol = pad.col % 4
        let rowFromBottomOfQuadrant = 3 - localRow
        let withinQuadrant = rowFromBottomOfQuadrant * 4 + localCol
        return baseNote &+ UInt8(qIndex * 16 + withinQuadrant)
    }

    public static func pad(for note: UInt8) -> PadCoord? {
        let offset = Int(note) - Int(baseNote)
        guard (0..<64).contains(offset) else { return nil }
        let qIndex = offset / 16
        let withinQuadrant = offset % 16
        let q = quadrantSequence[qIndex]
        let rowFromBottomOfQuadrant = withinQuadrant / 4
        let localCol = withinQuadrant % 4
        let localRow = 3 - rowFromBottomOfQuadrant
        let qOrigin = q.origin
        return PadCoord(row: qOrigin.row + localRow, col: qOrigin.col + localCol)
    }
}
