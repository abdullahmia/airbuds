// Self-checks for AirBudsKit: `swift run AirBudsKitChecks`.
// (XCTest / swift-testing aren't available with only the Command Line Tools.)
// Each area lives in its own file; protocol checks are under Protocols/.

import Foundation

// Print each line as it happens, so a crash on CI still shows how far the checks got.
setvbuf(stdout, nil, _IOLBF, 0)

lowBatteryChecks()
fullChargeChecks()
batteryHistoryChecks()
noiseCyclingChecks()
linkChecks()
automationChecks()
jieliChecks()

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
