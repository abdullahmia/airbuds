// Value types the panel shows, and what the connected earbuds support.

@inline(__always) func at(_ p: [UInt8], _ i: Int) -> UInt8? { i >= 0 && i < p.count ? p[i] : nil }

// MARK: - Battery

public struct BatteryLevel: Equatable {
    public var level: Int
    public var charging: Bool
    public init(level: Int, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

public struct Battery: Equatable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?
    public var `case`: BatteryLevel?
    public init() {}
}

// MARK: - Settings

public enum NoiseMode: String, CaseIterable {
    case anc, transparency, off
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
