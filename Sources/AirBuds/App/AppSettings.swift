// User preferences kept in UserDefaults, and Open at Login.

import Foundation
import AirBudsKit
import ServiceManagement

/// What to show next to the menu bar icon.
enum MenuBarBattery: String, CaseIterable, Identifiable {
    case off, both, average, minimum
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Icon Only"
        case .both: return "Left · Right"
        case .average: return "Average"
        case .minimum: return "Lowest"
        }
    }

    /// nil when there's nothing to show.
    func text(for battery: Battery) -> String? {
        switch (self, battery.left?.level, battery.right?.level) {
        case (.off, _, _):
            return nil
        case (.both, let l?, let r?):
            return l == r ? "\(l)%" : "\(l)·\(r)%"
        case (.average, let l?, let r?):
            return "\((l + r) / 2)%"
        case (.minimum, let l?, let r?):
            return "\(min(l, r))%"
        case (_, let l?, nil):
            return "\(l)%"
        case (_, nil, let r?):
            return "\(r)%"
        default:
            return nil
        }
    }
}

final class AppSettings: ObservableObject {
    /// nil: keep changes in memory only.
    private let defaults: UserDefaults?

    @Published var menuBarBattery: MenuBarBattery {
        didSet { defaults?.set(menuBarBattery.rawValue, forKey: "menuBarBattery") }
    }

    /// Notify when a bud or the case drops to 20% and 10%.
    @Published var lowBatteryAlerts: Bool {
        didSet { defaults?.set(lowBatteryAlerts, forKey: "lowBatteryAlerts") }
    }

    /// Notify when a bud or the case finishes charging.
    @Published var fullChargeAlerts: Bool {
        didSet { defaults?.set(fullChargeAlerts, forKey: "fullChargeAlerts") }
    }

    /// Badge the menu bar icon with the current noise mode.
    @Published var menuBarNoiseMode: Bool {
        didSet { defaults?.set(menuBarNoiseMode, forKey: "menuBarNoiseMode") }
    }

    /// ⌃⌥N cycles the noise mode from anywhere.
    @Published var noiseShortcut: Bool {
        didSet { defaults?.set(noiseShortcut, forKey: "noiseShortcut") }
    }

    /// Settings to use while particular apps are open.
    @Published var automationRules: [AutomationRule] {
        didSet {
            if let data = try? JSONEncoder().encode(automationRules) {
                defaults?.set(data, forKey: "automationRules")
            }
        }
    }

    /// `persist: false` starts from the defaults and saves nothing (for snapshots).
    init(persist: Bool = true) {
        let defaults: UserDefaults? = persist ? .standard : nil
        self.defaults = defaults
        menuBarBattery = MenuBarBattery(rawValue: defaults?.string(forKey: "menuBarBattery") ?? "") ?? .off
        lowBatteryAlerts = defaults?.object(forKey: "lowBatteryAlerts") as? Bool ?? true
        fullChargeAlerts = defaults?.object(forKey: "fullChargeAlerts") as? Bool ?? true
        menuBarNoiseMode = defaults?.object(forKey: "menuBarNoiseMode") as? Bool ?? true
        noiseShortcut = defaults?.object(forKey: "noiseShortcut") as? Bool ?? true
        let rules = defaults?.data(forKey: "automationRules")
            .flatMap { try? JSONDecoder().decode([AutomationRule].self, from: $0) }
        automationRules = rules ?? []
    }
}

/// Open at Login via SMAppService. Only an app bundle can be a login item.
enum LoginItem {
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool { isSupported && SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        guard isSupported else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.info("Open at Login change failed: \(error.localizedDescription)")
        }
    }

    /// Turn Open at Login on once, the first time the app runs from /Applications
    /// (not from a development build folder).
    static func enableOnFirstRun() {
        let installed = Bundle.main.bundlePath.hasPrefix("/Applications/")
        guard isSupported, installed, !UserDefaults.standard.bool(forKey: "loginItemInitialized") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemInitialized")
        setEnabled(true)
    }
}
