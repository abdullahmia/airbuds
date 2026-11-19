// Commands from outside the panel: the airbuds:// URL scheme (used by
// Shortcuts' "Open URLs" action, `open` in Terminal, and so on).
//
//   airbuds://noise/anc            Noise Cancellation (also noise-cancellation, nc)
//   airbuds://noise/transparency   Transparency
//   airbuds://noise/off            Off
//   airbuds://noise/next           cycle to the next mode
//   airbuds://eq/rock              EQ preset by name or number (0 = Normal)
//   airbuds://low-latency/on       on, off or toggle
//   airbuds://open                 open the panel

import Foundation

public enum AirBudsCommand: Equatable {
    case noise(NoiseMode)
    case nextNoise
    /// Preset name ("rock", "normal") or number, matched against the presets on offer.
    case eq(String)
    /// nil toggles.
    case lowLatency(Bool?)
    case open

    public static let scheme = "airbuds"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let argument = url.pathComponents.first { $0 != "/" }?.lowercased() ?? ""

        switch (host, argument) {
        case ("open", _):
            self = .open
        case ("noise", "anc"), ("noise", "nc"), ("noise", "noise-cancellation"), ("noise", "on"):
            self = .noise(.anc)
        case ("noise", "transparency"):
            self = .noise(.transparency)
        case ("noise", "off"):
            self = .noise(.off)
        case ("noise", "next"), ("noise", "cycle"):
            self = .nextNoise
        case ("eq", let preset) where !preset.isEmpty:
            self = .eq(preset)
        case ("low-latency", "on"):
            self = .lowLatency(true)
        case ("low-latency", "off"):
            self = .lowLatency(false)
        case ("low-latency", "toggle"), ("low-latency", ""):
            self = .lowLatency(nil)
        default:
            return nil
        }
    }

    /// The preset an `eq` argument names, by number, key or label.
    public static func preset(named name: String, in presets: [EqPreset]) -> EqPreset? {
        let wanted = name.lowercased()
        return presets.first { preset in
            String(preset.id) == wanted || preset.key == wanted || preset.label.lowercased() == wanted
        }
    }
}
