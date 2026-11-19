// Per-app automation: "while Zoom is open, use Transparency".
//
// Each rule names an app and the settings to use while it runs; nil means
// "don't change". When several rule apps are open, the one opened last wins
// for each setting it sets. When the last app controlling a setting quits, the
// setting goes back to what it was before, unless you changed it yourself in
// the meantime.

import Foundation

/// The settings a rule can change. In a rule, nil means "leave alone"; as a
/// snapshot of the earbuds, nil means "not known yet".
public struct DeviceSettings: Equatable, Codable {
    public var noiseMode: NoiseMode?
    public var eqPreset: Int?
    public var lowLatency: Bool?

    public init(noiseMode: NoiseMode? = nil, eqPreset: Int? = nil, lowLatency: Bool? = nil) {
        self.noiseMode = noiseMode
        self.eqPreset = eqPreset
        self.lowLatency = lowLatency
    }

    public var isEmpty: Bool { noiseMode == nil && eqPreset == nil && lowLatency == nil }
}

public struct AutomationRule: Equatable, Codable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String
    public var settings: DeviceSettings

    public init(bundleID: String, appName: String, settings: DeviceSettings = DeviceSettings()) {
        self.bundleID = bundleID
        self.appName = appName
        self.settings = settings
    }
}

public struct AutomationEngine {
    /// Bundle IDs of running rule apps, oldest first.
    public private(set) var active: [String] = []
    /// What each controlled setting was before a rule took it over.
    private var baseline = DeviceSettings()
    /// What the rules last set; nil for settings no rule controls.
    private var applied = DeviceSettings()

    public init() {}

    /// Call whenever the running apps, the rules or the earbuds' settings change.
    /// `running` lists running apps' bundle IDs, oldest first. Returns the
    /// changes to send (nil fields: leave alone), and the rule app that caused them.
    public mutating func update(running: [String], rules: [AutomationRule],
                                current: DeviceSettings) -> (changes: DeviceSettings, app: String?) {
        let ruled = Set(rules.map(\.bundleID))
        let stillActive = active.filter { running.contains($0) && ruled.contains($0) }
        let started = running.filter { ruled.contains($0) && !stillActive.contains($0) }
        active = stillActive + started

        // The newest active rule that sets each field.
        let byApp = Dictionary(rules.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let newestFirst: [AutomationRule] = active.reversed().compactMap { byApp[$0] }
        var changes = DeviceSettings()
        var cause: String?

        func reconcile<T: Equatable>(_ field: WritableKeyPath<DeviceSettings, T?>) {
            guard let now = current[keyPath: field] else { return } // wait until the earbuds report it
            let owner = newestFirst.first { $0.settings[keyPath: field] != nil }
            if let owner, let target = owner.settings[keyPath: field] {
                if applied[keyPath: field] == nil { baseline[keyPath: field] = now }
                if applied[keyPath: field] != target {
                    applied[keyPath: field] = target
                    if now != target {
                        changes[keyPath: field] = target
                        cause = cause ?? owner.bundleID
                    }
                }
            } else if let last = applied[keyPath: field] {
                // No rule controls it any more: put it back unless the user changed it.
                if now == last, let before = baseline[keyPath: field], before != now {
                    changes[keyPath: field] = before
                }
                applied[keyPath: field] = nil
                baseline[keyPath: field] = nil
            }
        }
        reconcile(\.noiseMode)
        reconcile(\.eqPreset)
        reconcile(\.lowLatency)
        return (changes, cause)
    }

    /// Forget everything, e.g. when the earbuds disconnect. Rules for apps that
    /// are still open apply again on the next update.
    public mutating func reset() {
        active = []
        baseline = DeviceSettings()
        applied = DeviceSettings()
    }
}
