// Jieli RCSP: handshake, framing, payloads, touch controls, custom EQ and
// capabilities, checked against bytes captured from a HOCO EQ34 Plus ANC.

import AirBudsKit

/// The Jieli protocol, end to end on captured bytes.
func jieliChecks() {
    section("Jieli protocol")
    // Jieli (Hoco): byte strings captured from a HOCO EQ34 Plus ANC.

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
    check(JieliCodec.encodeSetName("") == nil, "empty name refused")
    check(JieliCodec.encodeSetName("   ") == nil, "blank name refused")
    check(JieliCodec.encodeSetName(String(repeating: "a", count: 20)) != nil, "20-byte name accepted")
    check(JieliCodec.encodeSetName(String(repeating: "a", count: 21)) == nil, "21-byte name refused")
    check(JieliCodec.encodeSetName("Ünïcødé Buds 🎧") == nil, "multi-byte characters count as bytes: 21 > 20")

    section("Touch controls and custom EQ")
    // Touch controls and custom EQ: bytes from a HOCO EQ34 Plus ANC.
    let keys = JieliCodec.decodeAdvInfo(bytes("13 02 01 01 05 02 01 05 01 02 04 02 02 04 01 03 03 02 03 03")).touchControls
    check(keys?.count == 6, "six gestures reported")
    check(keys?.first == TouchControl(bud: .left, gesture: 1, function: 5), "left single tap: play/pause")
    let reportedKeys: [TouchControl] = keys ?? []
    check(reportedKeys.contains(TouchControl(bud: .right, gesture: 3, function: 3)), "right triple tap: previous track")
    check(TouchFunction.label(for: 4) == "Next Track", "function label")
    check(TouchFunction.label(for: 42) == "Other (42)", "unknown function label")
    check(JieliCodec.encodeSetTouchControl(TouchControl(bud: .left, gesture: 1, function: 5)) == bytes("04 02 01 01 05"),
          "set one gesture (accepted by the earbuds, result 0)")
    check(JieliCodec.encodeSetTouchControl(TouchControl(bud: .right, gesture: 2, function: 255)) == bytes("04 02 02 02 ff"),
          "switch noise mode is function 255")
    check(JieliCodec.encodeGetTouchControls() == bytes("00 00 00 04"), "touch controls mask")
    check(JieliCodec.encodeGetAdvInfo() == bytes("00 00 00 27"), "adv read includes touch controls")

    let table = JieliCodec.decodeSysInfo(bytes("""
        ff 2c 0c 0a 00 1f 00 3e 00 7d 00 fa 01 f4 03 e8 07 d0 0f a0 1f 40 3e 80 \
        00 00 00 00 00 00 00 00 00 00 00 06 00 00 00 04 04 04 00 02 03 04
        """))
    let expectedBands: [Int] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    check(table.eqFrequencies == expectedBands, "eq band frequencies")
    check(table.eqGains[6] == bytes("00 00 00 04 04 04 00 02 03 04"), "stored custom slot")
    check(JieliCodec.encodeSetCustomEq(gains: [1, 0, 0, 4, 4, 4, 0, 2, 3, 4])
          == bytes("ff 0c 04 06 01 00 00 04 04 04 00 02 03 04"), "custom eq (accepted by the earbuds)")
    check(JieliCodec.encodeSetCustomEq(gains: [-8, -9, 9, 0, 0, 0, 0, 0, 0, 0])
          == bytes("ff 0c 04 06 f8 f8 08 00 00 00 00 00 00 00"), "custom gains clamp to ±8 dB")
    check(CustomEq.label(hertz: 125) == "125", "band label below 1 kHz")
    check(CustomEq.label(hertz: 16000) == "16k", "band label in kHz")

    section("Capabilities")
    var hoco = Capabilities()
    check(!hoco.noiseControl && !hoco.lowLatency && hoco.eqPresets.isEmpty, "nothing shown before the earbuds report")
    hoco.learn(from: sys)
    hoco.learn(from: adv ?? JieliAdvInfo())
    check(hoco.noiseControl && hoco.transparency, "hoco noise control learned")
    check(hoco.lowLatency && hoco.eqPresets.count == 6, "hoco low latency and presets learned")
    check(hoco.rename, "rename offered once the earbuds report their name")
    check(hoco.touchControls, "touch controls learned from the adv capture")
    check(hoco.eqBands.isEmpty, "no custom eq without a table that has a custom slot")
    hoco.learn(from: table)
    check(hoco.eqBands.count == 10, "custom eq offered with a 10-band table")
    check(Capabilities.isJieli(deviceName: "HOCO EQ34 Plus ANC") && !Capabilities.isJieli(deviceName: "AirPods Pro"),
          "jieli name match")
}
