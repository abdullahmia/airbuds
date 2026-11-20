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
        var byApp: [String: AutomationRule] = [:]
        for rule in rules where byApp[rule.bundleID] == nil { byApp[rule.bundleID] = rule }
        let newestFirst: [AutomationRule] = active.reversed().compactMap { byApp[$0] }
        var changes = DeviceSettings()
        var cause: String?

        // One setting at a time, without key paths (they depend on the OS's Swift runtime).
        let noiseOwner: AutomationRule? = newestFirst.first { $0.settings.noiseMode != nil }
        Self.reconcile(now: current.noiseMode, target: noiseOwner?.settings.noiseMode, owner: noiseOwner?.bundleID,
                       applied: &applied.noiseMode, baseline: &baseline.noiseMode,
                       change: &changes.noiseMode, cause: &cause)
        let eqOwner: AutomationRule? = newestFirst.first { $0.settings.eqPreset != nil }
        Self.reconcile(now: current.eqPreset, target: eqOwner?.settings.eqPreset, owner: eqOwner?.bundleID,
                       applied: &applied.eqPreset, baseline: &baseline.eqPreset,
                       change: &changes.eqPreset, cause: &cause)
        let latencyOwner: AutomationRule? = newestFirst.first { $0.settings.lowLatency != nil }
        Self.reconcile(now: current.lowLatency, target: latencyOwner?.settings.lowLatency, owner: latencyOwner?.bundleID,
                       applied: &applied.lowLatency, baseline: &baseline.lowLatency,
                       change: &changes.lowLatency, cause: &cause)
        return (changes, cause)
    }

    /// One setting: take it over for the newest rule that sets it (`target`, from
    /// app `owner`), or give it back, restoring the old value unless the user
    /// changed it, when no rule does.
    private static func reconcile<T: Equatable>(now: T?, target: T?, owner: String?,
                                                applied: inout T?, baseline: inout T?,
                                                change: inout T?, cause: inout String?) {
        guard let now else { return } // wait until the earbuds report it
        if let target {
            if applied == nil { baseline = now }
            guard applied != target else { return }
            applied = target
            if now != target {
                change = target
                if cause == nil { cause = owner }
            }
        } else if let last = applied {
            if now == last, let before = baseline, before != now {
                change = before
            }
            applied = nil
            baseline = nil
        }
    }

    /// Forget everything, e.g. when the earbuds disconnect. Rules for apps that
    /// are still open apply again on the next update.
    public mutating func reset() {
        active = []
        baseline = DeviceSettings()
        applied = DeviceSettings()
    }
}
