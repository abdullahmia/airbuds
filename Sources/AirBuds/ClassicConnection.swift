// Connects and disconnects paired earbuds for audio (classic Bluetooth), like
// clicking Connect in System Settings → Bluetooth. Once they're connected,
// JieliTransport finds them and opens the control link as usual.

import Foundation
import IOBluetooth

final class ClassicConnection: NSObject {
    /// Called on the main thread when a connection attempt finishes.
    var onFinished: ((_ address: String, _ success: Bool) -> Void)?

    /// Devices with an attempt in flight (IOBluetooth doesn't retain them).
    private var connecting: [IOBluetoothDevice] = []

    /// Starts connecting; false if it couldn't even start.
    func connect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() {
            onFinished?(address, true)
            return true
        }
        let status = device.openConnection(self)
        guard status == kIOReturnSuccess else {
            Log.info("Could not start connecting to \(device.name ?? address) (error \(status))")
            return false
        }
        connecting.append(device)
        return true
    }

    /// IOBluetoothDevice's asynchronous openConnection callback.
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        connecting.removeAll { $0 === device }
        let address = device?.addressString?.lowercased() ?? ""
        if status != kIOReturnSuccess {
            Log.info("Connecting to \(device?.name ?? address) failed (error \(status))")
        }
        onFinished?(address, status == kIOReturnSuccess)
    }

    func disconnect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address), device.isConnected() else { return false }
        let status = device.closeConnection()
        if status != kIOReturnSuccess {
            Log.info("Disconnecting \(device.name ?? address) failed (error \(status))")
        }
        return status == kIOReturnSuccess
    }
}
