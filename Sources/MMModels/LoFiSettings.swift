import Foundation

/// Master-bus lo-fi character — the "lo-fi" in lo-fi hip-hop. Rolls off
/// highs (dusty/muffled), adds saturation (warmth), and mixes in a vinyl
/// crackle bed. Persists with the project.
public struct LoFiSettings: Hashable, Codable, Sendable {
    public var enabled: Bool = false
    public var tone: Double = 0.6     // 0…1 → lowpass cutoff (lower = darker)
    public var drive: Double = 0.3    // 0…1 → saturation amount
    public var noise: Double = 0.2    // 0…1 → vinyl crackle level

    public init() {}
}
