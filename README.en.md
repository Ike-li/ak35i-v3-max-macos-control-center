# AK35i Control Center: AJAZZ AK35i V3 Max software for macOS

[中文](README.md) · [Download](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases/latest) · [Getting started (Chinese)](docs/GETTING_STARTED.md) · [Chinese and English manuals](docs/manuals/) · [Protocol status](docs/PROTOCOL_STATUS.md)

**AK35i Control Center** is an unofficial native macOS app and command-line tool for the **AJAZZ AK35i V3 Max** tri-mode mechanical keyboard with a screen. The vendor's configuration software only runs on Windows; this app brings most of its settings to the Mac: RGB lighting, per-key colours, key remapping, macros, the screen clock, screen GIF upload, battery level, and the driver's own realtime effects and music visualiser. It works over USB and the 2.4G receiver; over Bluetooth it reads the battery.

Independent community project, not affiliated with, endorsed by, or supported by AJAZZ. See [NOTICE.md](NOTICE.md).

![AK35i Control Center overview page: connection, firmware version and vendor HID channels](docs/images/control-center.png)

## Features

| Feature | App page | CLI example |
|---|---|---|
| Screen clock sync (UTC+8 or the Mac's time zone) | Clock | `ak35i time sync --utc8 --apply` |
| Lighting: 20 modes with brightness, speed, direction and colour | Lighting | `ak35i light set --mode 1 --color 00FF00 --apply` |
| Per-key colours (read back from the keyboard) | Per-key | `ak35i keys set Esc=FF0000 --apply` |
| System settings: disable Win / Alt+Tab / Alt+F4, sleep, key response, Fn switch | System | `ak35i system set` |
| Key remapping (base and Fn layers, media and mouse keys) | Keymap | `ak35i keymap set CapsLock=Esc --apply` |
| Macros, bound to a key as `macro:N` | Macros | `ak35i macro set "Cmd+Space, 100ms, A" --apply` |
| Screen GIF page upload (picture or GIF, 16:9) | Screen | `ak35i screen set picture.gif --apply` |
| Realtime effects: the Windows driver's eight originals, streamed from the Mac | Realtime | `ak35i live wave` |
| Music visualiser: the driver's algorithm on what the Mac is playing | Realtime | `ak35i live music` |
| Battery (2.4G or Bluetooth) and firmware version | Battery, Overview | `ak35i battery`, `ak35i status` |

The screen clock is verified; the other writes are experimental. See [protocol status](docs/PROTOCOL_STATUS.md).

## Compatibility

| Item | Details |
|---|---|
| Keyboard | AJAZZ AK35i V3 Max tri-mode with screen, USB VID:PID `0C45:8009`, verified on firmware V1.30 |
| Connection | USB: every feature. 2.4G receiver: everything except per-key realtime effects and reading per-key colours back. Bluetooth: battery only (the keyboard ignores settings there, but settings written through the receiver or cable stay) |
| macOS | 13 or later, universal (Intel and Apple Silicon); the music visualiser needs 14.2 or later |
| Privacy | No account, telemetry or upload; device serial numbers are never shown, stored or written |

## Install

1. Download the latest `universal.dmg` and its `.sha256` file from [Releases](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases/latest).
2. Drag **AK35i Control Center** into Applications.
3. The app is not signed with an Apple Developer ID or notarized, so macOS blocks the first launch. Click **Done**, open **System Settings › Privacy & Security**, click **Open Anyway** next to AK35i Control Center and confirm with your password. You only need to do this once. On macOS 14 and earlier you can also Control-click the app and choose **Open**.
4. Connect the keyboard by cable (USB position) or through the 2.4G receiver and check the Overview page.

## FAQ

**Does the AJAZZ AK35i V3 Max work on a Mac?**
It types as soon as it is plugged in. The vendor's settings software is Windows-only; this app provides most of those settings on macOS.

**How is it different from the official Windows driver?**
Its packets are reproduced from the driver, and it only sends commands the driver sends. It does not update firmware or factory-reset the keyboard; Ambilight and settings export/import are not implemented yet.

**Does it work over 2.4G and Bluetooth?**
Most settings work through the 2.4G receiver. Over Bluetooth the keyboard ignores settings commands, so only the battery can be read.

**Can it break my keyboard?**
It does not guess commands or touch firmware. Lighting can be restored with the keyboard's shortcuts, and key remapping and macros can be reset or cleared; a screen upload replaces the GIF page, while the factory boot animation is not affected. See the [safety model](docs/SAFETY_MODEL.md).

**Does it support other AJAZZ keyboards?**
It has only been verified on the AK35i V3 Max (USB `0C45:8009`). Models such as the AK820 or AK35i V3 Pro may use different protocols; do not write to them with this app.

## Build from source

```zsh
git clone https://github.com/Ike-li/ak35i-v3-max-macos-control-center.git
cd ak35i-v3-max-macos-control-center
swift test --disable-sandbox
./Packaging/build-app.sh
```

`./Packaging/create-dmg.sh` builds the universal DMG. See the [getting-started guide](docs/GETTING_STARTED.md), [Chinese and English manual entry points](docs/manuals/), [troubleshooting](docs/TROUBLESHOOTING.md), [protocol status](docs/PROTOCOL_STATUS.md) and the [reverse-engineering notes](docs/STATIC_REVERSING.md) (Chinese) for detail.

## Scope and safety

Basic lighting has packet-to-acknowledgement-to-effect-to-persistence evidence from the physical keyboard, but only the static and stream modes have been checked by eye, so it stays experimental; the keyboard's own `Fn+\|` shortcuts restore it. System settings, key remapping and macros also have hardware evidence and are marked experimental; the keyboard cannot read them back, but each can be rewritten to defaults or cleared. Screen GIF page upload is verified on the keyboard as well: it survives a power cycle and `Fn+PrtSc` shows it (press again to return), but the previous GIF page cannot be restored once overwritten (the factory boot animation is not affected). Battery is read through the 2.4G receiver or Bluetooth, both verified on the keyboard; it is not reported over wired USB (the Windows driver and firmware analysis agree). The app does not guess opcodes or send unverified vendor commands.

This is an independent community project and is not affiliated with AJAZZ. It does not distribute vendor drivers, firmware, images, GIFs, or source code; to reproduce the driver's realtime effects and key positions it does include small numeric tables and key-layout data taken from the driver (see NOTICE.md). See [NOTICE.md](NOTICE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
