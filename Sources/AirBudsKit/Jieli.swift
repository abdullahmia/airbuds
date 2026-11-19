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

// MARK: - Handshake

public enum JieliAuth {
    /// Both sides send [challengeTag, 16 random bytes], answer with
    /// [responseTag, respond(challenge)] and confirm with `pass`.
    public static let challengeTag: UInt8 = 0x00
    public static let responseTag: UInt8 = 0x01
    public static let pass: [UInt8] = [0x02] + Array("pass".utf8)

    /// Bluetooth's E1 function (SAFER+) with Jieli's fixed key and address,
    /// as in Jieli's own SDK (jl_auth).
    public static func respond(to challenge: [UInt8]) -> [UInt8] {
        precondition(challenge.count == 16)
        let key: [UInt8] = [0x06, 0x77, 0x5F, 0x87, 0x91, 0x8D, 0xD4, 0x23,
                            0x00, 0x5D, 0xF1, 0xD8, 0xCF, 0x0C, 0x14, 0x2B]
        let address: [UInt8] = [0x11, 0x22, 0x33, 0x33, 0x22, 0x11]

        let first = SaferPlus.encrypt(key: key, challenge, feedForward: false)
        let offsets: [UInt8] = [233, 229, 223, 193, 179, 167, 149, 131]
        var input = [UInt8](repeating: 0, count: 16)
        var offsetKey = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            let mixed: UInt8 = first[i] ^ challenge[i]
            input[i] = mixed &+ address[i % 6]
            let add: Bool = i < 8 ? i % 2 == 0 : i % 2 == 1
            offsetKey[i] = add ? key[i] &+ offsets[i % 8] : key[i] ^ offsets[i % 8]
        }
        return SaferPlus.encrypt(key: offsetKey, input, feedForward: true)
    }
}

/// SAFER+ as the Bluetooth core spec uses it (Ar, and Ar' with feedForward).
enum SaferPlus {
    /// 45^x mod 257, with 256 stored as 0.
    static let exp: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        var v = 1
        for x in 0..<256 {
            table[x] = UInt8(v & 0xFF)
            v = v * 45 % 257
        }
        return table
    }()
    static let log: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for x in 0..<256 { table[Int(exp[x])] = UInt8(x) }
        return table
    }()
    /// Byte positions that use XOR (the others use addition), and vice versa in the second key layer.
    static let xorPositions: Set<Int> = [0, 3, 4, 7, 8, 11, 12, 15]
    static let shuffle = [8, 11, 12, 15, 2, 1, 6, 5, 10, 9, 14, 13, 0, 7, 4, 3]

    // Written as plain loops with typed locals: CI's compiler times out
    // type-checking the same arithmetic as one map expression.
    static func roundKeys(_ key: [UInt8]) -> [[UInt8]] {
        var k: [UInt8] = key
        k.append(key.reduce(0, ^))
        var keys: [[UInt8]] = [key]
        for p in 2...17 {
            for j in 0..<17 {
                let byte: UInt8 = k[j]
                k[j] = (byte << 3) | (byte >> 5)
            }
            var roundKey = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                let biasIndex: Int = (17 * p + i + 1) & 0xFF
                let bias: UInt8 = exp[Int(exp[biasIndex])]
                roundKey[i] = k[(p - 1 + i) % 17] &+ bias
            }
            keys.append(roundKey)
        }
        return keys
    }

    static func encrypt(key: [UInt8], _ input: [UInt8], feedForward: Bool) -> [UInt8] {
        let keys = roundKeys(key)
        var t = input
        func mix(_ k: [UInt8], xorFirst: Bool) {
            for i in 0..<16 {
                t[i] = xorPositions.contains(i) == xorFirst ? t[i] ^ k[i] : t[i] &+ k[i]
            }
        }
        for round in 0..<8 {
            if round == 2 && feedForward {
                for i in 0..<16 { t[i] = xorPositions.contains(i) ? t[i] ^ input[i] : t[i] &+ input[i] }
            }
            mix(keys[2 * round], xorFirst: true)
            for i in 0..<16 { t[i] = xorPositions.contains(i) ? exp[Int(t[i])] : log[Int(t[i])] }
            mix(keys[2 * round + 1], xorFirst: false)
            for layer in 0..<4 {
                for i in stride(from: 0, to: 16, by: 2) {
                    let (a, b) = (t[i], t[i + 1])
                    t[i] = (a &* 2) &+ b
                    t[i + 1] = a &+ b
                }
                if layer < 3 {
                    let copy = t
                    t = shuffle.map { copy[$0] }
                }
            }
        }
        mix(keys[16], xorFirst: true)
        return t
    }
}

