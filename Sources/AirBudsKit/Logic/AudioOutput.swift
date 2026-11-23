// Which CoreAudio output device is the connected earbuds. macOS names a
// Bluetooth audio device by its address, e.g. "AA-BB-CC-DD-EE-FF:output".

public enum AudioOutput {
    /// Whether the audio device with this UID belongs to the earbuds at `address`.
    public static func isEarbuds(uid: String, address: String) -> Bool {
        let address = hexDigits(address)
        let uid = hexDigits(uid)
        guard address.count == 12, uid.hasPrefix(address) else { return false }
        // The address, then nothing or a suffix like "output", not more hex digits
        // (displays and USB devices have long hex UIDs too).
        return uid.dropFirst(12).first.map { !$0.isHexDigit } ?? true
    }

    /// Lowercased, without the "-" or ":" separators.
    private static func hexDigits(_ s: String) -> String {
        s.lowercased().filter { $0 != "-" && $0 != ":" }
    }

    /// SF Symbol for a volume level (0...1), like the menu bar's Sound icon.
    public static func symbol(level: Double, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        switch level {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
