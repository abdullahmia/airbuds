// Finding the earbuds among CoreAudio's output devices.

import Foundation
import AirBudsKit

func volumeChecks() {
    section("Volume")
    let address = "aa-bb-cc-dd-ee-ff"
    check(AudioOutput.isEarbuds(uid: "AA-BB-CC-DD-EE-FF:output", address: address), "bluetooth output uid")
    check(AudioOutput.isEarbuds(uid: "AA-BB-CC-DD-EE-FF:input", address: address), "uid suffix doesn't matter")
    check(AudioOutput.isEarbuds(uid: "aa:bb:cc:dd:ee:ff", address: "AA-BB-CC-DD-EE-FF"), "colons and case")
    check(!AudioOutput.isEarbuds(uid: "AA-BB-CC-DD-EE-00:output", address: address), "other device")
    check(!AudioOutput.isEarbuds(uid: "BuiltInSpeakerDevice", address: address), "built-in speakers")
    check(!AudioOutput.isEarbuds(uid: "09D1F778-0000-0000-1923-010380351E78", address: "09-d1-f7-78-00-00"),
          "display uid that starts with the same digits")
    check(!AudioOutput.isEarbuds(uid: "anything", address: ""), "no address")

    check(AudioOutput.symbol(level: 0.5, muted: true) == "speaker.slash.fill", "muted")
    check(AudioOutput.symbol(level: 0, muted: false) == "speaker.fill", "silent")
    check(AudioOutput.symbol(level: 0.2, muted: false) == "speaker.wave.1.fill", "low")
    check(AudioOutput.symbol(level: 0.5, muted: false) == "speaker.wave.2.fill", "medium")
    check(AudioOutput.symbol(level: 1, muted: false) == "speaker.wave.3.fill", "high")
}
