import Foundation

/// Which Knob-FX effect is active on the master bus. A curated v1 subset of
/// the MPC's Knob FX list, each built on a reliable Apple Audio Unit.
public enum KnobFXType: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case delay
    case reverb
    case distortion
    case lowpass
    case highpass
    case bandpass

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none:       return "Off"
        case .delay:      return "Delay"
        case .reverb:     return "Reverb"
        case .distortion: return "Distortion"
        case .lowpass:    return "LP Filter"
        case .highpass:   return "HP Filter"
        case .bandpass:   return "BP Filter"
        }
    }

    /// K1/K2/K3 labels for the active effect ("" = unused).
    public var knobLabels: (String, String, String) {
        switch self {
        case .none:       return ("", "", "")
        case .delay:      return ("Time", "Feedback", "Mix")
        case .reverb:     return ("Size", "", "Mix")
        case .distortion: return ("Drive", "Tone", "Mix")
        case .lowpass, .highpass, .bandpass: return ("Freq", "Reso", "")
        }
    }
}
