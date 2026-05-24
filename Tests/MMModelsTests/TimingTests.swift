import Testing
@testable import MMModels

@Suite("Timing")
struct TimingTests {

    @Test func sixteenthIs240Ticks() {
        #expect(Timing.ticksPerStep(division: 16) == 240)
        #expect(Timing.ticksPerStep(division: 4) == 960)
        #expect(Timing.ticksPerStep(division: 8) == 480)
    }

    @Test func fourBarLoopIn44() {
        // 4 bars × 4 beats × 960 = 15360
        #expect(Timing.loopLengthTicks(bars: 4, numerator: 4, denominator: 4) == 15360)
        #expect(Timing.loopLengthTicks(bars: 1, numerator: 4, denominator: 4) == 3840)
    }

    @Test func quantizeSnapsToNearestStep() {
        // Step = 240 for 1/16. 100 → 0, 130 → 240, 360 → 480 (nearest).
        #expect(Timing.quantize(100, division: 16) == 0)
        #expect(Timing.quantize(130, division: 16) == 240)
        #expect(Timing.quantize(360, division: 16) == 480)
        #expect(Timing.quantize(240, division: 16) == 240)
    }

    @Test func secondsPerTickAt120BPM() {
        // 120 BPM → 0.5 s/quarter → /960 per tick.
        let spt = Timing.secondsPerTick(bpm: 120)
        #expect(abs(spt - (0.5 / 960.0)) < 1e-9)
    }
}
