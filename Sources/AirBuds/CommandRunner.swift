// Runs commands that don't come from the panel: the keyboard shortcut and
// airbuds:// links. Each change shows the on-screen indicator.
//
// A link can arrive before the earbuds are ready, e.g. when it launches the
// app. It then waits up to 20 seconds for them to connect and report.

import AppKit
import Combine
import AirBudsKit

final class CommandRunner {
    private static let wait: TimeInterval = 20

    private let controller: EarbudsController
    private let hud = ModeHUD()
    private let anchor: () -> NSView?
    private let openPanel: () -> Void
    private var pending: (command: AirBudsCommand, until: Date)?
    private var cancellables = Set<AnyCancellable>()

    private enum Outcome {
        case done(HUDMessage?)
        case notReady
        case unsupported(String)
    }

    /// `anchor` is the view the indicator appears under (the status item button).
    init(controller: EarbudsController, anchor: @escaping () -> NSView?, openPanel: @escaping () -> Void) {
        self.controller = controller
        self.anchor = anchor
        self.openPanel = openPanel
        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.retryPending() }
            .store(in: &cancellables)
    }

    /// `wait`: keep trying while the earbuds connect (links); otherwise say
    /// right away that no earbuds are connected (keyboard shortcut).
    func run(_ command: AirBudsCommand, wait: Bool) {
        pending = nil
        switch perform(command) {
        case .done(let message):
            if let message { show(message) }
        case .notReady where wait:
            Log.info("Waiting for earbuds to run \(command)")
            pending = (command, Date().addingTimeInterval(Self.wait))
        case .notReady where controller.state.connected:
            show(HUDMessage(symbol: "earbuds", title: "Connecting…", detail: "Try again in a moment"))
        case .notReady:
            show(HUDMessage(symbol: "earbuds", title: "No Earbuds", detail: "Connect them in Bluetooth settings"))
        case .unsupported(let reason):
            Log.info("Ignoring \(command): \(reason)")
            show(HUDMessage(symbol: "exclamationmark", title: "Not Available", detail: reason))
        }
    }

    func show(_ message: HUDMessage) {
        hud.show(message, below: anchor())
    }

    /// The indicator for a change automation made. `app` is the app that caused
    /// it, or nil when settings go back after the app quit.
    func announce(_ changes: DeviceSettings, app: String?) {
        let detail: String = app ?? "Restored"
        if let mode = changes.noiseMode {
            show(HUDMessage(symbol: mode.symbol, title: mode.label, detail: detail))
        } else if let on = changes.lowLatency {
            show(HUDMessage(symbol: "bolt.fill", title: on ? "Low Latency On" : "Low Latency Off", detail: detail))
        } else if let id = changes.eqPreset,
                  let preset = JieliCodec.eqPresets.first(where: { $0.id == id }) {
            show(HUDMessage(symbol: EqualizerView.symbol(for: preset.key), title: preset.label, detail: detail))
        }
    }

    private func retryPending() {
        guard let (command, until) = pending else { return }
        guard Date() < until else {
            Log.info("Gave up on \(command): earbuds not ready")
            pending = nil
            return
        }
        switch perform(command) {
        case .done(let message):
            pending = nil
            if let message { show(message) }
        case .notReady:
            break
        case .unsupported(let reason):
            pending = nil
            Log.info("Ignoring \(command): \(reason)")
        }
    }

    private func perform(_ command: AirBudsCommand) -> Outcome {
        let state = controller.state
        let caps = state.capabilities
        // The first reads have come back, so missing capabilities are really missing.
        let reported: Bool = state.noiseMode != nil || state.eq.preset != nil || state.quick.lowLatency != nil
        let ready: Bool = state.connected && reported
        switch command {
        case .open:
            openPanel()
            return .done(nil)

        case .noise(let mode):
            guard ready else { return .notReady }
            guard caps.noiseControl else { return .unsupported("These earbuds have no noise control") }
            guard mode != .transparency || caps.transparency else {
                return .unsupported("These earbuds have no Transparency mode")
            }
            controller.setNoiseMode(mode)
            return .done(HUDMessage(symbol: mode.symbol, title: mode.label, detail: "Noise Control"))

        case .nextNoise:
            guard ready else { return .notReady }
            guard let mode = controller.cycleNoiseMode() else {
                return .unsupported("These earbuds have no noise control")
            }
            return .done(HUDMessage(symbol: mode.symbol, title: mode.label, detail: "Noise Control"))

        case .eq(let name):
            guard ready else { return .notReady }
            guard let preset = AirBudsCommand.preset(named: name, in: caps.eqPresets) else {
                return .unsupported("No EQ preset called \"\(name)\"")
            }
            controller.setEqPreset(preset.id)
            return .done(HUDMessage(symbol: EqualizerView.symbol(for: preset.key), title: preset.label, detail: "Equalizer"))

        case .lowLatency(let wanted):
            // Low Latency comes with the battery, in a separate reply.
            let advReported: Bool = state.quick.lowLatency != nil || state.battery != Battery()
            guard state.connected, advReported else { return .notReady }
            guard caps.lowLatency, let current = state.quick.lowLatency else {
                return .unsupported("These earbuds have no Low Latency mode")
            }
            let on: Bool = wanted ?? !current
            controller.setLowLatency(on)
            return .done(HUDMessage(symbol: "bolt.fill", title: on ? "Low Latency On" : "Low Latency Off",
                                    detail: "Quick Settings"))
        }
    }
}
