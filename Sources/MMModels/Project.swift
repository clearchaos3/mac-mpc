import Foundation

/// Root project state. One of these per loaded `.macmpc` document.
public struct Project: Hashable, Codable, Sendable {
    public var name: String = "Untitled"

    /// All 128 pads (8 banks × 16 pads), indexed by `PadAddress`.
    public var pads: [PadAddress: Pad] = [:]

    /// Sequence slots: 8 banks × 16 sequences each. Same A1..H16 addressing
    /// scheme as pads. Empty sequences are still present (so the grid is
    /// always fully populated).
    public var sequences: [PadAddress: MMSequence] = [:]

    /// Globally selected sequence — what the transport plays/records into.
    public var activeSequence: PadAddress

    /// Project-wide tempo when not in per-sequence (SEQ) BPM mode.
    public var globalBPM: Double = 90.0

    /// Time signature numerator / denominator. MPC ties all sequences to one.
    public var timeSigNumerator: Int = 4
    public var timeSigDenominator: Int = 4

    /// Master-bus color compressor.
    public var compressor = CompressorSettings()

    /// Master-bus lo-fi character.
    public var lofi = LoFiSettings()

    public init() {
        self.activeSequence = PadAddress(bank: .A, pad: PadIndex(0))
        for bank in BankIndex.allCases {
            for i in 0..<16 {
                let addr = PadAddress(bank: bank, pad: PadIndex(i))
                self.pads[addr] = Pad()
                self.sequences[addr] = MMSequence()
            }
        }
    }
}
