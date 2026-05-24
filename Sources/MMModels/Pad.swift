import Foundation

/// Per-pad state. Everything editable on the MPC Sample's pad pages lives here.
/// Pure value type so it round-trips through Codable for project save/load and
/// can be cheaply diffed for UI updates.
public struct Pad: Hashable, Codable, Sendable {

    // MARK: - Sample reference

    /// Absolute URL of the loaded sample, or nil if the pad is empty.
    /// We deliberately store an absolute URL during the session and rewrite
    /// these as bundle-relative paths at save time.
    public var sampleURL: URL?

    // MARK: - Trim (Sample Mode → Trim page)

    /// Sample start point as a normalised position [0, 1] of the underlying file.
    public var start: Double = 0
    /// Sample end point as a normalised position [0, 1] of the underlying file.
    public var end: Double = 1
    /// Loop start point [0, 1]. Locked to `start` while `loopLock` is true.
    public var loopStart: Double = 0
    public var loopLock: Bool = true

    // MARK: - Pad Play state

    public var loop: Bool = false      // LOOP button
    public var reverse: Bool = false   // SHIFT + LOOP
    public var noteOn: Bool = false    // SHIFT + CHOP: pad held = gate

    // MARK: - Tune

    /// Coarse semitone tuning (-24…+24).
    public var semiTune: Int = 0
    /// Fine tuning in cents (-90…+90).
    public var fineTune: Int = 0
    /// Warp mode + amount. `.off` = no warp.
    public var warp: Warp = .off

    public enum Warp: Hashable, Codable, Sendable {
        case off
        case timeStretch(percent: Double)  // 50…200
        case pitch(percent: Double)        // 50…200
        case seq(beats: Double)            // lock to sequence tempo
    }

    // MARK: - Amplitude envelope

    public var ampAttack: Double = 0
    public var ampDecayOrRelease: Double = 1.0
    public var ampDecayFromEnd: Bool = true  // Decay From: start/end
    public var velocitySensitivity: Double = 1.0  // 0…1, MPC 0…127 scaled

    // MARK: - Filter

    public enum FilterType: String, Codable, CaseIterable, Sendable {
        case off, classic, lpf2, lpf4, hpf2, hpf4, bpf2, bpf4
    }
    public var filterType: FilterType = .off
    public var filterCutoff: Double = 1.0   // 0…1
    public var filterResonance: Double = 0  // 0…1

    // MARK: - Filter envelope

    public var filterAttack: Double = 0
    public var filterDecayOrRelease: Double = 1.0
    public var filterEnvDepth: Double = 0   // 0…1

    // MARK: - Play

    public enum Polyphony: String, Codable, Sendable { case mono, poly }
    public var polyphony: Polyphony = .mono
    public var muteGroup: Int = 0          // 0 = off, 1…16
    public var padLink: Int = 0            // 0 = off, 1…16 (links to this pad in the same bank)
    public var triggerOffset: Double = 0   // 0…1 of sample length

    // MARK: - Mix

    public var volume_dB: Double = 0       // -INF (-74)…+6
    public var pan: Double = 0             // -1 (50L)…+1 (50R)

    // MARK: - State (not editable; runtime)

    public var muted: Bool = false

    public init(sampleURL: URL? = nil) {
        self.sampleURL = sampleURL
    }
}
