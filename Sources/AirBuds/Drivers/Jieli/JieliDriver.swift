// The Jieli (Hoco) driver: turns reads and settings into RCSP frames and
// decodes what comes back into EarbudsReport. Runs on the main thread.

import Foundation
import IOBluetooth
import AirBudsKit

final class JieliDriver: EarbudsDriver {
    var onConnected: ((_ name: String, _ address: String, _ firmware: String?) -> Void)?
    var onReport: ((_ report: EarbudsReport, _ capabilities: Capabilities) -> Void)?
    var onDisconnected: (() -> Void)?
    var onPairedChanged: (([PairedEarbuds]) -> Void)?

    private let transport = JieliTransport()
    private var parser = RcspParser()
    private var sequence: UInt8 = 0
    /// What to send to switch noise mode / EQ preset, as the earbuds reported it.
    private var noiseEntries: [NoiseMode: [UInt8]] = [:]
    private var eqGains: [Int: [UInt8]] = [:]
    /// Learned from the replies since connecting.
    private var capabilities = Capabilities()

    init() {
        transport.onConnected = { [unowned self] name, address in
            parser.reset()
            noiseEntries = [:]
            eqGains = [:]
            capabilities = Capabilities()
            onConnected?(name, address, Self.firmware(address: address))
            #if DEBUG
            sendDebugCommands()
            #endif
        }
        transport.onData = { [unowned self] bytes in
            for frame in parser.push(bytes) { handle(frame) }
        }
        transport.onDisconnected = { [unowned self] in onDisconnected?() }
        transport.onPairedChanged = { [unowned self] devices in onPairedChanged?(devices) }
    }

    func start() { transport.start() }
    func stop() { transport.stop() }
    func dropLink() { transport.dropLink() }

    // MARK: Reads

    func readAll() {
        send(Rcsp.getSysInfo, JieliCodec.encodeGetSysInfo())
        send(Rcsp.getAdvInfo, JieliCodec.encodeGetAdvInfo())
    }

    func readBattery() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetBattery()) }
    func readNoiseMode() { send(Rcsp.getSysInfo, JieliCodec.encodeGetNoiseMode()) }
    func readEq() { send(Rcsp.getSysInfo, JieliCodec.encodeGetEq()) }
    func readLowLatency() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetLowLatency()) }
    func readName() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetName()) }
    func readTouchControls() { send(Rcsp.getAdvInfo, JieliCodec.encodeGetTouchControls()) }

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

    func setTouchControl(_ control: TouchControl) {
        send(Rcsp.setAdvInfo, JieliCodec.encodeSetTouchControl(control))
    }

    func setCustomEq(gains: [Int]) {
        send(Rcsp.setSysInfo, JieliCodec.encodeSetCustomEq(gains: gains))
    }

    func setName(_ name: String) {
        guard let params = JieliCodec.encodeSetName(name) else { return }
        send(Rcsp.setAdvInfo, params)
    }

    // MARK: Frames

    private func send(_ opcode: UInt8, _ params: [UInt8]) {
        sequence &+= 1
        transport.write(Rcsp.encode(opcode: opcode, sequence: sequence, params: params))
    }

    private func handle(_ frame: RcspFrame) {
        Log.trace(String(format: "RCSP %@ 0x%02X", frame.isCommand ? "push" : "reply", frame.opcode)
                  + (frame.status.map { " status \($0)" } ?? "")
                  + " body " + frame.body.map { String(format: "%02x", $0) }.joined(separator: " "))
        if let status = frame.status, status != 0 {
            Log.info(String(format: "RCSP 0x%02X failed with status %d", frame.opcode, status))
            return
        }
        switch (frame.isCommand, frame.opcode) {
        case (false, Rcsp.getSysInfo), (true, Rcsp.sysInfoChanged):
            let info = JieliCodec.decodeSysInfo(frame.body)
            noiseEntries.merge(info.noiseModes) { $1 }
            eqGains.merge(info.eqGains) { $1 }
            capabilities.learn(from: info)
            onReport?(info.report, capabilities)
        case (false, Rcsp.getAdvInfo):
            let info = JieliCodec.decodeAdvInfo(frame.body)
            capabilities.learn(from: info)
            onReport?(info.report, capabilities)
        case (true, Rcsp.advChanged):
            readBattery() // the status beacon changed; battery is the part we show
        case (true, Rcsp.advRequest):
            // e.g. 03: "reconnect". Seen after some settings changes; nothing to do here.
            Log.trace("The earbuds requested operation \(frame.body.first ?? 0)")
        case (false, Rcsp.setAdvInfo):
            // [result]: 0 = accepted. The read-back that follows each change confirms it.
            if let result = frame.body.first, result != 0 {
                Log.info("The earbuds refused a setting (result \(result))")
            }
        default:
            break
        }
    }

    #if DEBUG
    /// For reverse engineering: `AIRBUDS_SEND="c1 ffffffff; 07 ff ffffffff"` sends
    /// each raw command (opcode, then parameters, in hex) a second apart after
    /// connecting. Run with AIRBUDS_DEBUG=1 to see the replies.
    private func sendDebugCommands() {
        guard let script = ProcessInfo.processInfo.environment["AIRBUDS_SEND"] else { return }
        let commands: [[UInt8]] = script.split(separator: ";").map { command in
            let digits = command.filter { $0.isHexDigit }
            return stride(from: 0, to: digits.count - 1, by: 2).compactMap { i -> UInt8? in
                let start = digits.index(digits.startIndex, offsetBy: i)
                return UInt8(digits[start...digits.index(after: start)], radix: 16)
            }
        }
        for (i, bytes) in commands.enumerated() where !bytes.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i)) { [weak self] in
                Log.info("AIRBUDS_SEND " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
                self?.send(bytes[0], Array(bytes.dropFirst()))
            }
        }
    }
    #endif

    /// Firmware version from the classic device's PnP (Device ID) record: 0xJJMN -> "J.M.N".
    private static func firmware(address: String) -> String? {
        guard let device = IOBluetoothDevice(addressString: address),
              let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1200)),
              let version = record.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue,
              version > 0 else { return nil }
        let major: Int = version >> 8
        let minor: Int = (version >> 4) & 0xF
        let patch: Int = version & 0xF
        return "\(major).\(minor).\(patch)"
    }
}
