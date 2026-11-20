// Snapshot of everything the panel shows about the connected earbuds, and how
// the UI names each noise mode.

import Foundation
import AirBudsKit

struct QuickState: Equatable {
    var lowLatency: Bool?
    var lowLatencyPending = false
    var firmware: String?
}

struct EqState: Equatable {
    var preset: Int?
    var pending = false
    /// Gains for Custom (mode 6), one per band in dB. AirBuds keeps them, as
    /// Jieli's app does; the earbuds don't report them back.
    var customGains: [Int] = []
}


struct DeviceState: Equatable {
    var connected = false
    var name: String?
    var namePending = false
    var address: String?
    var battery = Battery()
    var noiseMode: NoiseMode?
    var noisePending = false
    var quick = QuickState()
    var eq = EqState()
    var touchControls: [TouchControl] = []
    var touchPending = false
    var capabilities = Capabilities()
}

extension NoiseMode {
    var label: String {
        switch self {
        case .anc: return "Noise Cancellation"
        case .transparency: return "Transparency"
        case .off: return "Off"
        }
    }

    var symbol: String {
        switch self {
        case .anc: return "person.wave.2.fill"
        case .transparency: return "ear.and.waveform"
        case .off: return "person.fill"
        }
    }
}
