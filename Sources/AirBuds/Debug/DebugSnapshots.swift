// Debug builds only: `AIRBUDS_SNAPSHOT=<dir> swift run AirBuds` renders each
// panel page with sample data to PNGs and exits. Handy for checking layout
// without earbuds or screen-recording permission.

#if DEBUG
import AppKit
import AirBudsKit
import SwiftUI

extension EarbudsController {
    func loadSample() {
        var s = DeviceState()
        s.connected = true
        s.name = "HOCO EQ34 Plus ANC"
        s.address = "aa-bb-cc-dd-ee-ff"
        s.capabilities.noiseControl = true
        s.capabilities.transparency = true
        s.capabilities.lowLatency = true
        s.capabilities.rename = true
        s.capabilities.maxNameBytes = 20
        s.capabilities.touchControls = true
        s.capabilities.eqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        s.eq.customGains = [4, 3, 1, 0, -1, 0, 1, 2, 3, 2]
        for bud in Bud.allCases {
            for (gesture, function) in [(1, 5), (2, 4), (3, 3)] {
                s.touchControls.append(TouchControl(bud: bud, gesture: gesture, function: function))
            }
        }
        s.capabilities.eqPresets = EqPreset.standard
        s.battery.left = BatteryLevel(level: 85, charging: false)
        s.battery.right = BatteryLevel(level: 18, charging: false)
        s.battery.case = BatteryLevel(level: 60, charging: true)
        s.noiseMode = .anc
        s.quick.lowLatency = false
        s.quick.firmware = "2.4.0"
        s.eq.preset = 1
        setSampleState(s)
    }
}

extension BatteryHistory {
    /// An hour and a half of listening: left drains 10% every 30 minutes, right
    /// 10% every 12, sampled every minute like the real poll.
    static func sample(now: Date = Date()) -> BatteryHistory {
        var history = BatteryHistory()
        let minutes = 90
        for minute in 0...minutes {
            let elapsed = Double(minutes - minute) * 60
            var battery = Battery()
            battery.left = BatteryLevel(level: 100 - minute / 30 * 10, charging: false)
            battery.right = BatteryLevel(level: 100 - minute / 12 * 10, charging: false)
            battery.case = BatteryLevel(level: 60, charging: true)
            history.record(battery, at: now.addingTimeInterval(-elapsed))
        }
        return history
    }
}

enum DebugSnapshots {
    @MainActor static func runIfRequested() {
        // AIRBUDS_LOGIN=off: drop this bundle's Open at Login registration (dev builds).
        if ProcessInfo.processInfo.environment["AIRBUDS_LOGIN"] == "off" {
            LoginItem.setEnabled(false)
            print("Open at Login now: \(LoginItem.isEnabled ? "on" : "off")")
            exit(0)
        }
        guard let dir = ProcessInfo.processInfo.environment["AIRBUDS_SNAPSHOT"] else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let device = EarbudsController()
        let history = BatteryHistory.sample()
        device.loadSample()
        if let last = history.samples.last {
            var state = device.state
            state.battery = last.battery
            device.setSampleState(state)
        }
        let offline = EarbudsController()
        offline.setSamplePaired([PairedEarbuds(name: "HOCO EQ34 Plus ANC", address: "aa-bb-cc-dd-ee-ff", connected: false)])
        let settings = AppSettings()
        let store = BatteryHistoryStore(controller: device, live: false)
        store.setSample(history)
        let pages: [(String, PanelPage)] = [
            ("main", .main), ("quick", .quickSettings), ("eq", .equalizer), ("battery", .battery),
            ("touch", .touchControls),
        ]
        let custom = EarbudsController()
        custom.setSampleState({ var c = device.state; c.eq.preset = CustomEq.id; return c }())

        func panel(_ page: PanelPage, _ controller: EarbudsController) -> some View {
            let nav = PanelNavigation()
            nav.page = page
            return PanelView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(nav)
                .environmentObject(store)
                .fixedSize()
        }

        // Automations window with two sample rules (not saved).
        let automationSettings = AppSettings(persist: false)
        automationSettings.automationRules = [
            AutomationRule(bundleID: "com.apple.FaceTime", appName: "FaceTime",
                           settings: DeviceSettings(noiseMode: .transparency)),
            AutomationRule(bundleID: "com.apple.Music", appName: "Music",
                           settings: DeviceSettings(noiseMode: .anc, eqPreset: 2)),
        ]
        let automations = AutomationsView()
            .environmentObject(automationSettings)
            .frame(width: 460, height: 440)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for (name, page) in pages {
                render(panel(page, device).background(Color(nsColor: .windowBackgroundColor)),
                       dark: dark, to: "\(dir)/\(name)-\(suffix).png")
            }
            render(panel(.main, offline).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/disconnected-\(suffix).png")
            render(panel(.equalizer, custom).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/eq-custom-\(suffix).png")
            render(automations.background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/automations-\(suffix).png")
            let hud = Local(HUDMessage(symbol: NoiseMode.transparency.symbol, title: "Transparency", detail: "Noise Control"))
            render(HUDView(model: hud).padding(20), dark: dark, to: "\(dir)/hud-\(suffix).png")

            // README hero: the pages side by side, each as a floating panel.
            let hero = HStack(alignment: .top, spacing: 28) {
                ForEach(Array([PanelPage.main, .quickSettings, .equalizer].enumerated()), id: \.offset) { _, page in
                    panel(page, device)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                }
            }
            .padding(40)
            .background(LinearGradient(
                colors: dark ? [Color(white: 0.10), Color(white: 0.20)] : [Color(white: 0.86), Color(white: 0.97)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            render(hero, dark: dark, to: "\(dir)/overview-\(suffix).png")
        }
        exit(0)
    }

    /// Draws a view through a real (offscreen) window so native AppKit controls render too.
    @MainActor private static func render<V: View>(_ view: V, dark: Bool, to path: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

#endif
