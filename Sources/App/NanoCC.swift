import Foundation

/// Factory Scene 1 CC numbers for the Korg nanoKONTROL (1st gen), verified
/// against Ryan's physical unit (carried over from the midi-fighter-64
/// project). If the device is remapped via Korg Kontrol Editor, the live
/// "last event" line shows what's actually arriving so these can be tuned.
enum NanoCC {
    // Indexed 0..8 — slot 0 = slider/knob #1 in the user-facing labels.
    static let sliderCCs: [UInt8] = [2, 3, 4, 5, 6, 8, 9, 12, 13]
    static let knobCCs:   [UInt8] = [14, 15, 16, 17, 18, 19, 20, 21, 22]

    // Transport row.
    static let rew:   UInt8 = 47
    static let play:  UInt8 = 45
    static let ff:    UInt8 = 48
    static let cycle: UInt8 = 49
    static let stop:  UInt8 = 46
    static let rec:   UInt8 = 44

    // mac-mpc role assignments.
    static let k1 = knobCCs[0]          // 14 → K1
    static let k2 = knobCCs[1]          // 15 → K2
    static let k3 = knobCCs[2]          // 16 → K3
    static let dataWheel = knobCCs[8]   // 22 → "data wheel" (knob 9)
    static let fader = sliderCCs[0]     // 2  → fader (slider 1)
}
