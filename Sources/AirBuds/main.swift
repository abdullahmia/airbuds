// AirBuds: control Hoco earbuds from the menu bar.
// A status item opens a popover with the SwiftUI panel; right-click shows the app
// menu. Also handles the ⌃⌥N shortcut, airbuds:// links and per-app automations.

import AppKit
import Combine
import AirBudsKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static let appName = "AirBuds"

    private let controller = EarbudsController()
    private let settings = AppSettings()
    private let navigation = PanelNavigation()
    private lazy var history = BatteryHistoryStore(controller: controller)
    private lazy var automationsWindow = AutomationsWindow(settings: settings)
    private var notifier: BatteryNotifier?
    private var commands: CommandRunner?
    private var automation: AutomationController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var lastClosedAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        LoginItem.enableOnFirstRun()

        navigation.openAutomations = { [weak self] in
            self?.popover.performClose(nil)
            self?.automationsWindow.show()
        }
        let panel = PanelView()
            .environmentObject(controller)
            .environmentObject(settings)
            .environmentObject(navigation)
            .environmentObject(history)
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize // popover follows the panel's height
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageLeading
            button.toolTip = Self.appName
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Keep the menu bar icon, title and tooltip in sync with the buds.
        controller.$state.combineLatest(settings.$menuBarBattery, settings.$menuBarNoiseMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, mode, showNoise in
                self?.updateStatusItem(state: state, mode: mode, showNoise: showNoise)
            }
            .store(in: &cancellables)

        notifier = BatteryNotifier(controller: controller, settings: settings)
        let commands = CommandRunner(controller: controller,
                                     anchor: { [weak self] in self?.statusItem.button },
                                     openPanel: { [weak self] in self?.showPopover() })
        self.commands = commands
        automation = AutomationController(controller: controller, settings: settings) { changes, app in
            commands.announce(changes, app: app)
        }
        settings.$noiseShortcut
            .removeDuplicates()
            .sink { [weak self] on in self?.setNoiseShortcut(on) }
            .store(in: &cancellables)
        _ = history // start recording
        controller.start()

        #if DEBUG
        // AIRBUDS_FAKE_LOW_BATTERY=1: pretend low earbuds are connected, to test alerts.
        if ProcessInfo.processInfo.environment["AIRBUDS_FAKE_LOW_BATTERY"] != nil {
            controller.stop()
            controller.loadSample()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                var state = self.controller.state
                state.battery.left = BatteryLevel(level: 18, charging: false)
                state.battery.right = BatteryLevel(level: 9, charging: false)
                self.controller.setSampleState(state)
            }
        }
        #endif

        // Dev convenience: AIRBUDS_OPEN=1 opens the panel on launch.
        if ProcessInfo.processInfo.environment["AIRBUDS_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.saveNow()
        // Drop the BLE link so the earbuds are free for the next launch (or a phone).
        controller.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// airbuds:// links, e.g. from the Shortcuts app's "Open URLs" action.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = AirBudsCommand(url: url) else {
                Log.info("Unknown link: \(url.absoluteString)")
                continue
            }
            commands?.run(command, wait: true)
        }
    }

    private func setNoiseShortcut(_ on: Bool) {
        hotKey = nil
        guard on else { return }
        let shortcut = HotKey.noiseControl
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.commands?.run(.nextNoise, wait: false)
        }
    }

    private func updateStatusItem(state: DeviceState, mode: MenuBarBattery, showNoise: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarIcon.make(noiseMode: state.connected && showNoise ? state.noiseMode : nil)
        let text = state.connected ? mode.text(for: state.battery) : nil
        button.title = text.map { " \($0)" } ?? ""
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        button.toolTip = state.connected ? "\(Self.appName) · \(state.name ?? "")" : Self.appName
    }

    // MARK: Popover

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastClosedAt) > 0.25 {
            // A click on the icon closes the transient popover first; don't reopen it.
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        controller.refreshBattery()
        navigation.page = .main
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosedAt = Date()
        navigation.page = .main
    }

    // MARK: Context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isSupported
        menu.addItem(login)

        let batteryItem = NSMenuItem(title: "Battery in Menu Bar", action: nil, keyEquivalent: "")
        let batteryMenu = NSMenu()
        for mode in MenuBarBattery.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setMenuBarBattery(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.menuBarBattery == mode ? .on : .off
            batteryMenu.addItem(item)
        }
        batteryItem.submenu = batteryMenu
        menu.addItem(batteryItem)

        let noiseIcon = NSMenuItem(title: "Noise Mode in Menu Bar", action: #selector(toggleMenuBarNoiseMode), keyEquivalent: "")
        noiseIcon.target = self
        noiseIcon.state = settings.menuBarNoiseMode ? .on : .off
        noiseIcon.toolTip = "Show Noise Cancellation or Transparency next to the icon"
        menu.addItem(noiseIcon)

        menu.addItem(.separator())
        let alerts = NSMenuItem(title: "Low Battery Alerts", action: #selector(toggleLowBatteryAlerts), keyEquivalent: "")
        alerts.target = self
        alerts.state = settings.lowBatteryAlerts ? .on : .off
        alerts.toolTip = "Notify at 20% and 10% for each earbud and the case"
        menu.addItem(alerts)

        let charged = NSMenuItem(title: "Fully Charged Alerts", action: #selector(toggleFullChargeAlerts), keyEquivalent: "")
        charged.target = self
        charged.state = settings.fullChargeAlerts ? .on : .off
        charged.toolTip = "Notify when an earbud or the case reaches 100% while charging"
        menu.addItem(charged)

        menu.addItem(.separator())
        let shortcut = NSMenuItem(title: "Noise Control Shortcut (\(HotKey.noiseControl.display))",
                                  action: #selector(toggleNoiseShortcut), keyEquivalent: "")
        shortcut.target = self
        shortcut.state = settings.noiseShortcut ? .on : .off
        shortcut.toolTip = "Press \(HotKey.noiseControl.display) anywhere to switch Noise Cancellation, Transparency and Off"
        if settings.noiseShortcut && hotKey == nil {
            shortcut.toolTip = "\(HotKey.noiseControl.display) is already used by another app"
        }
        menu.addItem(shortcut)

        let automations = NSMenuItem(title: "Automations…", action: #selector(showAutomations), keyEquivalent: "")
        automations.target = self
        menu.addItem(automations)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(Self.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // Attach temporarily so the menu drops down from the icon like a normal menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func toggleLowBatteryAlerts() {
        settings.lowBatteryAlerts.toggle()
    }

    @objc private func toggleFullChargeAlerts() {
        settings.fullChargeAlerts.toggle()
    }

    @objc private func toggleMenuBarNoiseMode() {
        settings.menuBarNoiseMode.toggle()
    }

    @objc private func toggleNoiseShortcut() {
        settings.noiseShortcut.toggle()
    }

    @objc private func showAutomations() {
        automationsWindow.show()
    }

    @objc private func setMenuBarBattery(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = MenuBarBattery(rawValue: raw) {
            settings.menuBarBattery = mode
        }
    }
}

#if DEBUG
MainActor.assumeIsolated { DebugSnapshots.runIfRequested() }
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
