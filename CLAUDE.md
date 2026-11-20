# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

AirBuds is a native macOS menu bar app (Swift Package, macOS 13+) that controls
Hoco earbuds over BLE using Jieli's RCSP protocol. There is no Xcode project, no
helper process, and no network access apart from Sparkle update checks.

## Commands

```bash
swift build                                   # debug build of everything
swift run AirBudsKitChecks                    # the test suite (see below)
swift run AirBuds                             # run the app (Bluetooth works: Info.plist is linked in)
AIRBUDS_DEBUG=1 swift run AirBuds             # log every RCSP frame to and from the earbuds
AIRBUDS_OPEN=1 swift run AirBuds              # open the panel on launch
AIRBUDS_SNAPSHOT=docs/screenshots swift run AirBuds   # render every panel page to PNG, then exit (debug)
AIRBUDS_DEBUG=1 AIRBUDS_SEND="c1 ffffffff; 07 ff ffffffff" swift run AirBuds
                                              # send raw RCSP commands after connecting (debug)
scripts/build-app.sh [--universal] [--install]  # build/AirBuds.app with Sparkle embedded, ad-hoc signed
scripts/make-dmg.sh 0.1.0                     # DMG, zip and checksums in dist/
scripts/build-site.sh && python3 -m http.server -d _site   # landing page with the latest release filled in
```

CI (`.github/workflows/ci.yml`) runs `swift build -c release --product AirBudsKitChecks`,
the checks, then `scripts/build-app.sh --universal` and the DMG. Releases are cut by
pushing a `v*` tag (`release.yml`). The version lives in `Resources/Info.plist`
(`CFBundleShortVersionString`).

The landing page is `site/index.html`: plain HTML with the Tailwind browser build,
no other tooling. `{{VERSION}}`, `{{DMG_URL}}` and similar placeholders are filled from
the latest GitHub release by `scripts/build-site.sh`. `pages.yml` deploys it to
GitHub Pages; `release.yml` starts that workflow after each release, because
events created with the workflow token don't trigger `on: release`. Images come from `docs/icon.png`
and `docs/screenshots/`, so feature or UI changes may need the page's copy updated too.

## Tests: AirBudsKitChecks, not XCTest

The project builds with only the Command Line Tools, where XCTest and swift-testing
aren't available. Tests are the `AirBudsKitChecks` executable: plain functions that
call `check(condition, "message")` from `Harness.swift` and print `FAIL (line N)`.
The process exits non-zero on any failure. There's no filter for running one check.
To focus on one area, comment out the other calls in `Sources/AirBudsKitChecks/main.swift`.
New checks go in the file for their area, and protocol checks go in `Protocols/<Brand>Checks.swift`.
Protocol checks use byte strings captured from real earbuds (`bytes("fe dc ba …")`).

Only `AirBudsKit` is testable this way. Keep logic that can be checked there (pure Swift,
no UI or Bluetooth), not in the app target.

## Command Line Tools constraints

Swift macros need plugins that ship only with Xcode, so don't use `@State`,
`@Observable`, `#Preview` or any other macro. For view-local state use
`@StateObject private var x = Local<Value>(…)` (`Views/Components.swift`). App
Intents also don't work, so Shortcuts integration goes through `airbuds://` links
(`AirBudsKit/Logic/Commands.swift`).

## Architecture

`docs/ARCHITECTURE.md` has the diagrams, the full source map and "Adding a brand".
`docs/PROTOCOL.md` documents RCSP byte by byte. The big picture:

- **Three targets.**
  - `AirBudsKit` (library): models, decision logic and protocol codecs.
  - `AirBuds` (executable): the app.
  - `AirBudsKitChecks`: the checks.
- **Driver layer.** `EarbudsController` (`Device/`) holds all device state and
  every setter. It talks only to the `EarbudsDriver` protocol (`Drivers/EarbudsDriver.swift`)
  and receives brand-neutral `EarbudsReport` values plus the current `Capabilities`.
  `JieliDriver` is the only driver. Brand-specific code lives in two places only:
  - `AirBudsKit/Protocols/<Brand>/`: pure codecs, including the conversion to `EarbudsReport`.
  - `AirBuds/Drivers/<Brand>/`: transport and session.

  Nothing outside those folders should use Jieli types.
- **Connection flow.** Hoco earbuds play audio over classic Bluetooth but take
  commands over BLE. `JieliTransport` only scans BLE while a supported paired classic
  device is connected. It matches the Jieli advert (company ID `0x05D6`) by the classic
  address inside it, then runs the challenge/response handshake before any command.
  Today a device counts as supported if its name contains "hoco"
  (`Capabilities.isJieli`) or it's in `KnownEarbuds`.
- **Capabilities are learned.** `Capabilities` starts empty and fills in from the
  earbuds' replies (`Capabilities+Jieli.swift`). The UI shows only what's supported,
  so a feature appears by setting a capability, not by checking the model name.
- **Confirmed settings.** Each setter sends the change, updates state as pending
  and starts a `ConfirmedSetting`. Reports that don't match are ignored and the value
  is read again until the earbuds confirm or it times out. Setters ignore new
  requests while a change of the same kind is pending.
- **Threading.** CoreBluetooth and IOBluetooth call back on the main queue, and
  everything (driver, controller, views) runs on the main thread.
- **Still numbered Jieli's way:** EQ preset ids (`EqPreset.standard`), the Custom EQ
  slot (`CustomEq.id` = mode 6) and `TouchFunction` raw values.

## Working on the protocol

Use `AIRBUDS_SEND` to reverse-engineer: opcodes and parameters in hex, `;`-separated.
Prefer reads (`07` sys info, `c1` ADV info), and check `docs/PROTOCOL.md` before
sending anything that writes. Record what you verify on hardware in `PROTOCOL.md`,
and add the captured bytes as checks.

## Keeping docs in sync

- **New, moved or renamed files:** update the source map in `docs/ARCHITECTURE.md`
  and the layout in `README.md`.
- **UI changes:** regenerate `docs/screenshots/` with `AIRBUDS_SNAPSHOT=docs/screenshots swift run AirBuds`.
  The sample data comes from `Debug/DebugSnapshots.swift`, so update it when you add state or capabilities.
- **New features:** the README and `docs/ROADMAP.md` track what has shipped.
