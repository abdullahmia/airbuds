// Noise mode cycling (the keyboard shortcut) and airbuds:// links.

import Foundation
import AirBudsKit

/// Noise Cancellation → Standard → Transparent.
func noiseCyclingChecks() {
    section("Noise mode cycling")
    check(NoiseMode.next(after: .anc, transparency: true) == .off, "nc -> standard")
    check(NoiseMode.next(after: .off, transparency: true) == .transparency, "standard -> transparent")
    check(NoiseMode.next(after: .transparency, transparency: true) == .anc, "transparent -> nc")
    check(NoiseMode.next(after: .anc, transparency: false) == .off, "nc -> standard without transparent")
    check(NoiseMode.next(after: nil, transparency: true) == .anc, "unknown -> nc")
}

/// airbuds:// link parsing.
func linkChecks() {
    section("airbuds:// links")
    func command(_ s: String) -> AirBudsCommand? { URL(string: s).flatMap(AirBudsCommand.init(url:)) }
    check(command("airbuds://noise/anc") == .noise(.anc), "url: noise cancellation")
    check(command("AirBuds://Noise/Transparency") == .noise(.transparency), "url: case-insensitive")
    check(command("airbuds://noise/off") == .noise(.off), "url: off")
    check(command("airbuds://noise/standard") == .noise(.off), "url: standard is noise control off")
    check(command("airbuds://noise/transparent") == .noise(.transparency), "url: transparent")
    check(command("airbuds://noise/next") == .nextNoise, "url: cycle")
    check(command("airbuds://eq/Rock") == .eq("rock"), "url: eq")
    check(command("airbuds://low-latency/on") == .lowLatency(true), "url: low latency on")
    check(command("airbuds://low-latency/toggle") == .lowLatency(nil), "url: low latency toggle")
    check(command("airbuds://open") == .open, "url: open")
    check(command("airbuds://connect") == AirBudsCommand.connect, "url: connect")
    check(command("airbuds://disconnect") == AirBudsCommand.disconnect, "url: disconnect")
    check(command("airbuds://noise/loud") == nil, "url: unknown command ignored")
    check(command("https://noise/anc") == nil, "url: other schemes ignored")
    check(AirBudsCommand.preset(named: "normal", in: JieliCodec.eqPresets)?.id == 0, "eq by label")
    check(AirBudsCommand.preset(named: "3", in: JieliCodec.eqPresets)?.key == "classical", "eq by number")
    check(AirBudsCommand.preset(named: "dubstep", in: JieliCodec.eqPresets) == nil, "unknown eq")
}
