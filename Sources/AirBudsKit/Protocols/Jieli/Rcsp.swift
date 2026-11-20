// Jieli RCSP: the control protocol of earbuds built on Zhuhai Jieli chips
// (Bluetooth company id 0x05D6), such as Hoco. It runs over BLE: service AE00,
// commands written to AE01, replies and updates notified on AE02.
//
// A session starts with a challenge/response handshake on the raw channel; until
// it passes, the earbuds ignore every command. After that, frames look like:
//   FE DC BA  flags  opcode  length (u16 BE)  payload  EF
// flags bit 7 marks a command (clear = reply), bit 6 asks for a reply. A
// command's payload starts with a sequence number, a reply's with [status, seq].
//
// Verified against a HOCO EQ34 Plus ANC (firmware 2.4.0).

import Foundation

public enum Rcsp {
    public static let getSysInfo: UInt8 = 0x07
    public static let setSysInfo: UInt8 = 0x08
    /// Pushed by the earbuds when a sys info value changes (e.g. from a button).
    public static let sysInfoChanged: UInt8 = 0x09
    public static let setAdvInfo: UInt8 = 0xC0
    public static let getAdvInfo: UInt8 = 0xC1
    /// Pushed by the earbuds with their status beacon (battery among it).
    public static let advChanged: UInt8 = 0xC2
    /// The earbuds ask the app to do something, e.g. 03 = reconnect.
    public static let advRequest: UInt8 = 0xC4

    static let header: [UInt8] = [0xFE, 0xDC, 0xBA]
    static let trailer: UInt8 = 0xEF

    /// A command that wants a reply.
    public static func encode(opcode: UInt8, sequence: UInt8, params: [UInt8]) -> [UInt8] {
        let length: Int = params.count + 1
        var frame: [UInt8] = header
        frame.append(0xC0)
        frame.append(opcode)
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xFF))
        frame.append(sequence)
        frame.append(contentsOf: params)
        frame.append(trailer)
        return frame
    }
}

public struct RcspFrame: Equatable {
    public var isCommand: Bool
    public var opcode: UInt8
    public var payload: [UInt8]

    /// A reply's status byte (0 = OK); nil for commands.
    public var status: UInt8? { isCommand ? nil : payload.first }

    /// The payload after the status / sequence bytes.
    public var body: [UInt8] { Array(payload.dropFirst(isCommand ? 1 : 2)) }
}

/// Reassembles frames from BLE notifications (one frame can span several).
public struct RcspParser {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func reset() { buffer.removeAll() }

    public mutating func push(_ bytes: [UInt8]) -> [RcspFrame] {
        buffer += bytes
        var frames: [RcspFrame] = []
        while true {
            guard let start = headerIndex() else {
                buffer = Array(buffer.suffix(2)) // could be the start of a header
                return frames
            }
            buffer.removeFirst(start)
            guard buffer.count >= 7 else { return frames }
            let high: Int = Int(buffer[5]) << 8
            let length: Int = high | Int(buffer[6])
            let total: Int = 7 + length + 1
            guard buffer.count >= total else { return frames }
            if buffer[total - 1] == Rcsp.trailer {
                frames.append(RcspFrame(isCommand: buffer[3] & 0x80 != 0, opcode: buffer[4],
                                        payload: Array(buffer[7..<(7 + length)])))
                buffer.removeFirst(total)
            } else {
                buffer.removeFirst() // false start: resync
            }
        }
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 3 else { return nil }
        for i in 0...(buffer.count - 3) where Array(buffer[i..<(i + 3)]) == Rcsp.header {
            return i
        }
        return nil
    }
}
