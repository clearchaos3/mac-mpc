import Foundation
import AVFoundation
import AudioToolbox
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
    /// One-shot amplitude envelope, normalised 0…1. attack = fade-in length
    /// (0 = instant); decay = tail sustain (1 = rings to natural end, lower =
    /// shorter fade-out). Baked into the playable buffer.
    public var ampAttack: Double = 0
    public var ampDecay: Double = 1

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
    /// When false, triggerPad no-ops — used to suppress sample playback while
    /// Pad FX mode repurposes the pads as effect triggers.
    private var playbackEnabled = true

    private let previewPlayer = AVAudioPlayerNode()
    private var previewFormat: AVAudioFormat?
    private var previewBuffer: AVAudioPCMBuffer?

    /// Master-bus compressor (Apple DynamicsProcessor). Bypassed by default.
    private let compressor: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    // Master Knob-FX chain. All inserted between the master mixer and the
    // compressor, all bypassed by default; selecting a Knob FX un-bypasses
    // exactly one. Using Apple's convenience AUs keeps the DSP reliable.
    private let fxDelay = AVAudioUnitDelay()
    private let fxReverb = AVAudioUnitReverb()
    private let fxDistortion = AVAudioUnitDistortion()
    private let fxEQ = AVAudioUnitEQ(numberOfBands: 1)

    private let lock = NSLock()

    public init() {
        engine.attach(masterMixer)
        engine.attach(fxDelay)
        engine.attach(fxReverb)
        engine.attach(fxDistortion)
        engine.attach(fxEQ)
        engine.attach(compressor)
        [fxDelay, fxReverb, fxDistortion, fxEQ].forEach { $0.bypass = true }
        compressor.bypass = true

        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        // masterMixer → delay → reverb → distortion → eq → compressor → main
        engine.connect(masterMixer, to: fxDelay, format: fmt)
        engine.connect(fxDelay, to: fxReverb, format: fmt)
        engine.connect(fxReverb, to: fxDistortion, format: fmt)
        engine.connect(fxDistortion, to: fxEQ, format: fmt)
        engine.connect(fxEQ, to: compressor, format: fmt)
        engine.connect(compressor, to: engine.mainMixerNode, format: fmt)

        // Reverb defaults to a fully-wet preset; tame it so un-bypassing
        // doesn't drown the mix until the user dials Mix up.
        fxReverb.loadFactoryPreset(.mediumHall)
        fxReverb.wetDryMix = 0

        engine.attach(previewPlayer)
        engine.connect(previewPlayer, to: masterMixer, format: fmt)
        previewFormat = fmt
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
            || old?.ampAttack != params.ampAttack
            || old?.ampDecay != params.ampDecay
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
        if params.ampAttack > 0.001 || params.ampDecay < 0.999 {
            // Apply on a mutable copy if we haven't already made one above.
            let target = (buf === full) ? (copyBuffer(buf) ?? buf) : buf
            applyAmpEnvelope(target, attack: params.ampAttack, decay: params.ampDecay)
            buf = target
        }
        return buf
    }

    /// Bake a one-shot amplitude envelope into a buffer: a fade-in of
    /// `attack` (0…1 → 0…1s) and a tail fade-out whose length is
    /// (1 - decay)·duration (decay = 1 leaves the tail untouched).
    private static func applyAmpEnvelope(_ buffer: AVAudioPCMBuffer, attack: Double, decay: Double) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 1 else { return }
        let sr = buffer.format.sampleRate
        let attackSamples = min(n, Int(max(0, attack) * sr))
        let fadeLen = min(n, Int((1.0 - max(0, min(1, decay))) * Double(n)))
        let channels = Int(buffer.format.channelCount)
        for ch in 0..<channels {
            let p = data[ch]
            if attackSamples > 1 {
                for i in 0..<attackSamples { p[i] *= Float(i) / Float(attackSamples) }
            }
            if fadeLen > 1 {
                let startFade = max(0, n - fadeLen)
                for i in startFade..<n {
                    p[i] *= Float(n - 1 - i) / Float(fadeLen)
                }
            }
        }
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

    /// Enable/disable sample playback (Pad FX mode disables it).
    public func setPlaybackEnabled(_ enabled: Bool) {
        lock.lock(); playbackEnabled = enabled; lock.unlock()
    }

    /// Trigger a pad. Safe from any thread (including the CoreMIDI thread).
    public func triggerPad(_ pad: PadAddress, velocity: UInt8) {
        lock.lock()
        guard playbackEnabled,
              let player = padPlayers[pad],
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

    // MARK: - Knob FX (master bus)

    /// Select the active Knob FX and apply its three normalised knob values.
    /// Bypasses every FX node except the one in use.
    public func setKnobFX(_ type: KnobFXType, k1: Double, k2: Double, k3: Double) {
        fxDelay.bypass = true
        fxReverb.bypass = true
        fxDistortion.bypass = true
        fxEQ.bypass = true

        func hz(_ n: Double) -> Float { Float(20.0 * pow(1000.0, max(0, min(1, n)))) } // 20…20k log

        switch type {
        case .none:
            break

        case .delay:
            fxDelay.bypass = false
            fxDelay.delayTime = TimeInterval(0.01 + k1 * 0.99)   // 10 ms … ~1 s
            fxDelay.feedback = Float(k2 * 90)                    // 0 … 90%
            fxDelay.wetDryMix = Float(k3 * 100)

        case .reverb:
            fxReverb.bypass = false
            // k1 picks a room size preset.
            let presets: [AVAudioUnitReverbPreset] = [.smallRoom, .mediumRoom, .largeRoom, .mediumHall, .largeHall, .cathedral]
            let idx = max(0, min(presets.count - 1, Int(k1 * Double(presets.count - 1))))
            fxReverb.loadFactoryPreset(presets[idx])
            fxReverb.wetDryMix = Float(k3 * 100)

        case .distortion:
            fxDistortion.bypass = false
            fxDistortion.preGain = Float(-20 + k1 * 40)          // -20 … +20 dB
            let presets: [AVAudioUnitDistortionPreset] = [.drumsBitBrush, .multiDecimated2, .multiDistortedFunk, .speechWaves]
            let idx = max(0, min(presets.count - 1, Int(k2 * Double(presets.count - 1))))
            fxDistortion.loadFactoryPreset(presets[idx])
            fxDistortion.wetDryMix = Float(k3 * 100)

        case .lowpass, .highpass, .bandpass:
            fxEQ.bypass = false
            let band = fxEQ.bands[0]
            switch type {
            case .lowpass:  band.filterType = .lowPass
            case .highpass: band.filterType = .highPass
            default:        band.filterType = .bandPass
            }
            band.frequency = hz(k1)
            band.bandwidth = Float(0.05 + k2 * 4.95)  // octaves
            band.bypass = false
            band.gain = 0
        }
    }

    // MARK: - Master compressor

    /// Configure the master-bus compressor. Bypassed unless `enabled`.
    public func setCompressor(_ s: CompressorSettings) {
        compressor.bypass = !s.enabled
        guard s.enabled else { return }
        let au = compressor.audioUnit
        // Amount 0…1 → threshold 0 dB (no comp) … -40 dB (heavy).
        let threshold = Float(-40.0 * max(0, min(1, s.amount)))
        let attackSec = Float(max(0.0001, min(0.2, s.attackMs / 1000.0)))
        let releaseSec = Float(max(0.01, min(3.0, s.releaseMs / 1000.0)))
        let gain = Float(max(-40, min(40, s.inBoostDB)))
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, threshold, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, attackSec, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, releaseSec, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, gain, 0)
    }

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
