// Auto-update with Sparkle. The feed is appcast.xml on the latest GitHub release
// (SUFeedURL in Info.plist); each update is the release's zip, signed with the
// project's EdDSA key (SUPublicEDKey), which is what lets an ad-hoc signed app
// trust it. Checks daily by default; "Check for Updates…" is in the right-click menu.

import AppKit
import Sparkle

final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /// Only an app bundle with a feed and a public key can update itself.
    static var isSupported: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return Bundle.main.bundleURL.pathExtension == "app"
            && (info["SUFeedURL"] as? String)?.isEmpty == false
            && (info["SUPublicEDKey"] as? String)?.isEmpty == false
    }

    override init() {
        super.init()
        guard Self.isSupported else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var isAvailable: Bool { controller != nil }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true) // a menu bar app's windows open behind others otherwise
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// A menu bar app has no Dock icon to badge, so scheduled checks that find an
    /// update show Sparkle's window (handled by the standard driver) without
    /// stealing focus mid-task.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
