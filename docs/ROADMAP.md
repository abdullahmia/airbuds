# Roadmap

Ideas for what to add to AirBuds next, grouped by how much work each needs.
Nothing here is promised; it's a list to pick from.

AirBuds already has battery for each bud and the case, low battery alerts,
noise control, the six EQ presets, Low Latency, device info and Open at Login,
plus the quick wins below.

## Quick wins: done

All six shipped. They use what the app already reads from the earbuds, with no
new protocol work. See the README for how to use them.

| # | Feature | Notes |
| --- | --- | --- |
| 1 | ✅ **Keyboard shortcut for noise control** | ⌃⌥N cycles Noise Cancellation → Transparency → Off from any app, with an indicator under the menu bar icon. Carbon hotkey, so no Accessibility permission. |
| 2 | ✅ **Noise mode in the menu bar icon** | The mode's symbol (as in the panel) sits beside the earbuds icon for Noise Cancellation and Transparency. Can be turned off from the right-click menu. |
| 3 | ✅ **"Fully charged" notification** | Notifies when a bud or the case reaches 100% after charging, using the charging flag (`| 0x80`). `FullChargeTracker` in AirBudsKit, posted by `BatteryNotifier`. |
| 4 | ✅ **Battery time estimate and history** | "About 3h 10m left" in the main panel, and a Battery page with a chart of the session and time left per bud. History stays on the Mac for 7 days. |
| 5 | ✅ **Shortcuts and URL scheme** | `airbuds://noise/transparency`, `airbuds://eq/rock`, `airbuds://low-latency/toggle` and more; works with Shortcuts' Open URLs action. |
| 6 | ✅ **Per-app automation** | An Automations window: noise mode, EQ and Low Latency per app while it's open, restored when it quits. |

## Medium: done

All three shipped. See the README for how to use them.

| # | Feature | Notes |
| --- | --- | --- |
| 7 | ✅ **Rename your earbuds** | Pencil next to the name in Quick Settings. ADV attribute `01` through `C0`, up to 20 bytes; the EQ34 Plus ANC accepts it (result 0) and reads it back. Other devices see it after the earbuds restart. Renamed earbuds are remembered by address. |
| 8 | ✅ **Auto-update with Sparkle** | Daily checks and Check for Updates…; releases publish an EdDSA-signed `appcast.xml`. Needs the `SPARKLE_PRIVATE_KEY` repository secret (see README → Releasing). |
| 9 | ✅ **Connect / disconnect button** | Paired earbuds with a Connect button when none are connected, Disconnect in Quick Settings, and `airbuds://connect` / `disconnect`. |

## Bigger: needs reverse engineering

Jieli's SDK defines these features, but each one needs packet captures (with
`AIRBUDS_DEBUG=1` and the official phone app) to confirm whether a given
firmware supports it and how.

| # | Feature | Notes |
| --- | --- | --- |
| 10 | **Custom EQ** | A 5- or 10-band slider editor instead of fixed presets. The EQ attribute (`04`) already carries per-band gains and attribute `0C` lists the band frequencies, so this is the most promising of the four. |
| 11 | **Touch controls** | Change what tap, double-tap and long-press do on each bud. |
| 12 | **Find My Earbuds** | Play a loud tone on a lost bud. |
| 13 | **In-ear detection** | Pause media when you take a bud out, if the earbuds report wear status. |

## Distribution

| Item | Notes |
| --- | --- |
| **Developer ID signing and notarization** | Removes the "Apple could not verify" warning on first launch. Needs a paid Apple Developer Program membership ($99 a year). With one, `release.yml` would import the certificate from GitHub secrets, sign with `--options runtime --timestamp`, submit with `xcrun notarytool submit --wait` and staple with `xcrun stapler staple`. |

## Suggested order

1. **Custom EQ** (#10): the feature people most often miss in the official Hoco app.
2. **Find My Earbuds** (#12): useful and usually a single command once captured.

Notes on the shipped quick wins:

- **Shortcuts:** the `airbuds://` scheme works with Shortcuts' **Open URLs**
  action. Native Shortcuts actions (App Intents) need Xcode's build-time metadata
  extraction, which a Command Line Tools build can't do.
- **Keyboard shortcut:** fixed at ⌃⌥N for now. A shortcut recorder to change it
  would be a small follow-up.
