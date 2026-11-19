// Snapshot of everything the panel shows about the connected earbuds.

import AirBudsKit

struct QuickState: Equatable {
    var lowLatency: Bool?
    var lowLatencyPending = false
    var firmware: String?
}

struct EqState: Equatable {
    var preset: Int?
    var pending = false
}

struct DeviceState: Equatable {
    var connected = false
    var name: String?
    var address: String?
    var battery = Battery()
    var noiseMode: NoiseMode?
    var noisePending = false
    var quick = QuickState()
    var eq = EqState()
    var capabilities = Capabilities()
}
