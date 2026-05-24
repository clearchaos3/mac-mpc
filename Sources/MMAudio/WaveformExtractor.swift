import Foundation
import AVFoundation

/// A per-bin min/max pair extracted from a PCM buffer, suitable for
/// rendering a waveform overview without holding the whole sample.
public struct WaveformPeaks: Sendable {
    public let peaks: [SIMD2<Float>]   // .x = min, .y = max, range [-1, 1]
    public let frameCount: Int
    public let sampleRate: Double

    public init(peaks: [SIMD2<Float>], frameCount: Int, sampleRate: Double) {
        self.peaks = peaks
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    public static let empty = WaveformPeaks(peaks: [], frameCount: 0, sampleRate: 0)
}

/// Downsample an `AVAudioPCMBuffer` into per-bin peaks for display.
/// O(frames) once per buffer + render-cheap thereafter.
public enum WaveformExtractor {

    public static func extract(buffer: AVAudioPCMBuffer, bins: Int) -> WaveformPeaks {
        precondition(bins > 0)
        guard let channelData = buffer.floatChannelData else {
            return WaveformPeaks(peaks: [], frameCount: 0, sampleRate: buffer.format.sampleRate)
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0 else {
            return WaveformPeaks(peaks: [], frameCount: 0, sampleRate: buffer.format.sampleRate)
        }
        let framesPerBin = max(1, frameCount / bins)
        let actualBins = min(bins, (frameCount + framesPerBin - 1) / framesPerBin)

        var peaks: [SIMD2<Float>] = []
        peaks.reserveCapacity(actualBins)

        for binIdx in 0..<actualBins {
            let start = binIdx * framesPerBin
            let end = min(frameCount, start + framesPerBin)
            var lo: Float = 0
            var hi: Float = 0
            for ch in 0..<channelCount {
                let ptr = channelData[ch]
                for i in start..<end {
                    let v = ptr[i]
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
            }
            peaks.append(SIMD2(lo, hi))
        }

        return WaveformPeaks(peaks: peaks, frameCount: frameCount, sampleRate: buffer.format.sampleRate)
    }
}
