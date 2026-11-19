// Protocol self-checks: `swift run AirBudsKitChecks`.
// (XCTest / swift-testing aren't available with only the Command Line Tools.)

import Foundation
import AirBudsKit

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

// Low battery alerts.
func report(left: Int?, right: Int? = nil, charging: Bool = false) -> Battery {
    var b = Battery()
    b.left = left.map { BatteryLevel(level: $0, charging: charging) }
    b.right = right.map { BatteryLevel(level: $0, charging: charging) }
    return b
}
var lowTracker = LowBatteryTracker()
check(lowTracker.update(report(left: 50)).isEmpty, "no alert above 20%")
check(lowTracker.update(report(left: 20)) == [LowBatteryAlert(part: .left, level: 20, threshold: 20)], "alert at 20%")
check(lowTracker.update(report(left: 19)).isEmpty, "no repeat while draining toward 10%")
check(lowTracker.update(report(left: 21)).isEmpty, "small bounce doesn't re-arm")
check(lowTracker.update(report(left: 10)).map(\.threshold) == [10], "second alert at 10%")
check(lowTracker.update(report(left: 4)).isEmpty, "no repeat below 10%")
check(lowTracker.update(report(left: 4, charging: true)).isEmpty, "no alert while charging")
check(lowTracker.update(report(left: 15)).map(\.threshold) == [20], "re-armed after charging")
check(lowTracker.update(report(left: nil, right: 18)).map(\.part) == [.right], "missing bud ignored, other bud alerts")
var connectLow = LowBatteryTracker()
check(connectLow.update(report(left: 8, right: 9)).map(\.threshold) == [10, 10], "connecting already low alerts once per bud at 10%")
var swapped = LowBatteryTracker()
_ = swapped.update(report(left: 9))
check(swapped.update(report(left: 15)).map(\.threshold) == [20], "recovering 5+ points re-arms (15% after 10% alert)")

// Jieli (Hoco): byte strings captured from a HOCO EQ34 Plus ANC.
func bytes(_ s: String) -> [UInt8] { hex(s.replacingOccurrences(of: " ", with: "")) }

check(JieliAuth.respond(to: bytes("fe 74 6c 20 75 42 dd 6a ee 3f f8 42 9f be 13 6a"))
      == bytes("74 83 8c 02 89 00 8d 7e 47 f3 b8 e9 0d da f3 8d"), "jieli handshake response")
check(JieliAuth.respond(to: bytes("ed 07 f3 bc b8 2f 38 4b c6 70 d8 d5 63 25 94 2a"))
      == bytes("e1 6a 9b 32 b6 7f ec b5 7c 10 39 32 90 01 ce be"), "jieli handshake response, second capture")

check(Rcsp.encode(opcode: Rcsp.getSysInfo, sequence: 2, params: [0xFF, 0x00, 0x00, 0x60, 0x10])
      == bytes("fe dc ba c0 07 00 06 02 ff 00 00 60 10 ef"), "rcsp frame")
check(JieliCodec.encodeGetSysInfo() == bytes("ff 00 00 70 10"), "sys info mask: eq, eq presets, noise mode, noise modes")

// Reply to that read, arriving split across two notifications after a stray byte.
let sysReply = bytes("""
    fe dc ba 00 07 00 39 00 0a ff 0c 04 01 00 00 00 00 00 00 00 00 00 00 0a 0d 02 40 00 40 00 39 96 39 96 \
    1d 0e 03 00 00 00 00 00 00 00 00 00 01 40 00 40 00 39 96 39 96 02 40 00 40 00 39 96 39 96 ef
    """)
var rcspParser = RcspParser()
check(rcspParser.push([0x33] + Array(sysReply[0..<20])).isEmpty, "rcsp waits for the rest of a split frame")
let sysFrames = rcspParser.push(Array(sysReply[20...]))
check(sysFrames.count == 1 && sysFrames[0].opcode == Rcsp.getSysInfo && sysFrames[0].status == 0, "rcsp reply parsed")
let sys = JieliCodec.decodeSysInfo(sysFrames.first?.body ?? [])
check(sys.noiseMode == .transparency, "jieli noise mode")
check(sys.eqPreset == 1, "jieli eq preset")
check(Set(sys.noiseModes.keys) == [.off, .anc, .transparency], "jieli noise modes on offer")
check(JieliCodec.encodeSetNoiseMode(.transparency, entry: sys.noiseModes[.transparency])
      == bytes("ff 0a 0d 02 40 00 40 00 39 96 39 96"), "jieli set noise mode")
check(JieliCodec.encodeSetNoiseMode(.off, entry: nil) == bytes("ff 0a 0d 00 00 00 00 00 00 00 00 00"),
      "jieli set noise off without an entry")

// Pushed after a change: flags 0x80 (command), payload [seq, function, attributes].
var pushParser = RcspParser()
let push = pushParser.push(bytes("fe dc ba 80 09 00 0f 05 ff 0c 04 01 00 00 00 00 00 00 00 00 00 00 ef"))
check(push.count == 1 && push[0].isCommand && JieliCodec.decodeSysInfo(push[0].body).eqPreset == 1, "jieli eq update push")

// Preset table: [bands, frequency (u16) × bands, (id, gain × bands) per preset]. Two bands here.
let presets = JieliCodec.decodeSysInfo(bytes("ff 0f 0c 02 00 1f 00 3e 00 00 00 01 fe 02 02 03 01")).eqGains
check(presets[1] == [0xFE, 0x02] && presets.count == 3, "jieli eq preset gains")

let advReply = bytes("""
    fe dc ba 00 c1 00 40 00 05 04 00 64 64 00 13 01 48 4f 43 4f 20 45 51 33 34 20 50 6c 75 73 20 41 4e 43 \
    13 02 01 01 05 02 01 05 01 02 04 02 02 04 01 03 03 02 03 03 05 0a 00 00 00 07 02 05 01 07 06 05 d6 80 c0 e0 0d ef
    """)
var advParser = RcspParser()
let adv = advParser.push(advReply).first.map { JieliCodec.decodeAdvInfo($0.body) }
check(adv?.battery?.left == BatteryLevel(level: 100, charging: false), "jieli left battery")
check(adv?.battery?.right?.level == 100 && adv?.battery?.case == nil, "jieli right battery, case 0 = unknown")
check(adv?.name == "HOCO EQ34 Plus ANC", "jieli name")
check(adv?.lowLatency == false, "jieli work mode normal")
check(JieliCodec.decodeAdvInfo(bytes("04 00 8a 32 00")).battery?.left == BatteryLevel(level: 10, charging: true),
      "jieli charging bit")
check(JieliCodec.encodeSetLowLatency(true) == bytes("02 05 02"), "jieli game mode on")

var hoco = Capabilities()
check(!hoco.noiseControl && !hoco.lowLatency && hoco.eqPresets.isEmpty, "nothing shown before the earbuds report")
hoco.learn(from: sys)
hoco.learn(from: adv ?? JieliAdvInfo())
check(hoco.noiseControl && hoco.transparency, "hoco noise control learned")
check(hoco.lowLatency && hoco.eqPresets.count == 6, "hoco low latency and presets learned")
check(Capabilities.isJieli(deviceName: "HOCO EQ34 Plus ANC") && !Capabilities.isJieli(deviceName: "AirPods Pro"),
      "jieli name match")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