// MARK: - Framing

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

// MARK: - Payloads

/// What a sys info reply or update said. Fields are nil / empty when not included.
public struct JieliSysInfo: Equatable {
    public var noiseMode: NoiseMode?
    /// Noise modes the earbuds offer, each with the entry to send to switch to it.
    public var noiseModes: [NoiseMode: [UInt8]] = [:]
    public var eqPreset: Int?
    /// Preset id -> band gains (signed dB, one byte per band).
    public var eqGains: [Int: [UInt8]] = [:]
    /// Band centre frequencies in Hz, from the preset table.
    public var eqFrequencies: [Int] = []
    public init() {}
}

/// What an ADV info reply said. Fields are nil when not included.
public struct JieliAdvInfo: Equatable {
    public var battery: Battery?
    public var name: String?
    public var lowLatency: Bool?
    /// What each gesture does; nil when not included.
    public var touchControls: [TouchControl]?
    public init() {}
}

public enum JieliCodec {
    // Sys info ("public" function 0xFF) attribute types.
    static let attrEq: UInt8 = 0x04
    static let attrEqPresets: UInt8 = 0x0C
    static let attrNoiseMode: UInt8 = 0x0D
    static let attrNoiseModes: UInt8 = 0x0E
    static let publicFunction: UInt8 = 0xFF
    // ADV info attribute types.
    static let advBattery: UInt8 = 0x00
    static let advName: UInt8 = 0x01
    static let advKeySettings: UInt8 = 0x02
    static let advWorkMode: UInt8 = 0x05

    static let noiseWire: [UInt8: NoiseMode] = [0: .off, 1: .anc, 2: .transparency]
    /// [mode, left max, right max, left gain, right gain] (u16 each): 9 bytes.
    static let noiseEntryLength = 9
    /// Work mode 2 is "game mode"; 1 is normal.
    static let gameMode: UInt8 = 2

    /// Jieli's standard presets (the earbuds also list unused slots after these).
    public static let eqPresets = [
        EqPreset(id: 0, key: "balanced", label: "Normal"),
        EqPreset(id: 1, key: "rock", label: "Rock"),
        EqPreset(id: 2, key: "pop", label: "Pop"),
        EqPreset(id: 3, key: "classical", label: "Classical"),
        EqPreset(id: 4, key: "jazz", label: "Jazz"),
        EqPreset(id: 5, key: "country", label: "Country"),
    ]

    /// Attribute bit mask, big-endian.
    static func mask(_ attributes: [UInt8]) -> [UInt8] {
        var bits: UInt32 = 0
        for type in attributes { bits |= UInt32(1) << UInt32(type) }
        var out: [UInt8] = []
        for shift: UInt32 in [24, 16, 8, 0] {
            out.append(UInt8(truncatingIfNeeded: bits >> shift))
        }
        return out
    }

    /// [length, type, data (length - 1 bytes)] repeated.
    static func attributes(_ p: [UInt8]) -> [(type: UInt8, data: [UInt8])] {
        var out: [(UInt8, [UInt8])] = []
        var i = 0
        while i + 1 < p.count {
            let length = Int(p[i])
            guard length > 0, i + 1 + length <= p.count else { break }
            out.append((p[i + 1], Array(p[(i + 2)..<(i + 1 + length)])))
            i += 1 + length
        }
        return out
    }

