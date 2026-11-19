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

## Bigger: reverse engineering: done (two of four)

Worked out from Jieli's published SDK and app source
([Android-JL_Bluetooth](https://github.com/Jieli-Tech/Android-JL_Bluetooth)) and
read-only probes of a HOCO EQ34 Plus ANC (`AIRBUDS_SEND`), then tested on it.
Details in [PROTOCOL.md](PROTOCOL.md).

| # | Feature | Notes |
| --- | --- | --- |
| 10 | ✅ **Custom EQ** | 10 bands, ±8 dB, as EQ mode `6`. The earbuds accept it but don't report the gains back, so AirBuds keeps and re-sends them. Not yet confirmed by ear. |
| 11 | ✅ **Touch controls** | Single, double and triple tap per bud, including "switch noise mode". Verified: changes are accepted and read back. |
| 12 | ➖ **Find My Earbuds** | Worked (opcode `19`; the left bud played alone in a test) but left out of the app by choice. The protocol is in PROTOCOL.md if it's wanted later. |
| 13 | ⛔ **In-ear detection** | Not possible on the EQ34: it doesn't report ADV attribute `08` (in-ear check), so it has no wear sensor. Could be added for models that report it. |

## Distribution

| Item | Notes |
| --- | --- |
| **Developer ID signing and notarization** | Removes the "Apple could not verify" warning on first launch. Needs a paid Apple Developer Program membership ($99 a year). With one, `release.yml` would import the certificate from GitHub secrets, sign with `--options runtime --timestamp`, submit with `xcrun notarytool submit --wait` and staple with `xcrun stapler staple`. |

## Suggested order

1. **Confirm Custom EQ by ear** on the EQ34, and adjust if the gains don't apply.
2. **A shortcut recorder** for the noise control shortcut.
3. **Developer ID signing** (see Distribution) when there's a paid account.

Notes on the shipped quick wins:

- **Shortcuts:** the `airbuds://` scheme works with Shortcuts' **Open URLs**
  action. Native Shortcuts actions (App Intents) need Xcode's build-time metadata
  extraction, which a Command Line Tools build can't do.
- **Keyboard shortcut:** fixed at ⌃⌥N for now. A shortcut recorder to change it
  would be a small follow-up.
