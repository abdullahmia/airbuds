# Architecture

AirBuds is a single native process: an AppKit status item that hosts a SwiftUI
panel, talking to Hoco earbuds over BLE through CoreBluetooth. There is no
helper process, no web view and no network access.

## Modules

The Swift package has three targets.

| Target | Kind | What it does |
| --- | --- | --- |
| `AirBudsKit` | library | The earbud protocol (Jieli RCSP): handshake cipher, packet framing, payload encoders and decoders, and capabilities. Pure Swift with no UI or Bluetooth, so it's easy to test. |
| `AirBuds` | app | BLE transport, device state, settings and the SwiftUI panel. |
| `AirBudsKitChecks` | tool | Self-checks for `AirBudsKit` (`swift run AirBudsKitChecks`), built on bytes captured from real earbuds. |

```mermaid
flowchart LR
    subgraph App["AirBuds (menu bar app)"]
        direction TB
        Main["main.swift<br/>AppDelegate · NSStatusItem · NSPopover"]
        Views["Views/<br/>PanelView · MainView<br/>QuickSettings · Equalizer"]
        Controller["EarbudsController<br/>@Published DeviceState"]
        Confirm["ConfirmedSetting"]
        Session["JieliSession<br/>commands ⇄ reports"]
        Transport["JieliTransport<br/>CoreBluetooth · handshake"]
        Settings["AppSettings<br/>UserDefaults · SMAppService"]
    end
    subgraph Kit["AirBudsKit"]
        Auth["JieliAuth<br/>E1 / SAFER+"]
        Rcsp["Rcsp · RcspParser"]
        Codec["JieliCodec<br/>sys info · ADV info"]
        Models["Capabilities<br/>Battery · NoiseMode · EqPreset"]
    end
    Buds(("Earbuds"))

    Main --> Views
    Main --> Settings
    Views -- "user actions" --> Controller
    Controller -- "state" --> Views
    Controller --> Confirm
    Controller --> Session
    Controller --> Models
    Session --> Rcsp
    Session --> Codec
    Session <--> Transport
    Transport --> Auth
    Transport <-- "BLE AE00" --> Buds
```

## Source map

```
Sources/AirBudsKit/
  Jieli.swift              Handshake (E1/SAFER+), RCSP framing and parser, payload codecs, capability learning
  Models.swift             Battery, NoiseMode, EqPreset, Capabilities
  LowBattery.swift         When to alert: 20% / 10% thresholds, re-arm after charging
Sources/AirBuds/
  main.swift               App entry, status item, popover, right-click menu
  JieliTransport.swift     Finds the BLE side of the connected buds, connects, runs the handshake, relays bytes
  JieliSession.swift       Encodes reads and settings, decodes replies and pushed updates
  EarbudsController.swift  All device state and every setter
  ConfirmedSetting.swift   "Wait until the buds confirm" helper plus timer utilities
  DeviceState.swift        Plain value types the UI renders
  AppSettings.swift        Menu bar battery mode, low battery alerts, Open at Login
  LowBatteryNotifier.swift Posts notifications; rules live in AirBudsKit/LowBattery.swift
  MenuBarIcon.swift        The menu bar icon (SF "earbuds" symbol as a template image)
  Log.swift                Console logging; AIRBUDS_DEBUG=1 logs every packet
  DebugSnapshots.swift     Debug only: renders every page to PNG (used for docs/screenshots)
  Views/                   One file per panel page plus shared components
```

## How a connection comes up

Hoco earbuds play audio over classic Bluetooth, but take control commands over
BLE. Every 3 seconds `JieliTransport` checks for a paired classic device that is
connected and has "hoco" in its name. Only then does it scan BLE, so the app
never scans otherwise.

