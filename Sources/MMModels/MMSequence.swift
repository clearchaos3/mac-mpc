import Foundation

/// A single recorded note event inside a sequence.
public struct SequenceEvent: Hashable, Codable, Sendable {
    /// Tick position from the start of the sequence. 960 ticks per quarter
    /// note (classic hardware-sampler convention); a 1/16th step is 240
    /// ticks. See `Timing`.
    public var tick: Int
    public var bank: BankIndex
    public var pad: PadIndex
    public var velocity: UInt8
    /// Note length in ticks; for one-shot samples this is informational.
    public var lengthTicks: Int

    public init(tick: Int, bank: BankIndex, pad: PadIndex, velocity: UInt8, lengthTicks: Int = 240) {
        self.tick = tick
        self.bank = bank
        self.pad = pad
        self.velocity = velocity
        self.lengthTicks = lengthTicks
    }
}

/// A single pattern. Each project holds 16 sequences × 8 banks of sequences = 128 total.
/// Named `MMSequence` to avoid colliding with `Swift.Sequence`.
public struct MMSequence: Hashable, Codable, Sendable {
    public var name: String = ""
    public var bars: Int = 4
    public var bpm: Double = 90.0
    public var quantizeDivision: Int = 16   // /16 = 1/16th notes
    public var swing: Double = 0            // 0…1 (RT Swing percent)
    public var events: [SequenceEvent] = []

    public init() {}

    public var isEmpty: Bool { events.isEmpty }
}
