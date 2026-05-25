import Testing
import AVFoundation
@testable import MMAudio

@Suite("DSP")
struct DSPTests {

    private func buffer(_ samples: [Float], sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        let p = buf.floatChannelData![0]
        for (i, v) in samples.enumerated() { p[i] = v }
        return buf
    }

    @Test func resampleUpHalvesLength() {
        let src = buffer((0..<100).map { Float($0) })
        let out = AudioEngine.resampled(src, ratio: 2.0)
        #expect(out != nil)
        #expect(out!.frameLength == 50)
        // out[i] ≈ src[i*2]
        #expect(abs(out!.floatChannelData![0][10] - 20) < 0.001)
    }

    @Test func resampleDownDoublesLength() {
        let src = buffer((0..<50).map { Float($0) })
        let out = AudioEngine.resampled(src, ratio: 0.5)
        #expect(out != nil)
        #expect(out!.frameLength == 100)
    }

    @Test func lowpassPassesDC() {
        // A constant (DC) signal through a lowpass should survive ~unchanged.
        let src = buffer([Float](repeating: 1.0, count: 2000))
        let bq = Biquad.make(kind: .lowpass, cutoffHz: 1000, q: 0.707, sampleRate: 44100)
        bq.process(src)
        // After settling, samples should be close to 1.
        #expect(abs(src.floatChannelData![0][1999] - 1.0) < 0.01)
    }

    @Test func highpassKillsDC() {
        // A constant (DC) signal through a highpass should decay toward 0.
        let src = buffer([Float](repeating: 1.0, count: 2000))
        let bq = Biquad.make(kind: .highpass, cutoffHz: 1000, q: 0.707, sampleRate: 44100)
        bq.process(src)
        #expect(abs(src.floatChannelData![0][1999]) < 0.05)
    }
}
