# Momentum — Sennheiser Momentum 4 menu bar controller (macOS)

A native macOS menu bar app to control the Sennheiser Momentum 4's noise-cancellation
and transparency from a single slider, plus quick toggles for the ANC sub-modes.

## What it does

Talks directly to the headphones over their proprietary **Qualcomm GAIA V3** control
protocol (Bluetooth Classic RFCOMM) and exposes:

- Noise control modes: **Adaptive · Custom · Off**, with a bidirectional
  **ANC ↔ Transparency** slider in Custom
- **Anti-Wind** toggle (enabled in Custom mode only)
- Live device info: battery %, codec, firmware, model, connection state

There is no official Sennheiser desktop app; this reimplements the relevant parts of
the Smart Control mobile app's protocol natively.

## Build & run

```sh
./build.sh          # swift build (release) + assemble + ad-hoc sign Momentum.app
open Momentum.app    # launch; click "Allow" on the Bluetooth permission prompt
swift test           # unit tests for the GAIA framing / slider model
```

Requirements: macOS 14+, Xcode/Swift toolchain. The headphones must be paired and
connected to this Mac.

> **Liquid Glass (macOS 26 design language):** standard controls only adopt the
> new appearance when the app is **built against the macOS 26 SDK**. `build.sh`
> sets `DEVELOPER_DIR` to the Command Line Tools (which ship `MacOSX26.sdk`) when
> present, so the toggle/slider/segmented controls and popover material render in
> the current design automatically. Building with the bundled Xcode 16.2
> (macOS 15 SDK) yields the legacy look — verify with
> `otool -l Momentum.app/Contents/MacOS/Momentum | grep -A3 LC_BUILD_VERSION`
> (want `sdk 26.x`).

> macOS only allows Bluetooth from a signed `.app` bundle whose Info.plist has
> `NSBluetoothAlwaysUsageDescription`. A bare CLI binary is killed (SIGABRT) on the
> first Bluetooth call. `build.sh` produces the bundle and ad-hoc signs it. Because
> ad-hoc signatures change each build, macOS re-prompts for Bluetooth permission after
> every rebuild (use a stable self-signed identity to avoid this during development).

## Architecture

```
Sources/
  MomentumKit/                 # engine (pure-ish, unit-testable)
    GAIAPacket.swift           # GAIA V3 framing: encode / parse / split-reassemble
    M4Protocol.swift           # vendor + command IDs, codec map, packet builders
    SoundMode.swift            # NoiseMode (Adaptive/Custom/Off) + ANC_Transparency mapping
    RFCOMMTransport.swift      # IOBluetooth RFCOMM link (dedicated BT thread)
    M4Controller.swift         # ObservableObject: device state + high-level commands
    Diag.swift                 # dev-only file logger (/tmp/momentum-diag.log)
  Momentum/                    # SwiftUI app
    MomentumApp.swift          # @main, MenuBarExtra, AppDelegate (lifecycle)
    MenuContentView.swift      # the popover UI
    MenuBarIcon.swift          # custom template glyph (headphones + waveform)
Tests/MomentumKitTests/        # GAIA framing + slider model tests
```

Data flow: `MenuContentView` ⇄ `M4Controller` (@Published state) ⇄ `RFCOMMTransport`
(GAIA packets over RFCOMM) ⇄ headphones. The transport runs all IOBluetooth work on a
dedicated thread and marshals state/packets back to the main queue.

## GAIA V3 protocol (validated live against the device)

Wire format, all multi-byte fields **big-endian**:

```
FF 03 [len:2] [vendorID:2] [commandID:2] [payload: len bytes]
```

`len` = payload byte count; total frame = `8 + len`. The M4 frequently glues several
frames into one RFCOMM read, so the receiver must split by length (`GAIAPacket.split`).

- **Vendor ID:** `0x0495` (Sennheiser/Sonova).
- **Transport:** Bluetooth Classic RFCOMM. The device advertises the control channel as
  an SDP service literally named **"GAIA"** (NOT standard SPP `0x1101`). Find it by
  service name — the RFCOMM channel number is not stable (seen as 2, then 1).

Each feature has a GET (response echoes the value) and usually a SET (empty response):

