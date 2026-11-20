// Console logging. AIRBUDS_DEBUG=1 also logs every frame to and from the earbuds.

import Foundation

enum Log {
    static let debug = ProcessInfo.processInfo.environment["AIRBUDS_DEBUG"] != nil

    static func info(_ message: String) { NSLog("[AirBuds] %@", message) }

    /// Connection details, only with AIRBUDS_DEBUG=1.
    static func trace(_ message: @autoclosure () -> String) {
        if debug { info(message()) }
    }

    static func frame(_ direction: String, _ bytes: [UInt8]) {
        guard debug else { return }
        info("\(direction) \(bytes.map { String(format: "%02x", $0) }.joined())")
    }
}
