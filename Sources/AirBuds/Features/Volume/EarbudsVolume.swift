// The connected earbuds' output volume and mute, through CoreAudio. The
// earbuds play audio over classic Bluetooth, so macOS lists them as an output
// device and passes volume changes on to them. This works whether or not
// they're the Mac's current output.
//
// Follows the device as it comes and goes (the audio side can appear a moment
// after the control link) and changes made elsewhere, e.g. the volume keys.

import AirBudsKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation

final class EarbudsVolume: ObservableObject {
    private struct Earbuds: Equatable {
        let address: String
        let name: String?
    }

    /// 0...1, or nil while the earbuds aren't an audio output.
    @Published private(set) var level: Double?
    @Published private(set) var muted = false

    private var device: AudioObjectID?
    private var earbuds: Earbuds?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var cancellables = Set<AnyCancellable>()

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// `live: false` doesn't touch CoreAudio (for snapshots).
    init(controller: EarbudsController, live: Bool = true) {
        guard live else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.findDevice() }
        devicesListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, listener)
        controller.$state
            .map { state in state.connected ? state.address.map { Earbuds(address: $0, name: state.name) } : nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] earbuds in
                self?.earbuds = earbuds
                self?.findDevice()
            }
            .store(in: &cancellables)
    }

    deinit {
        watch(nil)
        if let listener = devicesListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, listener)
        }
    }

    func setLevel(_ value: Double) {
        guard let device else { return }
        var volume = Float32(min(max(value, 0), 1))
        let status = AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        if status != noErr { Log.info("Could not set the earbuds' volume (error \(status))") }
        level = Double(volume)
        if muted, volume > 0 { setMuted(false) }
    }

    func setMuted(_ on: Bool) {
        guard let device, Self.settable(device, &Self.muteAddress) else { return }
        var value: UInt32 = on ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status != noErr { Log.info("Could not mute the earbuds (error \(status))") }
        muted = on
    }

    #if DEBUG
    func setSample(level: Double, muted: Bool = false) {
        self.level = level
        self.muted = muted
    }
    #endif

    // MARK: - Device

    /// Picks the earbuds' output device, if there is one with a settable volume.
    private func findDevice() {
        let found: AudioObjectID? = earbuds.flatMap { earbuds in
            let outputs = Self.allDevices().filter { Self.settable($0, &Self.volumeAddress) }
            return outputs.first { Self.uid($0).map { AudioOutput.isEarbuds(uid: $0, address: earbuds.address) } ?? false }
                // Fallback: a Bluetooth output with the earbuds' name.
                ?? outputs.first { Self.isBluetooth($0) && earbuds.name != nil && Self.name($0) == earbuds.name }
        }
        guard found != device else { return }
        watch(found)
        if let found { Log.trace("Earbuds audio output: \(Self.uid(found) ?? "\(found)")") }
    }

    private func watch(_ new: AudioObjectID?) {
        if let device, let listener = deviceListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        }
        device = new
        deviceListener = nil
        if let new {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
            deviceListener = listener
            AudioObjectAddPropertyListenerBlock(new, &Self.volumeAddress, .main, listener)
            AudioObjectAddPropertyListenerBlock(new, &Self.muteAddress, .main, listener)
        }
        read()
    }

    private func read() {
        guard let device else {
            level = nil
            muted = false
            return
        }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &volume) == noErr {
            level = Double(volume)
        }
        var mute: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        muted = AudioObjectHasProperty(device, &Self.muteAddress)
            && AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &mute) == noErr
            && mute != 0
    }

    // MARK: - CoreAudio helpers

    private static func allDevices() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func settable(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func uid(_ device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func name(_ device: AudioObjectID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
