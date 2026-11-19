// The Jieli (Hoco) side of the controller: turns reads and settings into RCSP
// frames and decodes what comes back. Runs on the main thread.

import Foundation
import IOBluetooth
import AirBudsKit

final class JieliSession {
    var onConnected: ((_ name: String, _ address: String, _ firmware: String?) -> Void)?
    var onSysInfo: ((JieliSysInfo) -> Void)?
    var onAdvInfo: ((JieliAdvInfo) -> Void)?
    var onDisconnected: (() -> Void)?

    private let transport = JieliTransport()
    private var parser = RcspParser()
    private var sequence: UInt8 = 0
    /// What to send to switch noise mode / EQ preset, as the earbuds reported it.
    private var noiseEntries: [NoiseMode: [UInt8]] = [:]
    private var eqGains: [Int: [UInt8]] = [:]

    var isConnected: Bool { transport.isConnected }

    init() {
        transport.onConnected = { [unowned self] name, address in
            parser.reset()
            noiseEntries = [:]
            eqGains = [:]
            onConnected?(name, address, Self.firmware(address: address))
        }
        transport.onData = { [unowned self] bytes in
            for frame in parser.push(bytes) { handle(frame) }
        }
        transport.onDisconnected = { [unowned self] in onDisconnected?() }
    }

    func start() { transport.start() }
    func stop() { transport.stop() }

    // MARK: Reads

    func readAll() {
        send(Rcsp.getSysInfo, JieliCodec.encodeGetSysInfo())
        send(Rcsp.getAdvInfo, JieliCodec.encodeGetAdvInfo())
    }

    func readBattery() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetBattery()) }
    func readNoiseMode() { send(Rcsp.getSysInfo, JieliCodec.encodeGetNoiseMode()) }
    func readEq() { send(Rcsp.getSysInfo, JieliCodec.encodeGetEq()) }
    func readLowLatency() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetLowLatency()) }

    // MARK: Settings

    func setNoiseMode(_ mode: NoiseMode) {
        send(Rcsp.setSysInfo, JieliCodec.encodeSetNoiseMode(mode, entry: noiseEntries[mode]))
    }

    func setEqPreset(_ id: Int) {
        send(Rcsp.setSysInfo, JieliCodec.encodeSetEqPreset(id, gains: eqGains[id]))
    }

    func setLowLatency(_ on: Bool) {
        send(Rcsp.setAdvInfo, JieliCodec.encodeSetLowLatency(on))
    }

    // MARK: Frames

    private func send(_ opcode: UInt8, _ params: [UInt8]) {
        sequence &+= 1
        transport.write(Rcsp.encode(opcode: opcode, sequence: sequence, params: params))
    }

    private func handle(_ frame: RcspFrame) {
        if let status = frame.status, status != 0 {
            Log.info(String(format: "RCSP 0x%02X failed with status %d", frame.opcode, status))
            return
        }
        switch (frame.isCommand, frame.opcode) {
        case (false, Rcsp.getSysInfo), (true, Rcsp.sysInfoChanged):
            let info = JieliCodec.decodeSysInfo(frame.body)
            noiseEntries.merge(info.noiseModes) { $1 }
            eqGains.merge(info.eqGains) { $1 }
            onSysInfo?(info)
        case (false, Rcsp.getAdvInfo):
            onAdvInfo?(JieliCodec.decodeAdvInfo(frame.body))
        case (true, Rcsp.advChanged):
            readBattery() // the status beacon changed; battery is the part we show
        default:
            break
        }
    }

    /// Firmware version from the classic device's PnP (Device ID) record: 0xJJMN -> "J.M.N".
    private static func firmware(address: String) -> String? {
        guard let device = IOBluetoothDevice(addressString: address),
              let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1200)),
              let version = record.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue,
              version > 0 else { return nil }
        return "\(version >> 8).\((version >> 4) & 0xF).\(version & 0xF)"
    }
}
