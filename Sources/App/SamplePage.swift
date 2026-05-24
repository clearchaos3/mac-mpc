import Foundation

/// One of the page tabs in the LCD display panel.
///
/// MPC Sample groups these under B1/B2/B3 cycles:
///   B1: Trim ↔ Mix ↔ AmpEnv
///   B2: Tune ↔ Play
///   B3: Filter ↔ FltEnv
///
/// We currently expose them as a flat row of tabs; the B1/B2/B3 grouping
/// gets layered on when we wire physical button cycling.
enum SamplePage: String, CaseIterable, Identifiable {
    case trim, mix, ampEnv
    case tune, play
    case filter, fltEnv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trim:   return "Trim"
        case .mix:    return "Mix"
        case .ampEnv: return "Amp Env"
        case .tune:   return "Tune"
        case .play:   return "Play"
        case .filter: return "Filter"
        case .fltEnv: return "Flt Env"
        }
    }
}
