import Foundation

/// Factory Scene-1 CC numbers for the Korg nanoKONTROL (1st gen), verified
/// against Ryan's physical unit. Plus the role each control plays in
/// Flipside — see `routeNanoCC` in AppState for the dispatch.
enum NanoCC {
    // Raw CC tables (Scene 1 factory layout).
    static let sliderCCs:       [UInt8] = [2, 3, 4, 5, 6, 8, 9, 12, 13]
    static let knobCCs:         [UInt8] = [14, 15, 16, 17, 18, 19, 20, 21, 22]
    static let topButtonCCs:    [UInt8] = [23, 24, 25, 26, 27, 28, 29, 30, 31]
    static let bottomButtonCCs: [UInt8] = [33, 34, 35, 36, 37, 38, 39, 40, 41]

    // Transport row.
    static let rew:   UInt8 = 47
    static let play:  UInt8 = 45
    static let ff:    UInt8 = 48
    static let cycle: UInt8 = 49
    static let stop:  UInt8 = 46
    static let rec:   UInt8 = 44

    // --- Knob roles -------------------------------------------------------
    static let k1        = knobCCs[0]    // 14 → page param 1
    static let k2        = knobCCs[1]    // 15 → page param 2
    static let k3        = knobCCs[2]    // 16 → page param 3
    static let kBars     = knobCCs[3]    // 17 → sequence bars (bucketed)
    static let kSwing    = knobCCs[4]    // 18 → swing 0…1
    static let kQuantize = knobCCs[5]    // 19 → quantize division (bucketed)
    static let dataWheel = knobCCs[8]    // 22 → data wheel (browser scroll)

    // --- Slider roles -----------------------------------------------------
    static let fader = sliderCCs[0]      // 2  → assigned-parameter fader

    // --- Top buttons (page selection + shift + sample select) -------------
    static let bPageTrim   = topButtonCCs[0]   // 23
    static let bPageMix    = topButtonCCs[1]   // 24
    static let bPageAmpEnv = topButtonCCs[2]   // 25
    static let bPageTune   = topButtonCCs[3]   // 26
    static let bPagePlay   = topButtonCCs[4]   // 27
    static let bPageFilter = topButtonCCs[5]   // 28
    static let bPageFltEnv = topButtonCCs[6]   // 29
    static let bShift      = topButtonCCs[7]   // 30 → SHIFT layer toggle
    static let bBrowser    = topButtonCCs[8]   // 31 → Sample Select (open/close)

    // --- Bottom buttons (actions + pad-play) ------------------------------
    static let bTrimCommit = bottomButtonCCs[0]  // 33 → commit trim
    static let bTapTempo   = bottomButtonCCs[1]  // 34 → tap tempo
    static let bChop       = bottomButtonCCs[2]  // 35 → chop selected pad (½ bar grid)
    static let bLoop       = bottomButtonCCs[3]  // 36 → pad-play LOOP
    static let bReverse    = bottomButtonCCs[4]  // 37 → pad-play REVERSE
    static let bNoteOn     = bottomButtonCCs[5]  // 38 → pad-play NOTE ON
    static let bMute       = bottomButtonCCs[6]  // 39 → pad-play MUTE
    static let bPadFX      = bottomButtonCCs[7]  // 40 → Pad FX mode toggle
    static let bBounce     = bottomButtonCCs[8]  // 41 → Bounce toggle
}
