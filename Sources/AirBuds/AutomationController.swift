// Applies per-app automation rules: watches apps launching and quitting, and
// asks AirBudsKit's AutomationEngine what to change on the earbuds.

import AppKit
import Combine
import AirBudsKit

final class AutomationController {
    private let controller: EarbudsController
    private let settings: AppSettings
    private let announce: (DeviceSettings, String?) -> Void
    private var engine = AutomationEngine()
    private var cancellables = Set<AnyCancellable>()

    /// `announce` gets each change made, with the name of the app that caused it
    /// (nil when settings go back after the app quits).
    init(controller: EarbudsController, settings: AppSettings,
         announce: @escaping (DeviceSettings, String?) -> Void) {
        self.controller = controller
        self.settings = settings
        self.announce = announce

        let center = NSWorkspace.shared.notificationCenter
        Publishers.Merge(center.publisher(for: NSWorkspace.didLaunchApplicationNotification),
                         center.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .map { _ in () }
            .merge(with: controller.$state.map { _ in () }, settings.$automationRules.map { _ in () })
            .receive(on: RunLoop.main) // after @Published has stored the new value
            .sink { [weak self] in self?.evaluate() }
            .store(in: &cancellables)
    }

    private func evaluate() {
        guard controller.state.connected else {
            engine.reset() // apply again from scratch on the next connection
            return
        }
        let rules = settings.automationRules
        guard !rules.isEmpty || !engine.active.isEmpty else { return }

        let running: [String] = NSWorkspace.shared.runningApplications
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            .compactMap(\.bundleIdentifier)
        let result = engine.update(running: running, rules: rules, current: controller.settings)
        guard !result.changes.isEmpty else { return }

        let appName = result.app.flatMap { id in rules.first { $0.bundleID == id }?.appName }
        Log.info("Automation: \(result.changes) for \(appName ?? "restore")")
        controller.apply(result.changes)
        announce(result.changes, appName)
    }
}
