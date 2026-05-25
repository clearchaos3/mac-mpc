import Foundation

/// Tick/tempo math. Uses the classic hardware-sampler resolution of 960
/// pulses per quarter note.
public enum Timing {
    public static let ticksPerQuarter = 960

    /// Ticks per quantize step. `division` is the denominator of the note
    /// value: 4 = 1/4, 8 = 1/8, 16 = 1/16, 32 = 1/32, 64 = 1/64.
    public static func ticksPerStep(division: Int) -> Int {
        max(1, ticksPerQuarter * 4 / max(1, division))
    }

    /// Total ticks in one loop of `bars` at the given time signature.
    public static func loopLengthTicks(bars: Int, numerator: Int, denominator: Int) -> Int {
        let ticksPerBar = numerator * (ticksPerQuarter * 4 / max(1, denominator))
        return max(1, bars * ticksPerBar)
    }

    public static func secondsPerTick(bpm: Double) -> Double {
        guard bpm > 0 else { return 0 }
        return 60.0 / (bpm * Double(ticksPerQuarter))
    }

    /// Quantize a tick to the nearest step boundary.
    public static func quantize(_ tick: Int, division: Int) -> Int {
        let step = ticksPerStep(division: division)
        let rounded = Int((Double(tick) / Double(step)).rounded()) * step
        return rounded
    }
}
