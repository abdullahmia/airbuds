// High-level earbud state and every setting the panel can change. The protocol
// work happens in JieliSession; this keeps the state the UI renders.
//
// Setters ignore requests while a previous change of the same kind is still in
// flight, so rapid clicks can't queue up commands on the earbuds. Runs on the
// main thread (CoreBluetooth and IOBluetooth deliver their callbacks there).

import Foundation
import AirBudsKit

final class EarbudsController: ObservableObject {
    @Published private(set) var state = DeviceState()

    private static let batteryPoll: TimeInterval = 60

    private let session = JieliSession()
    private var batteryTimer: Timer?

    private lazy var noise = ConfirmedSetting<NoiseMode>(
        read: { [unowned self] in self.session.readNoiseMode() },
        onTimeout: { [unowned self] in self.state.noisePending = false }
    )
    private lazy var eqConfirm = ConfirmedSetting<Int>(
        read: { [unowned self] in self.session.readEq() },
        onTimeout: { [unowned self] in self.state.eq.pending = false }
    )
    private lazy var lowLatencyConfirm = ConfirmedSetting<Bool>(
        read: { [unowned self] in self.session.readLowLatency() },
        onTimeout: { [unowned self] in self.state.quick.lowLatencyPending = false }
    )

    private var caps: Capabilities { state.capabilities }

    init() {
        session.onConnected = { [unowned self] name, address, firmware in
            self.didConnect(name: name, address: address, firmware: firmware)
        }
        session.onDisconnected = { [unowned self] in self.didDisconnect() }
        session.onSysInfo = { [unowned self] info in self.onSysInfo(info) }
        session.onAdvInfo = { [unowned self] info in self.onAdvInfo(info) }
    }

    func start() { session.start() }

    #if DEBUG
    func setSampleState(_ sample: DeviceState) { state = sample }
    #endif

    func stop() {
        resetTimers()
        session.stop()
    }

    func refreshBattery() {
        if state.connected { session.readBattery() }
    }

    // MARK: - Settings

    func setNoiseMode(_ mode: NoiseMode) {
        guard state.connected, caps.noiseControl, !noise.pending, mode != state.noiseMode else { return }
        session.setNoiseMode(mode)
        noise.begin(mode)
        state.noiseMode = mode
        state.noisePending = true
    }

    func setLowLatency(_ on: Bool) {
        guard state.connected, caps.lowLatency, !lowLatencyConfirm.pending, state.quick.lowLatency != on else { return }
        session.setLowLatency(on)
        lowLatencyConfirm.begin(on)
        state.quick.lowLatency = on
        state.quick.lowLatencyPending = true
    }

    func setEqPreset(_ id: Int) {
        guard state.connected, !eqConfirm.pending, id != state.eq.preset,
              caps.eqPresets.contains(where: { $0.id == id }) else { return }
        session.setEqPreset(id)
        eqConfirm.begin(id)
        state.eq.preset = id
        state.eq.pending = true
    }

    /// Switches to the next noise mode (NC → Transparency → Off) and returns it.
    /// While a change is still unconfirmed, returns that change's target instead.
    /// nil when the earbuds have no noise control.
    @discardableResult
    func cycleNoiseMode() -> NoiseMode? {
        guard state.connected, caps.noiseControl else { return nil }
        if noise.pending { return state.noiseMode }
        let next = NoiseMode.next(after: state.noiseMode, transparency: caps.transparency)
        setNoiseMode(next)
        return next
    }

    /// The settings automation can change, as last reported (nil = not known yet).
    var settings: DeviceSettings {
        guard state.connected else { return DeviceSettings() }
        return DeviceSettings(noiseMode: caps.noiseControl ? state.noiseMode : nil,
                              eqPreset: caps.eqPresets.isEmpty ? nil : state.eq.preset,
                              lowLatency: caps.lowLatency ? state.quick.lowLatency : nil)
    }

    /// Sends every non-nil field.
    func apply(_ changes: DeviceSettings) {
        if let mode = changes.noiseMode { setNoiseMode(mode) }
        if let preset = changes.eqPreset { setEqPreset(preset) }
        if let on = changes.lowLatency { setLowLatency(on) }
    }

    // MARK: - Reports

    private func onSysInfo(_ info: JieliSysInfo) {
        guard state.connected else { return }
        state.capabilities.learn(from: info)
        if let mode = info.noiseMode, noise.accept(mode) {
            state.noiseMode = mode
            state.noisePending = false
        }
        if let preset = info.eqPreset, eqConfirm.accept(preset) {
            state.eq.preset = preset
            state.eq.pending = false
        }
    }

    private func onAdvInfo(_ info: JieliAdvInfo) {
        guard state.connected else { return }
        state.capabilities.learn(from: info)
        if let battery = info.battery { state.battery = battery }
        if let on = info.lowLatency, lowLatencyConfirm.accept(on) {
            state.quick.lowLatency = on
            state.quick.lowLatencyPending = false
        }
    }

    // MARK: - Connection

    private func didConnect(name: String, address: String, firmware: String?) {
        resetTimers()
        var fresh = DeviceState()
        fresh.connected = true
        fresh.name = name
        fresh.address = address
        fresh.quick.firmware = firmware
        state = fresh
        session.readAll()

        batteryTimer = Timer.scheduledTimer(withTimeInterval: Self.batteryPoll, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    private func didDisconnect() {
        resetTimers()
        if state.connected { state = DeviceState() }
    }

    private func resetTimers() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        noise.reset()
        eqConfirm.reset()
        lowLatencyConfirm.reset()
    }
}
