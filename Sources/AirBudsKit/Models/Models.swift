// Value types the panel shows, and what the connected earbuds support.

import Foundation

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

    /// The six presets most earbuds offer. Automation rules and airbuds:// links
    /// pick from this list; the ids follow Jieli's numbering.
    public static let standard = [
        EqPreset(id: 0, key: "balanced", label: "Normal"),
        EqPreset(id: 1, key: "rock", label: "Rock"),
        EqPreset(id: 2, key: "pop", label: "Pop"),
        EqPreset(id: 3, key: "classical", label: "Classical"),
        EqPreset(id: 4, key: "jazz", label: "Jazz"),
        EqPreset(id: 5, key: "country", label: "Country"),
    ]
}

// MARK: - Capabilities

/// What the connected earbuds support. Starts empty; the earbuds' own reports
/// fill it in (each driver's protocol does; Jieli: Capabilities+Jieli.swift), so each
/// model shows only its features.
public struct Capabilities: Equatable {
    /// Noise cancellation (and Off).
    public var noiseControl = false
    public var transparency = false
    public var lowLatency = false
    /// The earbuds report their name, so they can be renamed.
    public var rename = false
    /// The longest name the earbuds take, in UTF-8 bytes.
    public var maxNameBytes = 0
    /// The earbuds report gesture settings (ADV attribute 02).
    public var touchControls = false
    public var eqPresets: [EqPreset] = []
    /// Band frequencies (Hz) for custom EQ; empty when there's no Custom slot.
    public var eqBands: [Int] = []

    public init() {}

    /// `name` trimmed, or nil if it's empty or longer than these earbuds take.
    public func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxNameBytes else { return nil }
        return trimmed
    }
}
