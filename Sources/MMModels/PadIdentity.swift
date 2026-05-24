import Foundation

/// One of the eight pad banks (A–H), matching the MPC Sample.
public enum BankIndex: Int, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case A = 0, B, C, D, E, F, G, H

    public var description: String { String(UnicodeScalar(UInt8(ascii: "A") + UInt8(rawValue))) }
}

/// Position of a pad inside a bank (0-15). MPC labels these 1-16 in the
/// physical layout:
///
///     13 14 15 16
///      9 10 11 12
///      5  6  7  8
///      1  2  3  4
public struct PadIndex: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int  // 0..<16

    public init(_ raw: Int) {
        precondition((0..<16).contains(raw), "PadIndex out of range: \(raw)")
        self.raw = raw
    }

    /// Row (0 = bottom row containing pads 1-4, 3 = top row).
    public var row: Int { raw / 4 }
    /// Column (0 = leftmost).
    public var col: Int { raw % 4 }
    /// 1-based label as shown on the MPC pads.
    public var label: Int { raw + 1 }

    public var description: String { "\(label)" }
}

/// Fully-qualified pad address: which bank + which pad within it.
/// One per addressable slot in the project (128 total = 16 × 8).
public struct PadAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    public let bank: BankIndex
    public let pad: PadIndex

    public init(bank: BankIndex, pad: PadIndex) {
        self.bank = bank
        self.pad = pad
    }

    public var description: String { "\(bank)\(pad.label)" }
}
