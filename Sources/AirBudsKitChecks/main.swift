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

// Fully charged alerts.
func charge(left: Int?, charging: Bool, case caseLevel: Int? = nil, caseCharging: Bool = false) -> Battery {
    var b = Battery()
    b.left = left.map { BatteryLevel(level: $0, charging: charging) }
    b.case = caseLevel.map { BatteryLevel(level: $0, charging: caseCharging) }
    return b
}
var full = FullChargeTracker()
check(full.update(charge(left: 100, charging: true)).isEmpty, "already full on connect: no alert")
check(full.update(charge(left: 80, charging: true)).isEmpty, "charging below 100%: no alert yet")
check(full.update(charge(left: 100, charging: true)) == [.left], "alert on reaching 100%")
check(full.update(charge(left: 100, charging: true)).isEmpty, "no repeat while it stays full")
check(full.update(charge(left: 90, charging: true)).isEmpty && full.update(charge(left: 100, charging: false)) == [.left],
      "full counts even when the charging flag clears at 100%")
check(full.update(charge(left: 90, charging: true)).isEmpty && full.update(charge(left: 92, charging: false)).isEmpty
      && full.update(charge(left: 100, charging: false)).isEmpty, "charging stopped short of 100% disarms")
check(full.update(charge(left: nil, charging: false, case: 70, caseCharging: true)).isEmpty
      && full.update(charge(left: nil, charging: false, case: 100, caseCharging: true)) == [.case], "case alerts too")

// Battery history and time left.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
func buds(_ left: Int?, _ right: Int? = nil, charging: Bool = false) -> Battery {
    var b = Battery()
    b.left = left.map { BatteryLevel(level: $0, charging: charging) }
    b.right = right.map { BatteryLevel(level: $0, charging: charging) }
    return b
}
var history = BatteryHistory()
check(history.record(buds(100, 100), at: at(0)), "first sample stored")
check(!history.record(buds(100, 100), at: at(1)), "unchanged reading not stored")
check(history.record(buds(100, 100), at: at(6)), "heartbeat after 5 minutes")
check(!history.record(Battery(), at: at(7)), "empty reading ignored")
// Polled every minute; left drains 10% every 20 minutes from minute 10.
for minute in 7...50 {
    let level = minute < 10 ? 100 : minute < 30 ? 90 : minute < 50 ? 80 : 70
    history.record(buds(level, 100), at: at(Double(minute)))
}
check(history.timeRemaining(.right, now: at(51)) == nil, "no estimate without drops")
let leftLeft = history.timeRemaining(.left, now: at(55))
check(leftLeft.map { abs($0 - 135 * 60) < 1 } == true, "left: 70% at 10%/20 min, 5 min after the drop -> 135 min")
check(history.timeRemaining(.left, now: at(64)) != nil, "estimate holds within the session gap")
var overdueHistory = history
for minute in 51...90 { overdueHistory.record(buds(70, 100), at: at(Double(minute))) }
let overdue = overdueHistory.timeRemaining(.left, now: at(90))
check(overdue.map { $0 > 100 * 60 } == true, "overdue drop: slower rate, so more than the naive 100 min left")
check(history.timeRemaining(.left, now: at(200)) == nil, "no estimate once the session is over")
var onePoint = BatteryHistory()
onePoint.record(buds(100), at: at(0))
onePoint.record(buds(90), at: at(20))
check(onePoint.timeRemaining(.left, now: at(21)) == nil, "one drop isn't enough")
var charged = history
charged.record(buds(80, 100, charging: true), at: at(52))
check(charged.timeRemaining(.left, now: at(53)) == nil, "no estimate while charging")
var later = history
later.record(buds(100, 100), at: at(120))
check(later.session().count == 1, "a gap over 15 minutes starts a new session")
var old = BatteryHistory()
old.record(buds(50), at: at(0))
old.record(buds(40), at: at(8 * 24 * 60))
check(old.samples.count == 1, "samples older than a week are dropped")

// Noise mode cycling.
check(NoiseMode.next(after: .anc, transparency: true) == .transparency, "nc -> transparency")
check(NoiseMode.next(after: .transparency, transparency: true) == .off, "transparency -> off")
check(NoiseMode.next(after: .off, transparency: true) == .anc, "off -> nc")
check(NoiseMode.next(after: .anc, transparency: false) == .off, "nc -> off without transparency")
check(NoiseMode.next(after: nil, transparency: true) == .anc, "unknown -> nc")

