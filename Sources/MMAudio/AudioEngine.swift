import Foundation
import AVFoundation
import MMModels

/// AVAudioEngine wrapper sized for an MPC-style sampler.
///
/// Current architecture:
///   - One `AVAudioEngine`
///   - One `AVAudioMixerNode` master bus
///   - One `AVAudioPlayerNode` per loaded pad (lazy)
///   - One decoded PCM buffer cached per pad
///   - One dedicated preview player for the sample browser
///
/// Per-pad polyphony / voice pooling / filters / envelopes / FX land in
/// later iterations on top of this graph.
public final class AudioEngine: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    /// One player + buffer per pad, keyed by `PadAddress`.
    private var padPlayers: [PadAddress: AVAudioPlayerNode] = [:]
    private var padBuffers: [PadAddress: AVAudioPCMBuffer] = [:]

    /// Sample-browser auto-preview voice. Separate from pad playback so
    /// previewing while a sequence is running doesn't disturb pad voices.
    private let previewPlayer = AVAudioPlayerNode()
    private var previewFormat: AVAudioFormat?
    private var previewBuffer: AVAudioPCMBuffer?

    /// Protects the pad dictionaries. Audio render-side calls (`scheduleBuffer`)
    /// are safe from any thread once nodes are attached.
    private let lock = NSLock()

    public init() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)

        engine.attach(previewPlayer)
        // Connect preview at the hardware format; we'll reconnect if a
        // mismatched-format buffer arrives.
        let defaultFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(previewPlayer, to: masterMixer, format: defaultFormat)
        previewFormat = defaultFormat
    }

    public func start() {
        do {
            try engine.start()
        } catch {
            NSLog("AudioEngine failed to start: \(error)")
        }
    }

    public func stop() {
        engine.stop()
    }

    // MARK: - Pad slots

    /// Load a sample file into a pad. Decoded once + cached as a PCMBuffer.
    public func loadSample(url: URL, into pad: PadAddress) throws {
        let buffer = try SampleLoader.load(url: url)

        lock.lock()
        defer { lock.unlock() }

        if let existing = padPlayers[pad] {
            existing.stop()
            engine.detach(existing)
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: masterMixer, format: buffer.format)

        padPlayers[pad] = player
        padBuffers[pad] = buffer
    }

    /// Clear a pad's sample.
    public func clearPad(_ pad: PadAddress) {
        lock.lock()
        if let existing = padPlayers.removeValue(forKey: pad) {
            existing.stop()
            engine.detach(existing)
        }
        padBuffers.removeValue(forKey: pad)
        lock.unlock()
    }

    /// True if this pad has a sample loaded.
    public func hasSample(_ pad: PadAddress) -> Bool {
        lock.lock()
        let has = padBuffers[pad] != nil
        lock.unlock()
        return has
    }

    /// Read-only access to a pad's PCM buffer (for waveform extraction).
    public func buffer(for pad: PadAddress) -> AVAudioPCMBuffer? {
        lock.lock()
        let buf = padBuffers[pad]
        lock.unlock()
        return buf
    }

    /// Replace a pad's buffer in place (for destructive edits like Trim).
    /// Re-uses the existing player node when possible to avoid graph churn.
    public func replaceBuffer(for pad: PadAddress, with newBuffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = padPlayers[pad] {
            existing.stop()
            if existing.outputFormat(forBus: 0) != newBuffer.format {
                engine.disconnectNodeOutput(existing)
                engine.connect(existing, to: masterMixer, format: newBuffer.format)
            }
        } else {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: masterMixer, format: newBuffer.format)
            padPlayers[pad] = player
        }
        padBuffers[pad] = newBuffer
    }

    /// Render a slice of `buffer` between two normalised positions into a
    /// fresh PCM buffer. Used by the destructive Trim operation.
    public static func slice(_ source: AVAudioPCMBuffer,
                             startFraction: Double,
                             endFraction: Double) -> AVAudioPCMBuffer? {
        let total = Int(source.frameLength)
        guard total > 0 else { return nil }
        let s = max(0.0, min(1.0, startFraction))
        let e = max(s, min(1.0, endFraction))
        let startFrame = Int(Double(total) * s)
        let endFrame = max(startFrame + 1, Int(Double(total) * e))
        let frames = AVAudioFrameCount(endFrame - startFrame)
        guard let dest = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frames) else {
            return nil
        }
        let channelCount = Int(source.format.channelCount)
        if let src = source.floatChannelData, let dst = dest.floatChannelData {
            for ch in 0..<channelCount {
                let srcPtr = src[ch].advanced(by: startFrame)
                let dstPtr = dst[ch]
                dstPtr.update(from: srcPtr, count: Int(frames))
            }
        }
        dest.frameLength = frames
        return dest
    }

    /// Trigger a pad. Safe to call from any thread (including the CoreMIDI thread).
    public func triggerPad(_ pad: PadAddress, velocity: UInt8) {
        lock.lock()
        guard let player = padPlayers[pad], let buffer = padBuffers[pad] else {
            lock.unlock()
            return
        }
        lock.unlock()

        player.volume = max(0, min(1, Float(velocity) / 127.0))
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Stop a pad immediately.
    public func stopPad(_ pad: PadAddress) {
        lock.lock()
        let player = padPlayers[pad]
        lock.unlock()
        player?.stop()
    }

    /// Stop everything.
    public func stopAll() {
        lock.lock()
        let players = Array(padPlayers.values)
        lock.unlock()
        for p in players { p.stop() }
        previewPlayer.stop()
    }

    // MARK: - Preview voice (sample browser)

    /// Play an audio file as a preview. Stops any in-flight preview first.
    /// If the file's format doesn't match the current preview connection,
    /// reconnect the player on the fly.
    public func preview(url: URL) {
        do {
            let buffer = try SampleLoader.load(url: url)
            previewPlayer.stop()

            // If format changed, reconnect.
            if previewFormat != buffer.format {
                engine.disconnectNodeOutput(previewPlayer)
                engine.connect(previewPlayer, to: masterMixer, format: buffer.format)
                previewFormat = buffer.format
            }

            previewBuffer = buffer
            previewPlayer.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
            if !previewPlayer.isPlaying { previewPlayer.play() }
        } catch {
            NSLog("preview load failed for \(url.lastPathComponent): \(error)")
        }
    }

    public func stopPreview() {
        previewPlayer.stop()
    }
}
