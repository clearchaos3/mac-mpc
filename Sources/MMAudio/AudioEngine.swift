import Foundation
import AVFoundation
import MMModels

/// AVAudioEngine wrapper sized for an MPC-style sampler.
///
/// First-cut architecture:
///   - One `AVAudioEngine`
///   - One `AVAudioMixerNode` master bus
///   - One `AVAudioPlayerNode` per loaded pad (lazy)
///   - One decoded PCM buffer cached per pad
///
/// Polyphony, voice pooling, per-pad filters/envelopes/FX, and the master
/// compressor land in later iterations on top of this graph.
public final class AudioEngine: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    /// One player + buffer per pad, keyed by `PadAddress`.
    private var padPlayers: [PadAddress: AVAudioPlayerNode] = [:]
    private var padBuffers: [PadAddress: AVAudioPCMBuffer] = [:]

    /// Serial queue protecting the dictionaries. Audio render thread reads
    /// only via `scheduleBuffer`, which is safe to call from any thread.
    private let lock = NSLock()

    public init() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
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

    /// Load a sample file into a pad. Decoded once + cached as a PCMBuffer.
    public func loadSample(url: URL, into pad: PadAddress) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw NSError(domain: "mac-mpc", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not allocate buffer"])
        }
        try file.read(into: buffer)

        lock.lock()
        defer { lock.unlock() }

        if let existing = padPlayers[pad] {
            existing.stop()
            engine.detach(existing)
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: masterMixer, format: format)

        padPlayers[pad] = player
        padBuffers[pad] = buffer
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
    }
}