```mermaid
sequenceDiagram
    autonumber
    participant T as JieliTransport
    participant M as macOS Bluetooth
    participant B as Earbuds
    participant C as EarbudsController

    loop every 3 s while not connected
        T->>M: pairedDevices(), keep connected Hoco ones
        T->>M: scan BLE while one exists
    end
    B-->>T: advert: d6 05 … + classic address
    T->>B: connect, discover AE00, subscribe to AE02
    T->>B: 00 + challenge
    B-->>T: 01 + E1(challenge)  (checked)
    T->>B: 02 "pass"
    B-->>T: 00 + their challenge
    T->>B: 01 + E1(their challenge)
    B-->>T: 02 "pass"
    T->>C: onConnected(name, address, firmware)
    C->>B: get sys info (EQ, presets, noise modes) · get ADV info (battery, name, work mode)
    B-->>C: replies → state, capabilities learned
```

Firmware comes from the classic device's Device ID (PnP) SDP record. If a
connection or handshake fails 3 times, the transport stops trying for that
device until it reconnects for audio.

## Capabilities come from the earbuds

`Capabilities` starts empty. The first replies fill it in: the noise modes the
earbuds list (attribute `0E`) turn on Noise Control and Transparency, an EQ
report turns on the preset list, and a work mode report turns on Low Latency.
A Hoco model without ANC simply never shows the Noise Control section.

## How a setting change works

The earbuds sometimes report the old value for a moment after a change. Each
setting is wrapped in a `ConfirmedSetting`, which makes the UI respond
instantly and then waits for the earbuds to agree:

1. The UI calls a setter, e.g. `setNoiseMode(.transparency)`.
2. The controller sends the set command, updates state optimistically and
   marks it **pending**. The UI shows a spinner and ignores further taps on that control.
3. After 400 ms it reads the value back. Reports that don't match the target are
   ignored, and it asks again every 500 ms. The earbuds also push a `09` update
   when a value changes, including from a button press on the buds.
4. A matching report clears the pending flag. If no match arrives within 4 s,
   the pending flag is dropped and the next report is trusted.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Pending: begin(target)<br/>send SET, optimistic state
    Pending --> Pending: report ≠ target<br/>re-read in 500 ms
    Pending --> Idle: report = target<br/>apply, clear spinner
    Pending --> Idle: 4 s timeout<br/>clear spinner, read once more
```

Battery is read on connect, every 60 seconds, whenever the panel opens, and
whenever the earbuds push a status beacon (`C2`).

## Low battery alerts

`LowBatteryNotifier` watches battery reports and asks `LowBatteryTracker`
(in AirBudsKit, covered by the self-checks) whether to alert. Each part (left,
right, case) alerts once at 20% and once at 10%. It re-arms after charging, or
once the level is back 5+ points above the last alert, so a battery hovering at
19–21% never spams you. Parts that cross a threshold in the same report share
one notification. Permission is requested the first time earbuds connect, not
at launch.

## UI

- `NSStatusItem` shows the earbuds icon (a template image) and, optionally,
  battery text. Left click toggles an `NSPopover`; right click shows the app menu.
- The popover hosts `PanelView` in an `NSHostingController` with
  `sizingOptions = .preferredContentSize`, so its height follows the content.
- `PanelNavigation.page` drives the sub-pages, which slide in from the right.
  Esc goes back, and closing the popover always returns to the main page.
- Views use a tiny `Local<T>` observable instead of `@State`. In the current
  SDK `@State` is a macro whose compiler plugin ships only with Xcode, and this
  keeps the project buildable with just the Command Line Tools.

## Build and release

```mermaid
flowchart LR
    Tag["git tag v1.2.3<br/>git push --tags"] --> WF["GitHub Actions<br/>release.yml (macos-15)"]
    WF --> Checks["swift run AirBudsKitChecks"]
    Checks --> Build["scripts/build-app.sh --universal<br/>VERSION=1.2.3"]
    Build --> Pack["scripts/make-dmg.sh 1.2.3<br/>DMG + zip + SHA256SUMS"]
    Pack --> Rel["gh release create v1.2.3"]
```

`build-app.sh` runs `swift build -c release`, assembles the `.app` (binary,
Info.plist, icon) and ad-hoc signs it. Info.plist is also linked into the
executable's `__TEXT,__info_plist` section, so a bare `swift run` (or Run in
Xcode) has the Bluetooth usage string too. Without it, macOS terminates the
process on first Bluetooth access.
