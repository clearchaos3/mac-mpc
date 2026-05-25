import Foundation
import AVFoundation

/// How to slice a sample in Chop mode.
public enum ChopType: Sendable, Equatable {
    /// Even division into N slices.
    case regions(Int)
    /// Transient-onset detection. `sensitivity` 0…1 — higher = fewer slices
    /// (matches the MPC's "higher threshold → fewer slices").
    case threshold(Double)
    /// Musical grid: slices of `beatsPerSlice` beats at `bpm`, so chops land
    /// on bar/beat boundaries where the progression moves. (4 = 1 bar at 4/4,
    /// 2 = ½ bar, 1 = beat.) The best fit for "chop on the progression".
    case grid(bpm: Double, beatsPerSlice: Double)
}

/// Computes slice boundaries for Chop mode. Returns normalised
/// (start, end) fraction pairs over the source buffer, so callers can reuse
/// `AudioEngine.slice(_:startFraction:endFraction:)`.
public enum Chopper {

    public static func slices(buffer: AVAudioPCMBuffer,
                              type: ChopType,
                              maxSlices: Int = 16) -> [(start: Double, end: Double)] {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return [] }

        switch type {
        case .regions(let count):
            let c = max(1, min(maxSlices, count))
            return (0..<c).map { i in
                (Double(i) / Double(c), Double(i + 1) / Double(c))
            }

        case .grid(let bpm, let beatsPerSlice):
            guard bpm > 0, beatsPerSlice > 0 else { return [(0, 1)] }
            let sampleRate = buffer.format.sampleRate
            let totalSec = Double(n) / sampleRate
            let sliceSec = (60.0 / bpm) * beatsPerSlice
            guard sliceSec > 0, totalSec > 0 else { return [(0, 1)] }
            let count = max(1, min(maxSlices, Int((totalSec / sliceSec).rounded(.up))))
            return (0..<count).map { i in
                let s = min(1.0, (Double(i) * sliceSec) / totalSec)
                let e = min(1.0, (Double(i + 1) * sliceSec) / totalSec)
                return (s, e)
            }

        case .threshold(let sensitivity):
            let onsets = onsetFrames(buffer: buffer, sensitivity: sensitivity, maxSlices: maxSlices)
            guard !onsets.isEmpty else { return [(0, 1)] }
            var boundaries = onsets
            if boundaries.first != 0 { boundaries.insert(0, at: 0) }
            var result: [(Double, Double)] = []
            for i in 0..<boundaries.count {
                let s = boundaries[i]
                let e = (i + 1 < boundaries.count) ? boundaries[i + 1] : n
                result.append((Double(s) / Double(n), Double(e) / Double(n)))
            }
            return Array(result.prefix(maxSlices))
        }
    }

    /// Short-time-energy onset detector. Returns onset frame positions.
    private static func onsetFrames(buffer: AVAudioPCMBuffer,
                                    sensitivity: Double,
                                    maxSlices: Int) -> [Int] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let sr = buffer.format.sampleRate

        let windowSize = max(1, Int(sr * 0.01))   // 10 ms windows
        let minGap = max(1, Int(sr * 0.05))        // 50 ms minimum slice
        let windowCount = n / windowSize
        guard windowCount > 1 else { return [] }

        // Per-window RMS energy (summed across channels).
        var energy = [Float](repeating: 0, count: windowCount)
        for w in 0..<windowCount {
            let start = w * windowSize
            var sum: Float = 0
            for ch in 0..<channels {
                let p = channelData[ch]
                for i in start..<(start + windowSize) { sum += p[i] * p[i] }
            }
            energy[w] = (sum / Float(windowSize * channels)).squareRoot()
        }

        let maxE = energy.max() ?? 0
        guard maxE > 0 else { return [] }

        // sensitivity 0…1 → level 0.05·maxE … 0.6·maxE (higher = fewer onsets).
        let s = max(0, min(1, sensitivity))
        let level = maxE * Float(0.05 + s * 0.55)

        var onsets: [Int] = []
        var lastOnsetFrame = -minGap
        for w in 1..<windowCount {
            let here = energy[w]
            let prev = energy[w - 1]
            let frame = w * windowSize
            if here > level && here > prev * 1.3 && (frame - lastOnsetFrame) >= minGap {
                onsets.append(frame)
                lastOnsetFrame = frame
                if onsets.count >= maxSlices - 1 { break }
            }
        }
        return onsets
    }
}
