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
        let input = (0..<16).map { (first[$0] ^ challenge[$0]) &+ address[$0 % 6] }
        let offsets: [UInt8] = [233, 229, 223, 193, 179, 167, 149, 131]
        let offsetKey = (0..<16).map { i -> UInt8 in
            let add = i < 8 ? i % 2 == 0 : i % 2 == 1
            return add ? key[i] &+ offsets[i % 8] : key[i] ^ offsets[i % 8]
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

    static func roundKeys(_ key: [UInt8]) -> [[UInt8]] {
        var k = key + [key.reduce(0, ^)]
        var keys = [key]
        for p in 2...17 {
            k = k.map { ($0 << 3) | ($0 >> 5) }
            keys.append((0..<16).map { i in k[(p - 1 + i) % 17] &+ exp[Int(exp[(17 * p + i + 1) & 0xFF])] })
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

    static let header: [UInt8] = [0xFE, 0xDC, 0xBA]
    static let trailer: UInt8 = 0xEF

    /// A command that wants a reply.
    public static func encode(opcode: UInt8, sequence: UInt8, params: [UInt8]) -> [UInt8] {
        let length = params.count + 1
        return header + [0xC0, opcode, UInt8(length >> 8), UInt8(length & 0xFF), sequence] + params + [trailer]
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
            let length = Int(buffer[5]) << 8 | Int(buffer[6])
            let total = 7 + length + 1
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
        return (0...(buffer.count - 3)).first { buffer[$0] == 0xFE && buffer[$0 + 1] == 0xDC && buffer[$0 + 2] == 0xBA }
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
    public init() {}
}

/// What an ADV info reply said. Fields are nil when not included.
public struct JieliAdvInfo: Equatable {
    public var battery: Battery?
    public var name: String?
    public var lowLatency: Bool?
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
        let bits = attributes.reduce(UInt32(0)) { $0 | 1 << UInt32($1) }
        return [UInt8(bits >> 24), UInt8((bits >> 16) & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8(bits & 0xFF)]
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
        [UInt8(data.count + 1), type] + data
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
                guard let bands = data.first.map(Int.init), bands > 0 else { continue }
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
        let wire = noiseWire.first { $0.value == mode }?.key ?? 0
        var data = entry ?? []
        if data.count != noiseEntryLength { data = [wire] + [UInt8](repeating: 0, count: noiseEntryLength - 1) }
        return [publicFunction] + attribute(attrNoiseMode, data)
    }

    /// gains: from JieliSysInfo.eqGains (10 bands); without them, flat.
    public static func encodeSetEqPreset(_ id: Int, gains: [UInt8]?) -> [UInt8] {
        [publicFunction] + attribute(attrEq, [UInt8(id)] + (gains ?? [UInt8](repeating: 0, count: 10)))
    }

    // MARK: ADV info

    public static func encodeGetAdvInfo() -> [UInt8] { mask([advBattery, advName, advWorkMode]) }
    public static func encodeGetBattery() -> [UInt8] { mask([advBattery]) }
    public static func encodeGetLowLatency() -> [UInt8] { mask([advWorkMode]) }

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
    }

    public mutating func learn(from info: JieliAdvInfo) {
        if info.lowLatency != nil { lowLatency = true }
    }

    /// Product names that get the Jieli connection.
    public static func isJieli(deviceName name: String) -> Bool {
        name.lowercased().contains("hoco")
    }
}
