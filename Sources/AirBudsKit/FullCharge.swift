// Decides when to say "fully charged".
//
// A part (left bud, right bud, case) alerts when it reaches 100% after being
// seen charging below 100%, so connecting buds that are already full stays
// quiet. Some firmware clears the charging flag at 100%, so a full report
// counts even without it. Charging that stops short of 100% disarms the part.

public struct FullChargeTracker {
    public static let full = 100

    /// Parts seen charging below 100% that haven't reached it yet.
    private var charging: Set<BatteryPart> = []

    public init() {}

    /// Feed the latest battery report; returns the parts that just became full.
    public mutating func update(_ battery: Battery) -> [BatteryPart] {
        let parts: [(BatteryPart, BatteryLevel?)] = [
            (.left, battery.left), (.right, battery.right), (.case, battery.case),
        ]
        return parts.compactMap { part, info in
            guard let info else { return nil } // not reported; keep what we knew
            return update(part, level: info.level, charging: info.charging) ? part : nil
        }
    }

    mutating func update(_ part: BatteryPart, level: Int, charging isCharging: Bool) -> Bool {
        if level >= Self.full {
            return charging.remove(part) != nil
        }
        if isCharging {
            charging.insert(part)
        } else {
            charging.remove(part)
        }
        return false
    }

    public mutating func reset() { charging.removeAll() }
}
