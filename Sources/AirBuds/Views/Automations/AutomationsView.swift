// Automations window: settings to use while particular apps are open.
// Opened from the right-click menu and from Quick Settings.

import AppKit
import AirBudsKit
import SwiftUI
import UniformTypeIdentifiers

final class AutomationsWindow {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AutomationsView().environmentObject(settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Automations"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 460, height: 440))
            window.contentMinSize = NSSize(width: 420, height: 300)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AutomationsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            Text("While an app is open, AirBuds switches your earbuds to these settings, and switches back when it quits.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if settings.automationRules.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Automations").font(.system(size: 13, weight: .semibold))
                    Text("Add an app, then pick what your earbuds should do while it's open.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    ForEach(settings.automationRules) { rule in
                        RuleSection(bundleID: rule.bundleID)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack {
                AddAppMenu()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 420, minHeight: 300)
    }
}

// MARK: - One rule

private struct RuleSection: View {
    let bundleID: String
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let rule = settings.automationRules.first(where: { $0.bundleID == bundleID }) {
            Section {
                Picker("Noise Control", selection: field(\.noiseMode)) {
                    Text("No Change").tag(NoiseMode?.none)
                    Divider()
                    ForEach(NoiseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(NoiseMode?.some(mode))
                    }
                }
                Picker("Equalizer", selection: field(\.eqPreset)) {
                    Text("No Change").tag(Int?.none)
                    Divider()
                    ForEach(EqPreset.standard) { preset in
                        Text(preset.label).tag(Int?.some(preset.id))
                    }
                }
                Picker("Low Latency", selection: field(\.lowLatency)) {
                    Text("No Change").tag(Bool?.none)
                    Divider()
                    Text("On").tag(Bool?.some(true))
                    Text("Off").tag(Bool?.some(false))
                }
            } header: {
                HStack(spacing: 8) {
                    Image(nsImage: AppInfo.icon(bundleID: bundleID))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(rule.appName).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        settings.automationRules.removeAll { $0.bundleID == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(rule.appName)")
                }
                .foregroundStyle(.primary)
            }
        }
    }

    /// A binding to one setting of this rule.
    private func field<T>(_ path: WritableKeyPath<DeviceSettings, T?>) -> Binding<T?> {
        Binding(
            get: { settings.automationRules.first { $0.bundleID == bundleID }?.settings[keyPath: path] },
            set: { value in
                guard let index = settings.automationRules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
                settings.automationRules[index].settings[keyPath: path] = value
            }
        )
    }
}

// MARK: - Adding apps

private struct AddAppMenu: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let taken = Set(settings.automationRules.map(\.bundleID))
        let running = AppInfo.runningApps().filter { !taken.contains($0.bundleID) }
        Menu {
            if !running.isEmpty {
                Section("Open Apps") {
                    ForEach(running, id: \.bundleID) { app in
                        Button(app.name) { add(app) }
                    }
                }
                Divider()
            }
            Button("Choose App…") { choose() }
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .fixedSize()
    }

    private func add(_ app: AppInfo) {
        guard !settings.automationRules.contains(where: { $0.bundleID == app.bundleID }) else { return }
        settings.automationRules.append(AutomationRule(bundleID: app.bundleID, appName: app.name))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an app to automate"
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let app = AppInfo(url: url) else { return }
            add(app)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

struct AppInfo {
    let bundleID: String
    let name: String

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        bundleID = id
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Apps with a Dock icon that are open now, by name.
    static func runningApps() -> [AppInfo] {
        let own = Bundle.main.bundleIdentifier
        let apps: [AppInfo] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return AppInfo(bundleID: id, name: app.localizedName ?? id)
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func icon(bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
