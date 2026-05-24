import Testing
import AVFoundation
@testable import MMAudio

@Suite("Buffer math")
struct BufferMathTests {

    /// Build a mono buffer holding 0, 1, 2, … (n-1) as float samples.
    private func ramp(_ n: Int, sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let ptr = buf.floatChannelData![0]
        for i in 0..<n { ptr[i] = Float(i) }
        return buf
    }

    @Test func sliceTakesMiddleHalf() {
        let src = ramp(100)
        let slice = AudioEngine.slice(src, startFraction: 0.25, endFraction: 0.75)
        #expect(slice != nil)
        #expect(slice!.frameLength == 50)
        // First sample of the slice should be source[25].
        #expect(slice!.floatChannelData![0][0] == 25)
        #expect(slice!.floatChannelData![0][49] == 74)
    }

    @Test func sliceClampsAndOrders() {
        let src = ramp(100)
        // end < start gets clamped so end >= start; expect at least 1 frame.
        let slice = AudioEngine.slice(src, startFraction: 0.8, endFraction: 0.2)
        #expect(slice != nil)
        #expect(slice!.frameLength >= 1)
    }

    @Test func reverseFlipsSamples() {
        let src = ramp(10)
        let rev = AudioEngine.reversed(src)
        #expect(rev != nil)
        #expect(rev!.frameLength == 10)
        #expect(rev!.floatChannelData![0][0] == 9)
        #expect(rev!.floatChannelData![0][9] == 0)
    }

    @Test func extractProducesPeaks() {
        let src = ramp(1000)
        let peaks = WaveformExtractor.extract(buffer: src, bins: 10)
        #expect(peaks.peaks.count == 10)
        #expect(peaks.frameCount == 1000)
    }
}