    static func attribute(_ type: UInt8, _ data: [UInt8]) -> [UInt8] {
        let length: UInt8 = UInt8(data.count + 1)
        return [length, type] + data
    }

    // MARK: Sys info

    /// Everything the panel uses: EQ, presets, noise mode and the modes on offer.
    public static func encodeGetSysInfo() -> [UInt8] { encodeGetSysInfo([attrEq, attrEqPresets, attrNoiseMode, attrNoiseModes]) }
    public static func encodeGetNoiseMode() -> [UInt8] { encodeGetSysInfo([attrNoiseMode]) }
    public static func encodeGetEq() -> [UInt8] { encodeGetSysInfo([attrEq]) }

    static func encodeGetSysInfo(_ attributes: [UInt8]) -> [UInt8] {
        [publicFunction] + mask(attributes)
    }

    /// body: [function, attributes...] (the same for replies and updates).
    public static func decodeSysInfo(_ body: [UInt8]) -> JieliSysInfo {
        var info = JieliSysInfo()
        for (type, data) in attributes(Array(body.dropFirst())) {
            switch type {
            case attrEq:
                info.eqPreset = data.first.map(Int.init)
            case attrEqPresets:
                // [bands, frequency (u16) × bands, then (id, gain × bands) per preset]
                guard let bands = data.first.map(Int.init), bands > 0, data.count >= 1 + bands * 2 else { continue }
                var frequencies: [Int] = []
                for band in 0..<bands {
                    let high: Int = Int(data[1 + band * 2]) << 8
                    frequencies.append(high | Int(data[2 + band * 2]))
                }
                info.eqFrequencies = frequencies
                var i = 1 + bands * 2
                while i + 1 + bands <= data.count {
                    info.eqGains[Int(data[i])] = Array(data[(i + 1)...(i + bands)])
                    i += 1 + bands
                }
            case attrNoiseMode:
                info.noiseMode = data.first.flatMap { noiseWire[$0] }
            case attrNoiseModes:
                // [count, entry × count]
                var i = 1
                while i + noiseEntryLength <= data.count {
                    let entry = Array(data[i..<(i + noiseEntryLength)])
                    if let mode = noiseWire[entry[0]] { info.noiseModes[mode] = entry }
                    i += noiseEntryLength
                }
            default:
                break
            }
        }
        return info
    }

    /// entry: from JieliSysInfo.noiseModes; without one, the mode with zero gains.
    public static func encodeSetNoiseMode(_ mode: NoiseMode, entry: [UInt8]?) -> [UInt8] {
        let wire: UInt8 = noiseWire.first { $0.value == mode }?.key ?? 0
        var data: [UInt8] = entry ?? []
        if data.count != noiseEntryLength {
            data = [UInt8](repeating: 0, count: noiseEntryLength)
            data[0] = wire
        }
        return [publicFunction] + attribute(attrNoiseMode, data)
    }

    /// Custom EQ (mode 6) with one gain per band, clamped to ±8 dB.
    public static func encodeSetCustomEq(gains: [Int]) -> [UInt8] {
        var data: [UInt8] = [UInt8(CustomEq.id)]
        for gain in gains {
            let clamped: Int = min(max(gain, CustomEq.range.lowerBound), CustomEq.range.upperBound)
            data.append(UInt8(bitPattern: Int8(clamped)))
        }
        return [publicFunction] + attribute(attrEq, data)
    }

    /// gains: from JieliSysInfo.eqGains (10 bands); without them, flat.
    public static func encodeSetEqPreset(_ id: Int, gains: [UInt8]?) -> [UInt8] {
        var data: [UInt8] = [UInt8(id)]
        data.append(contentsOf: gains ?? [UInt8](repeating: 0, count: 10))
        return [publicFunction] + attribute(attrEq, data)
    }

