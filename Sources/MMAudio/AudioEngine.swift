import Foundation
import AVFoundation
import MMModels

/// Per-trigger playback parameters pushed from the model layer. Kept inside
/// the engine (thread-safe) so the realtime/MIDI trigger path can read them
/// without reaching back across the main actor.
public struct TriggerParams: Sendable, Equatable {
    public var startFraction: Double = 0
    public var endFraction: Double = 1
    public var gain: Float = 1          // linear, from volume_dB
    public var pan: Float = 0           // -1…+1
    public var reverse: Bool = false
    /// Playback pitch ratio (2^(semitones/12)). >1 = higher + shorter
    /// (classic sampler behaviour — also speeds the sample up).
    public var pitchRatio: Double = 1
    /// Static per-pad filter baked into the playable buffer (nil = bypass).
    public var filter: FilterSpec? = nil

    public init() {}
}

/// Static filter description baked into a pad's playable buffer.
public struct FilterSpec: Sendable, Equatable {
    public var kind: Biquad.Kind
    public var cutoffHz: Double
    public var q: Double
    public var passes: Int   // 1 = 2-pole, 2 = 4-pole

    public init(kind: Biquad.Kind, cutoffHz: Double, q: Double, passes: Int) {
        self.kind = kind
        self.cutoffHz = cutoffHz
        self.q = q
        self.passes = passes
    }
}

extension Biquad.Kind: Equatable {}