| Feature | GET → resp | SET | Payload |
|---|---|---|---|
| ANC on/off | `0x1A05 → 0x1B05` | `0x1A04` | `activation` u8 (0/1) |
| Transparency level | `0x1A03 → 0x1B03` | `0x1A02` | `level` u8 |
| ANC sub-modes | `0x1A01 → 0x1B01` | `0x1A00` | `mode` u8, `state` u8 |
| Transparent-hearing on/off | `0x1805 → 0x1905` | `0x1804` | `status` u8 (0/1) |
| Battery % | `0x0603 → 0x0703` | — | u8 (first byte = %) |
| Codec | `0x0800 → 0x0900` | — | u8 (see codec map) |
| Firmware | `0x1201 → 0x1301` | — | Major u16, Minor u16, Patch u16 |
| Model | `0x1206 → 0x1306` | — | string (e.g. "M4AEBT Black") |

ANC sub-modes GET response is 3 `(mode,state)` pairs: `[01 aw 02 cf 03 ad]`.
Codec map: 0 SBC, 1 AAC, 2 aptX, 3 aptX-LL, 4 MP3, 5 aptX-HD, 6 Faststream, 7 LHDC,
8 aptX Adaptive, 9 aptX Lossless.

## Feature semantics (validated live against the device + official app)

Noise control has three modes, matching Sennheiser's Smart Control app:
**Adaptive · Custom · Off**.

- **Adaptive** — `ANC_Status = on` and the `adaptive` ANC sub-mode on; the
  headphones auto-adjust cancellation to the environment.
- **Off** — `ANC_Status = off`.
- **Custom** — `ANC_Status = on`, adaptive off, and **one bidirectional slider
  driven entirely by `ANC_Transparency` (0–100)**: `0` = max ANC, `50` = neutral,
  `100` = full transparency. The device manages its own ANC/transparency blend
  from this single value (it even flips `TransparentHearing_Status` on by itself
  around ~60).

> **CRITICAL (the "only extremes" bug):** in Custom, write **only**
> `ANC_Transparency`. Do **not** also set `TransparentHearing_Status` — doing so
> forces a binary full-ANC/full-transparency state that overrides the smooth
> level. This was confirmed by capturing the device state while sweeping the
> official app's slider: `anc` stays `true` throughout Custom and only
> `ANC_Transparency` moves smoothly. See `M4Controller.setNoiseValue`.

**Anti-Wind** — a plain on/off toggle (`ANC` sub-mode, device value **1 = on**,
`0 = off`; the protocol also defines `2`, unused by the official app). Only
meaningful/enabled in **Custom** mode. "Reduce wind noise in ANC."

The `ANC` sub-mode **Comfort** (mode `2`) exists in the protocol but is **not**
exposed by the official app, so the UI omits it (its effect on the M4 over-ear is
unverified). Easily re-added via `M4Controller.setComfort`.

Reads come from a 6 s background poll; after any write the controller ignores
controllable reads for 3 s (`suppressReadsUntil`) so a stale poll can't revert a
change before the device applies it.

## macOS / IOBluetooth gotchas (hard-won)

These are the non-obvious things that make or break this app:

1. **Dedicated Bluetooth thread.** A SwiftUI app's main run loop delivers SDP
   completions and `Timer`s but NOT the `openRFCOMMChannelAsync` open-complete
   callback — the channel open silently never completes. Run all IOBluetooth work on a
   dedicated `Thread` with its own `CFRunLoop` pumped in `.defaultMode`
   (`RFCOMMTransport`). (A plain `NSApplication` app does deliver it; this is
   SwiftUI-specific.)
2. **Don't touch IOBluetooth from `DispatchQueue.main.async` at startup.**
   `registerForConnectNotifications` / coordinator init deadlocks the main queue. Kick
   off from `applicationDidFinishLaunching`.
3. **Single GAIA connection — always close it on quit.** The M4 allows only one GAIA
   RFCOMM connection. If a process holding it dies without closing the channel, it
   wedges host-side in `bluetoothd` and *every* subsequent open hangs (returns success,
   completion never fires) — even for other tools. Recovery: toggle the **Mac's**
   Bluetooth off/on (power-cycling the headphones is not enough). The app closes the
   channel in `applicationWillTerminate` to prevent this.
4. **Permission requires an app bundle** with `NSBluetoothAlwaysUsageDescription`; gate
   readiness with `CBManager.authorization` (a non-blocking status read).
5. **Find the GAIA channel by SDP service name**, not a fixed channel number.

## Reference

Protocol distilled from the open-source Qt client
[`zaval/sennheiser-desktop-client`](https://github.com/zaval/sennheiser-desktop-client),
whose `gaiaV3/m4.json` is extracted by decompiling the Smart Control Android APK.
A clone is kept under `.context/research/` (gitignored) for reference.
