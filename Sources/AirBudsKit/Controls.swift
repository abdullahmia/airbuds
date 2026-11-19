// Touch controls and custom EQ: the values Jieli's own app
// (Jieli Home, Android-JL_Bluetooth on GitHub) uses for AC697x earphones, and
// checked against a HOCO EQ34 Plus ANC.

// MARK: - Touch controls

public enum Bud: Int, CaseIterable, Codable {
    case left = 1, right = 2

    public var label: String { self == .left ? "Left" : "Right" }
}

/// What a gesture on one bud does (ADV attribute 02: [bud, gesture, function]).
public struct TouchControl: Equatable, Hashable, Codable {
    public var bud: Bud
    /// 1 single tap, 2 double tap, 3 triple tap (the EQ34 reports this one too).
    public var gesture: Int
    /// A `TouchFunction` raw value; firmware may report others.
    public var function: Int

    public init(bud: Bud, gesture: Int, function: Int) {
        self.bud = bud
        self.gesture = gesture
        self.function = function
    }

    public static func gestureLabel(_ gesture: Int) -> String {
        switch gesture {
        case 1: return "Single Tap"
        case 2: return "Double Tap"
        case 3: return "Triple Tap"
        default: return "Gesture \(gesture)"
        }
    }
}

/// Functions a gesture can have, from Jieli's AC697x headset configuration.
/// (1 and 2, power on and off, exist in firmware but aren't offered.)
public enum TouchFunction: Int, CaseIterable {
    case none = 0
    case playPause = 5
    case next = 4
    case previous = 3
    case volumeUp = 9
    case volumeDown = 10
    case answerCall = 6
    case hangUp = 7
    case callBack = 8
    /// Cycles the noise modes listed in ADV attribute 0A; only on ANC models.
    case noiseControl = 255

    public var label: String {
        switch self {
        case .none: return "Nothing"
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .answerCall: return "Answer Call"
        case .hangUp: return "Hang Up"
        case .callBack: return "Call Back"
        case .noiseControl: return "Switch Noise Mode"
        }
    }

    public static func label(for raw: Int) -> String {
        TouchFunction(rawValue: raw)?.label ?? "Other (\(raw))"
    }
}

// MARK: - Custom EQ

public enum CustomEq {
    /// The EQ mode id for Custom (presets are 0–5).
    public static let id = 6
    /// Gain range per band, in dB (Jieli's app uses the same).
    public static let range = -8...8

    /// Band labels: 31, 62, 125 … 1k, 2k … 16k.
    public static func label(hertz: Int) -> String {
        hertz >= 1000 ? "\(hertz / 1000)k" : "\(hertz)"
    }
}