    // MARK: ADV info

    public static func encodeGetAdvInfo() -> [UInt8] { mask([advBattery, advName, advKeySettings, advWorkMode]) }
    public static func encodeGetTouchControls() -> [UInt8] { mask([advKeySettings]) }

    /// Changes one gesture (the way Jieli's app does it: one entry per command).
    public static func encodeSetTouchControl(_ control: TouchControl) -> [UInt8] {
        attribute(advKeySettings, [UInt8(control.bud.rawValue), UInt8(control.gesture), UInt8(control.function & 0xFF)])
    }
    public static func encodeGetBattery() -> [UInt8] { mask([advBattery]) }
    public static func encodeGetLowLatency() -> [UInt8] { mask([advWorkMode]) }
    public static func encodeGetName() -> [UInt8] { mask([advName]) }

    /// The longest name the earbuds take, in UTF-8 bytes (Jieli's app allows 20).
    public static let maxNameBytes = 20

    /// `name` trimmed, or nil if it's empty or too long.
    public static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxNameBytes else { return nil }
        return trimmed
    }

    /// Sets the Bluetooth name (ADV attribute 01). nil if the name isn't valid.
    public static func encodeSetName(_ name: String) -> [UInt8]? {
        guard let valid = validName(name) else { return nil }
        return attribute(advName, Array(valid.utf8))
    }

    public static func decodeAdvInfo(_ body: [UInt8]) -> JieliAdvInfo {
        var info = JieliAdvInfo()
        for (type, data) in attributes(body) {
            switch type {
            case advBattery:
                // [left, right, case]: level | 0x80 while charging; 0 = not available.
                var battery = Battery()
                let level = { (i: Int) -> BatteryLevel? in
                    guard let raw = at(data, i), raw & 0x7F != 0 else { return nil }
                    return BatteryLevel(level: Int(raw & 0x7F), charging: raw & 0x80 != 0)
                }
                battery.left = level(0)
                battery.right = level(1)
                battery.case = level(2)
                info.battery = battery
            case advName:
                info.name = String(decoding: data, as: UTF8.self)
            case advKeySettings:
                // [bud, gesture, function] per entry
                var controls: [TouchControl] = []
                var i = 0
                while i + 3 <= data.count {
                    if let bud = Bud(rawValue: Int(data[i])) {
                        controls.append(TouchControl(bud: bud, gesture: Int(data[i + 1]), function: Int(data[i + 2])))
                    }
                    i += 3
                }
                info.touchControls = controls
            case advWorkMode:
                info.lowLatency = data.first == gameMode
            default:
                break
            }
        }
        return info
    }

    public static func encodeSetLowLatency(_ on: Bool) -> [UInt8] {
        attribute(advWorkMode, [on ? gameMode : 1])
    }
}

// MARK: - Capabilities

extension Capabilities {
    /// Turn on what a Jieli report shows the earbuds support.
    public mutating func learn(from info: JieliSysInfo) {
        if !info.noiseModes.isEmpty {
            noiseControl = info.noiseModes[.anc] != nil
            transparency = info.noiseModes[.transparency] != nil
        }
        if info.eqPreset != nil && eqPresets.isEmpty {
            eqPresets = JieliCodec.eqPresets
        }
        // A table with a Custom slot means custom gains are possible.
        if info.eqGains[CustomEq.id] != nil && !info.eqFrequencies.isEmpty {
            eqBands = info.eqFrequencies
        }
    }

    public mutating func learn(from info: JieliAdvInfo) {
        if info.lowLatency != nil { lowLatency = true }
        if info.name != nil { rename = true }
        if let controls = info.touchControls, !controls.isEmpty { touchControls = true }
    }

    /// Product names that get the Jieli connection.
    public static func isJieli(deviceName name: String) -> Bool {
        name.lowercased().contains("hoco")
    }
}
