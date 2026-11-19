// Posts macOS notifications when the earbuds' battery runs low or finishes
// charging. When to alert lives in AirBudsKit's LowBatteryTracker and
// FullChargeTracker.

import Combine
import Foundation
import AirBudsKit
import UserNotifications

final class BatteryNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var tracker = LowBatteryTracker()
    private var fullTracker = FullChargeTracker()
    private var deviceName: String?
    private var authorizationRequested = false
    private var cancellables = Set<AnyCancellable>()

    /// UNUserNotificationCenter only works inside an app bundle; a bare
    /// `swift run` binary would crash on first use.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil

    init(controller: EarbudsController, settings: AppSettings) {
        super.init()
        center?.delegate = self

        controller.$state
            .map { ($0.connected, $0.name, $0.battery) }
            .removeDuplicates { $0 == $1 }
            .combineLatest(settings.$lowBatteryAlerts, settings.$fullChargeAlerts)
            .receive(on: RunLoop.main)
            .sink { [weak self] report, low, full in
                self?.handle(connected: report.0, name: report.1, battery: report.2, low: low, full: full)
            }
            .store(in: &cancellables)
    }

    private func handle(connected: Bool, name: String?, battery: Battery, low: Bool, full: Bool) {
        guard connected, let name else { return } // keep state across brief disconnects
        if name != deviceName {
            deviceName = name
            tracker.reset()
            fullTracker.reset()
        }
        // Ask for permission the first time earbuds connect, not at app launch.
        if low || full { requestAuthorizationOnce() }

        // Always run the trackers, so turning alerts on later doesn't fire stale ones.
        let alerts = tracker.update(battery)
        let charged = fullTracker.update(battery)
        if low, !alerts.isEmpty { post(alerts, device: name) }
        if full, !charged.isEmpty { postCharged(charged, device: name) }
    }

    private func requestAuthorizationOnce() {
        guard let center, !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.info("Notification permission error: \(error.localizedDescription)") }
            Log.info("Notifications \(granted ? "allowed" : "not allowed")")
        }
    }

    private func post(_ alerts: [LowBatteryAlert], device: String) {
        let content = UNMutableNotificationContent()
        let critical = alerts.contains { $0.threshold <= 10 }
        content.title = critical ? "Battery Very Low" : "Low Battery"
        content.subtitle = device
        content.body = alerts
            .map { "\($0.part.label) \($0.level)%" }
            .joined(separator: " · ")
            + (critical ? ". Charge soon." : "")
        content.sound = .default

        Log.info("Low battery: \(content.body)")
        // One notification per kind; a newer alert replaces the older one.
        deliver(content, id: "low-battery")
    }

    private func postCharged(_ parts: [BatteryPart], device: String) {
        let content = UNMutableNotificationContent()
        content.title = "Fully Charged"
        content.subtitle = device
        let names: String = ListFormatter.localizedString(byJoining: parts.map { $0.label })
        let verb: String = parts.count == 1 ? "is" : "are"
        content.body = "\(names) \(verb) at 100%."
        content.sound = .default

        Log.info("Fully charged: \(content.body)")
        deliver(content, id: "fully-charged")
    }

    private func deliver(_ content: UNNotificationContent, id: String) {
        guard let center else { return }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        // Waits for the permission prompt on first use (returns at once after that),
        // so an alert that fires right as the buds connect isn't dropped.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request) { error in
                if let error { Log.info("Could not post notification: \(error.localizedDescription)") }
            }
        }
    }

    /// Show the banner even while the panel is open (the app counts as active then).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
