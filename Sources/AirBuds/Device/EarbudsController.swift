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
    /// Paired supported earbuds, connected for audio or not.
    @Published private(set) var paired: [PairedEarbuds] = []
    /// Earbuds being connected from the panel.
    @Published private(set) var connecting: String?
    /// Earbuds whose last connection attempt failed.
    @Published private(set) var connectFailed: String?

    private static let batteryPoll: TimeInterval = 60
    /// Custom EQ changes are sent once the slider rests this long.
    private static let customEqDelay: TimeInterval = 0.12

    private let session = JieliSession()
    private let classic = ClassicConnection()
    private var batteryTimer: Timer?
    private let customEqTimer = Delayed()
    /// Custom gains were re-sent after connecting (the earbuds don't keep them).
    private var customEqRestored = false

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
    private lazy var nameConfirm = ConfirmedSetting<String>(
        read: { [unowned self] in self.session.readName() },
        onTimeout: { [unowned self] in self.state.namePending = false }
    )
    /// Target: the changed gesture; a report matches when it contains it.
    private lazy var touchConfirm = ConfirmedSetting<[TouchControl]>(
        read: { [unowned self] in self.session.readTouchControls() },
        matches: { report, target in Set(target).isSubset(of: Set(report)) },
        onTimeout: { [unowned self] in self.state.touchPending = false }
    )

    private var caps: Capabilities { state.capabilities }

    init() {
        session.onConnected = { [unowned self] name, address, firmware in
            self.didConnect(name: name, address: address, firmware: firmware)
        }
        session.onDisconnected = { [unowned self] in self.didDisconnect() }
        session.onSysInfo = { [unowned self] info in self.onSysInfo(info) }
        session.onAdvInfo = { [unowned self] info in self.onAdvInfo(info) }
        session.onPairedChanged = { [unowned self] devices in self.paired = devices }
        classic.onFinished = { [unowned self] address, success in
            if self.connecting == address { self.connecting = nil }
            if !success { self.connectFailed = address }
        }
    }

    func start() { session.start() }

    #if DEBUG
    func setSampleState(_ sample: DeviceState) { state = sample }
    func setSamplePaired(_ sample: [PairedEarbuds]) { paired = sample }
    #endif

    func stop() {
        resetTimers()
        session.stop()
    }

    func refreshBattery() {
        if state.connected { session.readBattery() }
    }

    // MARK: - Connection

    /// Connects paired earbuds for audio; the control link follows by itself.
    func connect(_ address: String) {
        guard connecting == nil, !state.connected else { return }
        connectFailed = nil
        if classic.connect(address: address) {
            if paired.first(where: { $0.address == address })?.connected != true { connecting = address }
        } else {
            connectFailed = address
        }
    }

    /// Disconnects the earbuds from this Mac, audio included.
    func disconnect() {
        guard state.connected, let address = state.address else { return }
        session.dropLink()
        _ = classic.disconnect(address: address)
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

    /// Renames the earbuds. False if the name isn't valid (empty or too long).
    @discardableResult
    func rename(_ name: String) -> Bool {
        guard let valid = JieliCodec.validName(name) else { return false }
        guard state.connected, caps.rename, !nameConfirm.pending, valid != state.name else { return true }
        session.setName(valid)
        nameConfirm.begin(valid)
        state.name = valid
        state.namePending = true
        return true
    }

    // MARK: - Touch controls

    func setTouchControl(bud: Bud, gesture: Int, function: Int) {
        guard state.connected, caps.touchControls, !touchConfirm.pending else { return }
        let control = TouchControl(bud: bud, gesture: gesture, function: function)
        guard !state.touchControls.contains(control) else { return }
        session.setTouchControl(control)
        touchConfirm.begin([control])
        state.touchControls = state.touchControls.map {
            $0.bud == bud && $0.gesture == gesture ? control : $0
        }
        state.touchPending = true
    }

    // MARK: - Custom EQ

    /// Switches to Custom with the saved gains.
    func selectCustomEq() {
        guard state.connected, !caps.eqBands.isEmpty, !eqConfirm.pending else { return }
        sendCustomEq()
        eqConfirm.begin(CustomEq.id)
        state.eq.preset = CustomEq.id
        state.eq.pending = true
    }

    /// Sets one band (in dB) of the custom EQ, switching to Custom if needed.
    func setCustomGain(band: Int, to gain: Int) {
        guard state.connected, state.eq.customGains.indices.contains(band) else { return }
        let clamped: Int = min(max(gain, CustomEq.range.lowerBound), CustomEq.range.upperBound)
        guard state.eq.customGains[band] != clamped else { return }
        state.eq.customGains[band] = clamped
        saveCustomGains()
        if state.eq.preset != CustomEq.id {
            selectCustomEq()
        } else {
            customEqTimer.schedule(Self.customEqDelay) { [weak self] in self?.sendCustomEq() }
        }
    }

    /// All bands back to 0 dB.
    func resetCustomEq() {
        guard state.connected, !state.eq.customGains.isEmpty else { return }
        state.eq.customGains = Array(repeating: 0, count: state.eq.customGains.count)
        saveCustomGains()
        if state.eq.preset == CustomEq.id { sendCustomEq() }
    }

    private func sendCustomEq() {
        customEqTimer.cancel()
        session.setCustomEq(gains: state.eq.customGains)
    }

    private var customGainsKey: String? { state.address.map { "customEq.\($0)" } }

    private func saveCustomGains() {
        guard let key = customGainsKey else { return }
        UserDefaults.standard.set(state.eq.customGains, forKey: key)
    }

    /// Saved gains for these earbuds, else the earbuds' own Custom slot, else flat.
    private func loadCustomGains(table: [UInt8]?) {
        let bands = caps.eqBands.count
        guard bands > 0, state.eq.customGains.count != bands else { return }
        if let key = customGainsKey, let saved = UserDefaults.standard.array(forKey: key) as? [Int], saved.count == bands {
            state.eq.customGains = saved
        } else if let table, table.count == bands {
            state.eq.customGains = table.map { Int(Int8(bitPattern: $0)) }
        } else {
            state.eq.customGains = Array(repeating: 0, count: bands)
        }
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
        if !info.eqFrequencies.isEmpty { loadCustomGains(table: info.eqGains[CustomEq.id]) }
        // Custom was left on: the earbuds may have dropped the gains, so send ours.
        if state.eq.preset == CustomEq.id, !customEqRestored, !state.eq.customGains.isEmpty {
            customEqRestored = true
            sendCustomEq()
        }
    }

    private func onAdvInfo(_ info: JieliAdvInfo) {
        guard state.connected else { return }
        state.capabilities.learn(from: info)
        if let battery = info.battery { state.battery = battery }
        if let name = info.name, !name.isEmpty, nameConfirm.accept(name) {
            state.name = name
            state.namePending = false
        }
        if let controls = info.touchControls, touchConfirm.accept(controls) {
            state.touchControls = controls
            state.touchPending = false
        }
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
        nameConfirm.reset()
        touchConfirm.reset()
        customEqTimer.cancel()
        customEqRestored = false
    }
}
