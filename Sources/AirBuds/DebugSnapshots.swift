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
        s.capabilities.eqPresets = JieliCodec.eqPresets
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
        device.loadSample()
        let offline = EarbudsController()
        let settings = AppSettings()
        let pages: [(String, PanelPage)] = [("main", .main), ("quick", .quickSettings), ("eq", .equalizer)]

        func panel(_ page: PanelPage, _ controller: EarbudsController) -> some View {
            let nav = PanelNavigation()
            nav.page = page
            return PanelView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(nav)
                .fixedSize()
        }

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for (name, page) in pages {
                render(panel(page, device).background(Color(nsColor: .windowBackgroundColor)),
                       dark: dark, to: "\(dir)/\(name)-\(suffix).png")
            }
            render(panel(.main, offline).background(Color(nsColor: .windowBackgroundColor)),
                   dark: dark, to: "\(dir)/disconnected-\(suffix).png")

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