/// AVAudioEngine wrapper sized for an MPC-style sampler.
///
/// Current architecture:
///   - One `AVAudioEngine`, one master `AVAudioMixerNode`
///   - One `AVAudioPlayerNode` per loaded pad (lazy)
///   - Full decoded buffer cached per pad (waveform + destructive edits)
///   - A derived "playable" buffer per pad (sliced to start/end, optionally
///     reversed) that the trigger path actually schedules — recomputed only
///     when params change, so the hot path never allocates
///   - A dedicated preview player for the sample browser
///
/// Per-pad pitch / filter / envelopes / voice-pool polyphony are still to
/// come (they need either per-pad DSP nodes or a pooled-voice rework).
public final class AudioEngine: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    private var padPlayers: [PadAddress: AVAudioPlayerNode] = [:]
    /// Full decoded buffer (source of truth for waveform + slicing).
    private var padBuffers: [PadAddress: AVAudioPCMBuffer] = [:]
    /// Buffer actually scheduled on trigger (sliced/reversed per params).
    private var padPlayable: [PadAddress: AVAudioPCMBuffer] = [:]
    private var padParams: [PadAddress: TriggerParams] = [:]

    private let previewPlayer = AVAudioPlayerNode()
    private var previewFormat: AVAudioFormat?
    private var previewBuffer: AVAudioPCMBuffer?

    private let lock = NSLock()

    public init() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)

        engine.attach(previewPlayer)
        let defaultFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(previewPlayer, to: masterMixer, format: defaultFormat)
        previewFormat = defaultFormat
    }

    public func start() {
        do { try engine.start() }
        catch { NSLog("AudioEngine failed to start: \(error)") }
    }

    public func stop() { engine.stop() }

    // MARK: - Pad slots

    public func loadSample(url: URL, into pad: PadAddress) throws {
        let buffer = try SampleLoader.load(url: url)
        lock.lock()
        defer { lock.unlock() }
        attachPlayerIfNeeded(pad, format: buffer.format)
        padBuffers[pad] = buffer
        padParams[pad] = TriggerParams()
        padPlayable[pad] = buffer
    }

    public func clearPad(_ pad: PadAddress) {
        lock.lock()
        if let existing = padPlayers.removeValue(forKey: pad) {
            existing.stop()
            engine.detach(existing)
        }
        padBuffers.removeValue(forKey: pad)
        padPlayable.removeValue(forKey: pad)
        padParams.removeValue(forKey: pad)
        lock.unlock()
    }

    public func hasSample(_ pad: PadAddress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return padBuffers[pad] != nil
    }

    public func buffer(for pad: PadAddress) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return padBuffers[pad]
    }

    /// Replace a pad's full buffer (destructive edits like Trim). Resets the
    /// playable buffer to the new full buffer and clears start/end.
    public func replaceBuffer(for pad: PadAddress, with newBuffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        attachPlayerIfNeeded(pad, format: newBuffer.format, reconnectIfFormatChanged: true)
        padBuffers[pad] = newBuffer
        var params = padParams[pad] ?? TriggerParams()
        params.startFraction = 0
        params.endFraction = 1
        padParams[pad] = params
        padPlayable[pad] = newBuffer
    }

    /// Push updated trigger params from the model. Recomputes the pad's
    /// "playable" buffer — source run through the static DSP chain
    /// (slice → reverse → pitch-resample → filter) — only when a chain
    /// param actually changed, so the trigger path never does this work.
    public func setTriggerParams(_ params: TriggerParams, for pad: PadAddress) {
        lock.lock()
        defer { lock.unlock() }
        let old = padParams[pad]
        padParams[pad] = params
        guard let full = padBuffers[pad] else { return }

        let chainChanged = old?.startFraction != params.startFraction
            || old?.endFraction != params.endFraction
            || old?.reverse != params.reverse
            || old?.pitchRatio != params.pitchRatio
            || old?.filter != params.filter
        guard chainChanged || padPlayable[pad] == nil else { return }

        padPlayable[pad] = Self.renderPlayable(full: full, params: params)
    }

    /// Run the source buffer through the static DSP chain.
    private static func renderPlayable(full: AVAudioPCMBuffer, params: TriggerParams) -> AVAudioPCMBuffer {
        var buf = full
        if params.startFraction > 0 || params.endFraction < 1 {
            buf = slice(buf, startFraction: params.startFraction, endFraction: params.endFraction) ?? buf
        }
        if params.reverse {
            buf = reversed(buf) ?? buf
        }
        if abs(params.pitchRatio - 1.0) > 1e-6 {
            buf = resampled(buf, ratio: params.pitchRatio) ?? buf
        }
        if let f = params.filter {
            // Filter a mutable copy so the cached source stays clean.
            if let copy = copyBuffer(buf) {
                let bq = Biquad.make(kind: f.kind, cutoffHz: f.cutoffHz, q: f.q,
                                     sampleRate: buf.format.sampleRate)
                bq.process(copy, passes: f.passes)
                buf = copy
            }
        }
        return buf
    }

    private static func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let n = source.frameLength
        guard let dest = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: n),
              let src = source.floatChannelData, let dst = dest.floatChannelData else { return nil }
        for ch in 0..<Int(source.format.channelCount) {
            dst[ch].update(from: src[ch], count: Int(n))
        }
        dest.frameLength = n
        return dest
    }

    /// Linear-interpolation resample. `ratio` > 1 → higher pitch + shorter
    /// (output frame count = input / ratio). Same output format as input.
    public static func resampled(_ source: AVAudioPCMBuffer, ratio: Double) -> AVAudioPCMBuffer? {
        let inN = Int(source.frameLength)
        guard inN > 0, ratio > 0,
              let src = source.floatChannelData else { return nil }
        let outN = max(1, Int(Double(inN) / ratio))
        guard let dest = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(outN)),
              let dst = dest.floatChannelData else { return nil }
        let channels = Int(source.format.channelCount)
        for ch in 0..<channels {
            let s = src[ch], d = dst[ch]
            for i in 0..<outN {
                let pos = Double(i) * ratio
                let i0 = Int(pos)
                let frac = Float(pos - Double(i0))
                let a = s[min(i0, inN - 1)]
                let b = s[min(i0 + 1, inN - 1)]
                d[i] = a + (b - a) * frac
            }
        }
        dest.frameLength = AVAudioFrameCount(outN)
        return dest
    }

    /// Trigger a pad. Safe from any thread (including the CoreMIDI thread).
    public func triggerPad(_ pad: PadAddress, velocity: UInt8) {
        lock.lock()
        guard let player = padPlayers[pad],
              let playable = padPlayable[pad] else {
            lock.unlock()
            return
        }
        let params = padParams[pad] ?? TriggerParams()
        lock.unlock()

        let vel = max(0, min(1, Float(velocity) / 127.0))
        player.volume = params.gain * vel
        player.pan = max(-1, min(1, params.pan))
        player.scheduleBuffer(playable, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    public func stopPad(_ pad: PadAddress) {
        lock.lock(); let player = padPlayers[pad]; lock.unlock()
        player?.stop()
    }

    public func stopAll() {
        lock.lock(); let players = Array(padPlayers.values); lock.unlock()
        for p in players { p.stop() }
        previewPlayer.stop()
    }

    // MARK: - Buffer math

    /// Slice a normalised sub-range into a fresh buffer.
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
        guard let dest = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frames) else { return nil }
        let channelCount = Int(source.format.channelCount)
        if let src = source.floatChannelData, let dst = dest.floatChannelData {
            for ch in 0..<channelCount {
                dst[ch].update(from: src[ch].advanced(by: startFrame), count: Int(frames))
            }
        }
        dest.frameLength = frames
        return dest
    }

    /// Reverse a buffer's samples into a fresh buffer.
    public static func reversed(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let n = Int(source.frameLength)
        guard n > 0,
              let dest = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(n)),
              let src = source.floatChannelData,
              let dst = dest.floatChannelData else { return nil }
        let channelCount = Int(source.format.channelCount)
        for ch in 0..<channelCount {
            for i in 0..<n { dst[ch][i] = src[ch][n - 1 - i] }
        }
        dest.frameLength = AVAudioFrameCount(n)
        return dest
    }

    // MARK: - Preview voice

    public func preview(url: URL) {
        do {
            let buffer = try SampleLoader.load(url: url)
            previewPlayer.stop()
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

    public func stopPreview() { previewPlayer.stop() }

    // MARK: - Private

    /// Attach + connect a player node for a pad if one doesn't exist.
    /// Caller must hold `lock`.
    private func attachPlayerIfNeeded(_ pad: PadAddress,
                                      format: AVAudioFormat,
                                      reconnectIfFormatChanged: Bool = false) {
        if let existing = padPlayers[pad] {
            existing.stop()
            if reconnectIfFormatChanged, existing.outputFormat(forBus: 0) != format {
                engine.disconnectNodeOutput(existing)
                engine.connect(existing, to: masterMixer, format: format)
            }
            return
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: masterMixer, format: format)
        padPlayers[pad] = player
    }
}
