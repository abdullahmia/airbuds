// Value types the panel shows, and what the connected earbuds support.

@inline(__always) func at(_ p: [UInt8], _ i: Int) -> UInt8? { i >= 0 && i < p.count ? p[i] : nil }

// MARK: - Battery

public struct BatteryLevel: Equatable, Codable {
    public var level: Int
    public var charging: Bool
    public init(level: Int, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

public struct Battery: Equatable, Codable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?
    public var `case`: BatteryLevel?
    public init() {}
}

// MARK: - Settings

public enum NoiseMode: String, CaseIterable, Codable {
    case anc, transparency, off

    /// The mode after `current` when cycling NC → Transparency → Off (Transparency
    /// only if the earbuds have it). Starts at Noise Cancellation when unknown.
    public static func next(after current: NoiseMode?, transparency: Bool) -> NoiseMode {
        let order: [NoiseMode] = transparency ? [.anc, .transparency, .off] : [.anc, .off]
        guard let current, let index = order.firstIndex(of: current) else { return order[0] }
        return order[(index + 1) % order.count]
    }
}

public struct EqPreset: Equatable, Identifiable {
    public let id: Int
    /// Picks the tile icon in the UI.
    public let key: String
    public let label: String
}

// MARK: - Capabilities

/// What the connected earbuds support. Starts empty; the earbuds' own reports
/// fill it in (see `learn` in Jieli.swift), so each model shows only its features.
public struct Capabilities: Equatable {
    /// Noise cancellation (and Off).
    public var noiseControl = false
    public var transparency = false
    public var lowLatency = false
    public var eqPresets: [EqPreset] = []

    public init() {}
}
