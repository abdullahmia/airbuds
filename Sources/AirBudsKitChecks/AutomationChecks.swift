// Per-app automation rules: applied while an app runs, restored when it quits.

import AirBudsKit

/// Per-app automation.
func automationChecks() {
    section("Per-app automation")
    let zoom = AutomationRule(bundleID: "us.zoom.xos", appName: "zoom.us",
                              settings: DeviceSettings(noiseMode: .transparency))
    let game = AutomationRule(bundleID: "com.game", appName: "Game",
                              settings: DeviceSettings(noiseMode: .anc, lowLatency: true))
    let rules = [zoom, game]
    var engine = AutomationEngine()
    var buds = DeviceSettings(noiseMode: .anc, eqPreset: 1, lowLatency: false)
    func step(_ running: [String]) -> DeviceSettings {
        let changes = engine.update(running: running, rules: rules, current: buds).changes
        if let mode = changes.noiseMode { buds.noiseMode = mode }
        if let preset = changes.eqPreset { buds.eqPreset = preset }
        if let on = changes.lowLatency { buds.lowLatency = on }
        return changes
    }
    check(step(["com.apple.finder"]).isEmpty, "no rule app running: nothing changes")
    check(step(["com.apple.finder", "us.zoom.xos"]) == DeviceSettings(noiseMode: .transparency), "zoom opens: transparency")
    check(step(["com.apple.finder", "us.zoom.xos"]).isEmpty, "steady state: nothing more")
    check(step(["com.apple.finder"]) == DeviceSettings(noiseMode: .anc), "zoom quits: back to noise cancellation")
    _ = step(["us.zoom.xos"])
    check(step(["us.zoom.xos", "com.game"]) == DeviceSettings(noiseMode: .anc, lowLatency: true), "newest rule wins")
    check(step(["com.game"]).isEmpty, "zoom quits under the game: game still owns the settings")
    let restored: DeviceSettings = step([])
    check(restored == DeviceSettings(lowLatency: false), "game quits: low latency goes back off")
    check(buds == DeviceSettings(noiseMode: .anc, eqPreset: 1, lowLatency: false), "game quits: back to the original settings")
    _ = step(["us.zoom.xos"])
    buds.noiseMode = .off // user picks Off during the call
    check(step([]).isEmpty, "manual change during a rule is kept")
    var waiting = AutomationEngine()
    check(waiting.update(running: ["us.zoom.xos"], rules: rules, current: DeviceSettings()).changes.isEmpty,
          "nothing sent before the earbuds report their settings")
    let applied = waiting.update(running: ["us.zoom.xos"], rules: rules, current: DeviceSettings(noiseMode: .anc))
    check(applied.changes == DeviceSettings(noiseMode: .transparency), "applies once the earbuds report")
    check(applied.app == "us.zoom.xos", "names the app that caused it")
}