// airbuds:// commands.
func command(_ s: String) -> AirBudsCommand? { URL(string: s).flatMap(AirBudsCommand.init(url:)) }
check(command("airbuds://noise/anc") == .noise(.anc), "url: noise cancellation")
check(command("AirBuds://Noise/Transparency") == .noise(.transparency), "url: case-insensitive")
check(command("airbuds://noise/off") == .noise(.off), "url: off")
check(command("airbuds://noise/next") == .nextNoise, "url: cycle")
check(command("airbuds://eq/Rock") == .eq("rock"), "url: eq")
check(command("airbuds://low-latency/on") == .lowLatency(true), "url: low latency on")
check(command("airbuds://low-latency/toggle") == .lowLatency(nil), "url: low latency toggle")
check(command("airbuds://open") == .open, "url: open")
check(command("airbuds://connect") == .connect && command("airbuds://disconnect") == .disconnect, "url: connect, disconnect")
check(command("airbuds://noise/loud") == nil && command("https://noise/anc") == nil, "url: unknown ignored")
check(AirBudsCommand.preset(named: "normal", in: JieliCodec.eqPresets)?.id == 0, "eq by label")
check(AirBudsCommand.preset(named: "3", in: JieliCodec.eqPresets)?.key == "classical", "eq by number")
check(AirBudsCommand.preset(named: "dubstep", in: JieliCodec.eqPresets) == nil, "unknown eq")

// Per-app automation.
let zoom = AutomationRule(bundleID: "us.zoom.xos", appName: "zoom.us",
                          settings: DeviceSettings(noiseMode: .transparency))
let game = AutomationRule(bundleID: "com.game", appName: "Game",
                          settings: DeviceSettings(noiseMode: .anc, lowLatency: true))
let rules = [zoom, game]
var engine = AutomationEngine()
var buds = DeviceSettings(noiseMode: .anc, eqPreset: 1, lowLatency: false)
func step(_ running: [String]) -> DeviceSettings {
    let changes = engine.update(running: running, rules: rules, current: buds).changes
    if let mode = changes.noiseMode { buds.noiseMode = mode }
    if let preset = changes.eqPreset { buds.eqPreset = preset }
    if let on = changes.lowLatency { buds.lowLatency = on }
    return changes
}
check(step(["com.apple.finder"]).isEmpty, "no rule app running: nothing changes")
check(step(["com.apple.finder", "us.zoom.xos"]) == DeviceSettings(noiseMode: .transparency), "zoom opens: transparency")
check(step(["com.apple.finder", "us.zoom.xos"]).isEmpty, "steady state: nothing more")
check(step(["com.apple.finder"]) == DeviceSettings(noiseMode: .anc), "zoom quits: back to noise cancellation")
_ = step(["us.zoom.xos"])
check(step(["us.zoom.xos", "com.game"]) == DeviceSettings(noiseMode: .anc, lowLatency: true), "newest rule wins")
check(step(["com.game"]).isEmpty, "zoom quits under the game: game still owns the settings")
check(step([]) == DeviceSettings(lowLatency: false) && buds == DeviceSettings(noiseMode: .anc, eqPreset: 1, lowLatency: false),
      "game quits: back to the original settings")
_ = step(["us.zoom.xos"])
buds.noiseMode = .off // user picks Off during the call
check(step([]).isEmpty, "manual change during a rule is kept")
var waiting = AutomationEngine()
check(waiting.update(running: ["us.zoom.xos"], rules: rules, current: DeviceSettings()).changes.isEmpty,
      "nothing sent before the earbuds report their settings")
check(waiting.update(running: ["us.zoom.xos"], rules: rules,
                     current: DeviceSettings(noiseMode: .anc)) == (DeviceSettings(noiseMode: .transparency), "us.zoom.xos"),
      "applies once the earbuds report, naming the app")

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
check(JieliCodec.encodeGetName() == bytes("00 00 00 02"), "jieli name mask")
check(JieliCodec.encodeSetName("  My Buds ") == bytes("08 01 4d 79 20 42 75 64 73"), "jieli set name, trimmed")
check(JieliCodec.encodeSetName("") == nil && JieliCodec.encodeSetName("   ") == nil, "empty name refused")
check(JieliCodec.encodeSetName(String(repeating: "a", count: 20)) != nil
      && JieliCodec.encodeSetName(String(repeating: "a", count: 21)) == nil, "name up to 20 bytes")
check(JieliCodec.encodeSetName("Ünïcødé Buds 🎧") == nil, "multi-byte characters count as bytes: 21 > 20")

var hoco = Capabilities()
check(!hoco.noiseControl && !hoco.lowLatency && hoco.eqPresets.isEmpty, "nothing shown before the earbuds report")
hoco.learn(from: sys)
hoco.learn(from: adv ?? JieliAdvInfo())
check(hoco.noiseControl && hoco.transparency, "hoco noise control learned")
check(hoco.lowLatency && hoco.eqPresets.count == 6, "hoco low latency and presets learned")
check(hoco.rename, "rename offered once the earbuds report their name")
check(Capabilities.isJieli(deviceName: "HOCO EQ34 Plus ANC") && !Capabilities.isJieli(deviceName: "AirPods Pro"),
      "jieli name match")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
