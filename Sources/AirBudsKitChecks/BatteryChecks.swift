// Battery logic: low battery and fully charged alerts, history and time left.

import Foundation
import AirBudsKit

/// Low battery alerts at 20% and 10%, re-armed after charging.
func lowBatteryChecks() {
    section("Low battery alerts")
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
}

/// "Fully charged" after charging up to 100%.
func fullChargeChecks() {
    section("Fully charged alerts")
    func charge(left: Int?, charging: Bool, case caseLevel: Int? = nil, caseCharging: Bool = false) -> Battery {
        var b = Battery()
        b.left = left.map { BatteryLevel(level: $0, charging: charging) }
        b.case = caseLevel.map { BatteryLevel(level: $0, charging: caseCharging) }
        return b
    }
    var full = FullChargeTracker()
    check(full.update(charge(left: 100, charging: true)).isEmpty, "already full on connect: no alert")
    check(full.update(charge(left: 80, charging: true)).isEmpty, "charging below 100%: no alert yet")
    let reachedFull: [BatteryPart] = full.update(charge(left: 100, charging: true))
    check(reachedFull == [BatteryPart.left], "alert on reaching 100%")
    check(full.update(charge(left: 100, charging: true)).isEmpty, "no repeat while it stays full")
    _ = full.update(charge(left: 90, charging: true))
    let flagCleared: [BatteryPart] = full.update(charge(left: 100, charging: false))
    check(flagCleared == [BatteryPart.left], "full counts even when the charging flag clears at 100%")
    _ = full.update(charge(left: 90, charging: true))
    _ = full.update(charge(left: 92, charging: false))
    let disarmed: [BatteryPart] = full.update(charge(left: 100, charging: false))
    check(disarmed.isEmpty, "charging stopped short of 100% disarms")
    _ = full.update(charge(left: nil, charging: false, case: 70, caseCharging: true))
    let caseFull: [BatteryPart] = full.update(charge(left: nil, charging: false, case: 100, caseCharging: true))
    check(caseFull == [BatteryPart.case], "case alerts too")
}

/// Samples, sessions and the time-left estimate.
func batteryHistoryChecks() {
    section("Battery history and time left")
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
    func drainingLeft(at minute: Int) -> Int {
        if minute < 10 { return 100 }
        if minute < 30 { return 90 }
        if minute < 50 { return 80 }
        return 70
    }
    for minute in 7...50 {
        history.record(buds(drainingLeft(at: minute), 100), at: at(Double(minute)))
    }
    check(history.timeRemaining(.right, now: at(51)) == nil, "no estimate without drops")
    let leftLeft = history.timeRemaining(.left, now: at(55))
    let leftMinutes: Double = (leftLeft ?? -1) / 60
    check(abs(leftMinutes - 135) < 0.02, "left: 70% at 10%/20 min, 5 min after the drop -> 135 min")
    check(history.timeRemaining(.left, now: at(64)) != nil, "estimate holds within the session gap")
    var overdueHistory = history
    for minute in 51...90 { overdueHistory.record(buds(70, 100), at: at(Double(minute))) }
    let overdue = overdueHistory.timeRemaining(.left, now: at(90))
    let overdueMinutes: Double = (overdue ?? 0) / 60
    check(overdueMinutes > 100, "overdue drop: slower rate, so more than the naive 100 min left")
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
}
