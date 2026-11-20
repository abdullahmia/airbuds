// Jieli RCSP payloads: encoders for reads and settings, decoders for sys info
// and ADV info replies and pushed updates.

import Foundation

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

    /// Jieli's presets are the standard six, with the same ids (the earbuds also
    /// list unused slots after these).
    public static let eqPresets = EqPreset.standard

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
