// BLE transport for Jieli-based earbuds (Hoco): finds the BLE side of a connected,
// paired classic device, opens the RCSP service, passes the handshake and then
// relays raw bytes. Framing and payloads live in AirBudsKit/Jieli.swift.
//
// It only scans while a supported device is connected for audio, so there's no
// BLE scanning the rest of the time. CoreBluetooth calls back on the main queue.

import CoreBluetooth
import Foundation
import IOBluetooth
import AirBudsKit

final class JieliTransport: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onConnected: ((_ name: String, _ address: String) -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onDisconnected: (() -> Void)?

    private static let service = CBUUID(string: "AE00")
    private static let writeCharacteristic = CBUUID(string: "AE01")
    private static let notifyCharacteristic = CBUUID(string: "AE02")
    /// Bluetooth company id 0x05D6 (Zhuhai Jieli) as it leads manufacturer data.
    private static let jieliCompany: [UInt8] = [0xD6, 0x05]
    private static let checkInterval: TimeInterval = 3
    private static let connectTimeout: TimeInterval = 10
    /// Some firmware never sends the final "pass"; the link works anyway.
    private static let passWait: TimeInterval = 1.5
    private static let maxAttempts = 3

    private struct Target {
        let name: String
        let address: String
        let addressBytes: [UInt8]
    }

    private enum Phase {
        case idle
        case connecting(since: Date)
        case authenticating(challenge: [UInt8])
        case ready
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var target: Target?
    private var phase = Phase.idle
    private var checkTimer: Timer?
    private let passTimer = Delayed()
    /// Failed attempts per classic address; reset when that device disconnects.
    private var attempts: [String: Int] = [:]
    private var stopped = true

    var isConnected: Bool { if case .ready = phase { return true } else { return false } }

    func start() {
        guard stopped else { return }
        stopped = false
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) }
        check()
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        stopped = true
        checkTimer?.invalidate()
        checkTimer = nil
        central?.stopScan()
        disconnect()
    }

    func write(_ bytes: [UInt8]) {
        guard isConnected else { return }
        send(bytes)
    }

    // MARK: Finding the earbuds

    /// Scan only while a supported classic device is connected and we aren't.
    private func check() {
        guard !stopped, let central, central.state == .poweredOn else { return }
        if case .connecting(let since) = phase, Date().timeIntervalSince(since) > Self.connectTimeout {
            Log.info("BLE connection to \(target?.name ?? "earbuds") timed out")
            fail()
        }
        let candidates = connectedTargets()
        attempts = attempts.filter { address, _ in candidates.contains { $0.address == address } }
        guard case .idle = phase else { return }

        if candidates.contains(where: { (attempts[$0.address] ?? 0) < Self.maxAttempts }) {
            if !central.isScanning { central.scanForPeripherals(withServices: nil) }
        } else if central.isScanning {
            central.stopScan()
        }
    }

    private func connectedTargets() -> [Target] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.compactMap { device in
            guard device.isConnected(), let name = device.name, Capabilities.isJieli(deviceName: name),
                  let address = device.addressString else { return nil }
            let bytes = address.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { UInt8($0, radix: 16) }
            return Target(name: name, address: address, addressBytes: bytes)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            check()
        } else if peripheral != nil {
            disconnect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard case .idle = phase,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.starts(with: Self.jieliCompany) else { return }
        // The beacon carries the classic address; fall back to the advertised name.
        let beacon = [UInt8](data)
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let match = connectedTargets().first { (t: Target) -> Bool in
            guard (attempts[t.address] ?? 0) < Self.maxAttempts else { return false }
            if localName == t.name { return true }
            guard t.addressBytes.count == 6 else { return false }
            return contains(beacon, t.addressBytes) || contains(beacon, Array(t.addressBytes.reversed()))
        }
        guard let match else { return }

        central.stopScan()
        target = match
        self.peripheral = peripheral
        peripheral.delegate = self
        phase = .connecting(since: Date())
        central.connect(peripheral)
    }

    private func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    // MARK: Opening the service

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.info("BLE connection failed: \(error?.localizedDescription ?? "unknown error")")
        fail()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            Log.info("\(target?.name ?? "Earbuds") have no Jieli control service")
            return fail()
        }
        peripheral.discoverCharacteristics([Self.writeCharacteristic, Self.notifyCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        writer = characteristics.first { $0.uuid == Self.writeCharacteristic }
        guard writer != nil, let notify = characteristics.first(where: { $0.uuid == Self.notifyCharacteristic }) else {
            return fail()
        }
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, characteristic.isNotifying else { return fail() }
        let challenge = (0..<16).map { _ in UInt8.random(in: 0...255) }
        phase = .authenticating(challenge: challenge)
        send([JieliAuth.challengeTag] + challenge)
    }

    // MARK: Handshake and data

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, let value = characteristic.value, !value.isEmpty else { return }
        let bytes = [UInt8](value)
        Log.frame("<-", bytes)
        switch phase {
        case .ready:
            onData?(bytes)
        case .authenticating(let challenge):
            authenticate(bytes, challenge: challenge)
        default:
            break
        }
    }

    private func authenticate(_ bytes: [UInt8], challenge: [UInt8]) {
        if bytes.count == 17 && bytes[0] == JieliAuth.responseTag {
            // The earbuds answered our challenge.
            guard Array(bytes[1...]) == JieliAuth.respond(to: challenge) else {
                Log.info("\(target?.name ?? "Earbuds") failed the handshake")
                return fail()
            }
            send(JieliAuth.pass)
        } else if bytes.count == 17 && bytes[0] == JieliAuth.challengeTag {
            // Their challenge to us.
            send([JieliAuth.responseTag] + JieliAuth.respond(to: Array(bytes[1...])))
            passTimer.schedule(Self.passWait) { [weak self] in self?.authenticated() }
        } else if bytes == JieliAuth.pass {
            authenticated()
        }
    }

    private func authenticated() {
        guard case .authenticating = phase, let target else { return }
        passTimer.cancel()
        phase = .ready
        attempts[target.address] = 0
        Log.info("Connected to \(target.name) over BLE")
        onConnected?(target.name, target.address)
    }

    private func send(_ bytes: [UInt8]) {
        guard let peripheral, let writer else { return }
        Log.frame("->", bytes)
        let chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
        for start in stride(from: 0, to: bytes.count, by: chunk) {
            let piece = Data(bytes[start..<min(start + chunk, bytes.count)])
            peripheral.writeValue(piece, for: writer, type: .withoutResponse)
        }
    }

    // MARK: Teardown

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        let wasReady = isConnected
        reset()
        Log.info("BLE link closed")
        if wasReady { onDisconnected?() }
    }

    private func fail() {
        if let address = target?.address { attempts[address, default: 0] += 1 }
        disconnect()
    }

    private func disconnect() {
        let wasReady = isConnected
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        reset()
        if wasReady { onDisconnected?() }
    }

    private func reset() {
        passTimer.cancel()
        peripheral?.delegate = nil
        peripheral = nil
        writer = nil
        target = nil
        phase = .idle
    }
}
