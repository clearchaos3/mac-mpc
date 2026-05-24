import Foundation

/// A pad LED color expressed as an MF64 factory palette index (0-127).
/// The device interprets this as the `velocity` byte of a Note On addressed
/// to that pad's note number on the LED channel.
public struct PadColor: Hashable, Sendable {
    public let paletteIndex: UInt8

    public init(paletteIndex: UInt8) {
        self.paletteIndex = paletteIndex & 0x7F
    }

    public static let off     = PadColor(paletteIndex: 0)
    public static let white   = PadColor(paletteIndex: 3)
    public static let red     = PadColor(paletteIndex: 5)
    public static let orange  = PadColor(paletteIndex: 9)
    public static let yellow  = PadColor(paletteIndex: 13)
    public static let lime    = PadColor(paletteIndex: 17)
    public static let green   = PadColor(paletteIndex: 21)
    public static let mint    = PadColor(paletteIndex: 25)
    public static let aqua    = PadColor(paletteIndex: 33)
    public static let cyan    = PadColor(paletteIndex: 37)
    public static let sky     = PadColor(paletteIndex: 41)
    public static let blue    = PadColor(paletteIndex: 45)
    public static let violet  = PadColor(paletteIndex: 49)
    public static let magenta = PadColor(paletteIndex: 53)
    public static let pink    = PadColor(paletteIndex: 57)

    /// Resolved 8-bit-per-channel RGB for on-screen mirroring of pad LEDs.
    public var rgb: (r: UInt8, g: UInt8, b: UInt8) {
        MFFactoryPalette.rgb(forVelocity: paletteIndex)
    }
}
