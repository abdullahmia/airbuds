# Earbud protocol

How AirBuds talks to Hoco earbuds. Hoco builds its earbuds on Zhuhai Jieli
chips (Bluetooth company id `0x05D6`), which speak Jieli's **RCSP** control
protocol. Everything here is implemented in `Sources/AirBudsKit/Jieli.swift`
and was verified against a **HOCO EQ34 Plus ANC** on firmware 2.4.0.

## Transport

- **BLE GATT**: service `AE00`. Commands are written to `AE01` (write without
  response), and replies and updates arrive as notifications on `AE02`.
- The earbuds must be paired and connected for audio in macOS first. The app
  only opens the BLE control link on top of that.
- **Finding the BLE side:** the earbuds advertise manufacturer data that starts
  with `d6 05` and contains their classic Bluetooth address, e.g.
  `d6 05 c0 80 0d e0 22 a5 67 f5 c5 08 bd 01 64 64 00 …`. The app matches that
  address to the connected classic device, falling back to the advertised name.
- Writes are split into chunks of the negotiated BLE write size, and the earbuds
  reassemble them. Replies longer than one notification arrive in pieces too.
- The classic `JL_SPP` channel (RFCOMM 1) exists but refused connections from
  macOS in testing, so the app doesn't use it.

## Handshake

Before anything else, both sides prove they know Jieli's key. Until this
passes, the earbuds silently ignore every command. These packets are raw, with
no RCSP framing:

```
app  → buds   00 + 16 random bytes          our challenge
buds → app    01 + respond(our challenge)
app  → buds   02 'p' 'a' 's' 's'
buds → app    00 + 16 random bytes          their challenge
app  → buds   01 + respond(their challenge)
buds → app    02 'p' 'a' 's' 's'            (not every firmware sends this)
```

`respond` is the Bluetooth core spec's **E1** function (SAFER+ `Ar` / `Ar'`),
keyed with Jieli's fixed key `06775f87918dd423005df1d8cf0c142b` and the fixed
"address" `11 22 33 33 22 11`. The app checks the earbuds' answer before going
on. If the final `pass` doesn't arrive within 1.5 s, it carries on anyway.

## Frame format

| Bytes | Field |
| --- | --- |
| 0–2 | `FE DC BA` |
| 3 | flags: bit 7 = command (clear = reply), bit 6 = reply wanted |
| 4 | opcode |
| 5–6 | payload length, big-endian |
| 7… | payload |
| last | `EF` |

A command's payload starts with a sequence number. A reply's payload starts
with `[status, sequence]`, where status `0` means OK. The app sends every
command with flags `C0`.

## Commands

| Opcode | Name | Params | Reply / meaning |
| --- | --- | --- | --- |
| `07` | Get sys info | `FF` + attribute mask (u32 BE) | `FF` + attributes |
| `08` | Set sys info | `FF` + attributes | status |
| `09` | Sys info changed | (from the earbuds) | `FF` + attributes |
| `C0` | Set ADV info | attributes | status |
| `C1` | Get ADV info | attribute mask (u32 BE) | attributes |
| `C2` | Status beacon | (from the earbuds) | the app re-reads the battery |

**Attributes** are `[length, type, data…]` repeated, where `length` counts the
type byte plus the data. **Masks** set bit `n` for attribute type `n`.

### Sys info attributes (function `FF`)

| Type | Meaning | Data |
| --- | --- | --- |
| `04` | EQ | `[preset, gain × 10]` |
| `0C` | EQ presets | `[bands, freq u16 BE × bands, then (id, gain × bands) per preset]` |
| `0D` | Noise mode | `[mode, left max, right max, left gain, right gain]` (u16 each) |
| `0E` | Noise modes on offer | `[count, entry × count]`, entries as in `0D` |

Noise mode `0` = Off, `1` = Noise Cancellation, `2` = Transparency. To switch
modes, send the mode's entry from `0E` as attribute `0D`.

EQ presets follow Jieli's standard table: `0` Normal, `1` Rock, `2` Pop,
`3` Classical, `4` Jazz, `5` Country. The earbuds list unused slots after
these. To pick a preset, send `[id, its gains]` as attribute `04`.

### ADV info attributes

| Type | Meaning | Data |
| --- | --- | --- |
| `00` | Battery | `[left, right, case]`: level, `| 0x80` while charging, `0` = not available |
| `01` | Name | UTF-8 |
| `05` | Work mode | `1` normal, `2` game mode (Low Latency) |

## Example

Switch to Transparency, then read it back:

```
-> fe dc ba c0 08 00 0d 03  ff 0a 0d 02 40 00 40 00 39 96 39 96  ef
<- fe dc ba 00 08 00 02 00 03 ef                                       OK
<- fe dc ba 80 09 00 0d 04  ff 0a 0d 02 40 00 40 00 39 96 39 96  ef    pushed update
```

## Debugging

`AIRBUDS_DEBUG=1 swift run AirBuds` logs every packet in both directions,
including the handshake:

```
# [AirBuds] -> 00418813354f40bed2f276e0e253b27d82   (our challenge)
# [AirBuds] <- 010a5b92406158d39c4f5317e7b986f34f   (their answer)
# [AirBuds] Connected to HOCO EQ34 Plus ANC over BLE
# [AirBuds] -> fedcbac007000601ff00007010ef         (get sys info)
```
