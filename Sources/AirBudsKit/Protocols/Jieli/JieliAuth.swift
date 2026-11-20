// Jieli RCSP handshake: the challenge/response both sides pass before the
// earbuds accept commands (E1 over SAFER+). See Rcsp.swift for the protocol.

import Foundation

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
