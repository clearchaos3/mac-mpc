import Testing
import AVFoundation
@testable import MMAudio

@Suite("Chopper")
struct ChopperTests {

    private func buffer(frames: Int, fill: (Int) -> Float, sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        let p = buf.floatChannelData![0]
        for i in 0..<frames { p[i] = fill(i) }
        return buf
    }

    @Test func regionsEvenlyDivide() {
        let buf = buffer(frames: 1000) { _ in 0.5 }
        let slices = Chopper.slices(buffer: buf, type: .regions(4))
        #expect(slices.count == 4)
        #expect(abs(slices[0].start - 0.0) < 1e-9)
        #expect(abs(slices[0].end - 0.25) < 1e-9)
        #expect(abs(slices[3].end - 1.0) < 1e-9)
    }

    @Test func regionsClampToMax() {
        let buf = buffer(frames: 1000) { _ in 0.1 }
        let slices = Chopper.slices(buffer: buf, type: .regions(99), maxSlices: 16)
        #expect(slices.count == 16)
    }

    @Test func thresholdFindsTransients() {
        // 4 sharp bursts separated by silence, at 44.1k → ~0.25s apart.
        let sr = 44100.0
        let n = Int(sr) // 1 second
        let burstPositions = [0, n / 4, n / 2, 3 * n / 4]
        let burstLen = Int(sr * 0.02)
        let buf = buffer(frames: n, fill: { i in
            for p in burstPositions where i >= p && i < p + burstLen {
                return 0.9
            }
            return 0.0
        }, sampleRate: sr)

        let slices = Chopper.slices(buffer: buf, type: .threshold(0.3))
        // Should find multiple slices (won't be exact, but > 1).
        #expect(slices.count >= 2)
        #expect(slices.first!.start == 0)
    }
}
