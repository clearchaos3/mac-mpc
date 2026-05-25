import Foundation
import AVFoundation

/// A single biquad filter section (RBJ cookbook coefficients). Used to bake
/// a static per-pad filter into a pad's playable buffer, so we get per-pad
/// filtering without one AVAudioUnit node per pad.
public struct Biquad: Sendable {
    public var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    public enum Kind: Sendable { case lowpass, highpass, bandpass }

    public static func make(kind: Kind, cutoffHz: Double, q: Double, sampleRate: Double) -> Biquad {
        let nyquist = sampleRate / 2
        let fc = max(20.0, min(cutoffHz, nyquist * 0.99))
        let w0 = 2.0 * Double.pi * fc / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let qq = max(0.1, q)
        let alpha = sinw0 / (2.0 * qq)

        var b0 = 0.0, b1 = 0.0, b2 = 0.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosw0
        let a2 = 1.0 - alpha

        switch kind {
        case .lowpass:
            b0 = (1.0 - cosw0) / 2.0
            b1 = 1.0 - cosw0
            b2 = (1.0 - cosw0) / 2.0
        case .highpass:
            b0 = (1.0 + cosw0) / 2.0
            b1 = -(1.0 + cosw0)
            b2 = (1.0 + cosw0) / 2.0
        case .bandpass:
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
        }

        return Biquad(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }

    /// Filter a buffer in place. `passes` cascades the section (2 = 4-pole).
    public func process(_ buffer: AVAudioPCMBuffer, passes: Int = 1) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        for _ in 0..<max(1, passes) {
            for ch in 0..<channels {
                let p = data[ch]
                var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
                for i in 0..<n {
                    let x0 = p[i]
                    let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                    x2 = x1; x1 = x0
                    y2 = y1; y1 = y0
                    p[i] = y0
                }
            }
        }
    }
}
