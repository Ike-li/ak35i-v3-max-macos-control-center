# AK35i Control Center for macOS

[中文](README.md) · [Download](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) · [Getting started](docs/GETTING_STARTED.md) · [Chinese and English manuals](docs/manuals/) · [Protocol status](docs/PROTOCOL_STATUS.md)

A safety-first native macOS control center and CLI for the AJAZZ AK35i V3 Max. The project enables only writes backed by physical-device evidence: the verified screen clock and experimental basic lighting (Lighting page or CLI), per-key colors, system settings, key remapping, macros, screen GIF uploads, and realtime effects and music visualisation streamed from the Mac. All other vendor-HID writes remain locked.

## At a glance

| Item | Status |
|---|---|
| Verified hardware | AK35i V3 Max, USB VID:PID `0C45:8009` |
| Verified write | Screen clock sync: UTC+8 or the Mac system time zone |
| Experimental write | Basic lighting: 20 modes with brightness, speed, direction and color from the Lighting page or `ak35i light set`; per-key colors from the Per-key page or `ak35i keys set Esc=FF0000`; system settings (disable Win / Alt+Tab / Alt+F4, sleep, key response, Fn switch) from the System page or `ak35i system set`; key remapping (base and Fn layers) from the Keymap page or `ak35i keymap set CapsLock=Esc`; macros from the Macros page or `ak35i macro set "Cmd+Space, 100ms, A"`, bound to a key with `macro:N`; realtime effects and music visualisation streamed from the Mac (nothing stored on the keyboard) from the Realtime page or `ak35i live wave` / `ak35i live music`; screen GIF page from the Screen page or `ak35i screen set picture.gif` |
| Connection | USB wired mode; through the 2.4G receiver the clock, battery, lighting and system settings work so far, the rest is being ported; no Bluetooth (the keyboard firmware ignores settings commands over Bluetooth) |
| Release build | Apple Silicon (`arm64`), macOS 13+ |
| Read only | Battery, only through the 2.4G receiver, from the Battery page or `ak35i battery`; the keyboard does not report it over wired USB |
| Privacy | No account, telemetry, upload, or device serial-number display/persistence |

## Quick start

1. Download the latest `arm64.dmg` and its `.sha256` file from [Releases](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases).
2. Connect the keyboard by cable and switch it to USB mode.
3. Drag **AK35i Control Center** into Applications. If Gatekeeper blocks the first launch, Control-click the app and choose **Open**.
4. Open **Clock**, select a time zone, and choose **Sync now**.

The DMG is ad-hoc signed and is not notarized yet. It is a preview release, not a claim of broad hardware compatibility.

## Build from source

```zsh
git clone https://github.com/Ike-li/ak35i-v3-max-macos-control-center.git
cd ak35i-v3-max-macos-control-center
swift test --disable-sandbox
./Packaging/build-app.sh
```

See the [getting-started guide](docs/GETTING_STARTED.md), [Chinese and English manual entry points](docs/manuals/), [troubleshooting](docs/TROUBLESHOOTING.md), and [protocol status](docs/PROTOCOL_STATUS.md) for detail.

## Scope and safety

Basic lighting has packet-to-acknowledgement-to-effect-to-persistence evidence from the physical keyboard, but only the static and stream modes have been checked by eye, so it stays experimental; the keyboard's own `Fn+\|` shortcuts restore it. System settings, key remapping and macros also have hardware evidence and are marked experimental; the keyboard cannot read them back, but each can be rewritten to defaults or cleared. Screen GIF page upload is verified on the keyboard as well: it survives a power cycle and `Fn+PrtSc` shows it (press again to return), but the previous GIF page cannot be restored once overwritten (the factory boot animation is not affected). Battery can only be read through the 2.4G receiver, which is verified on the keyboard; it is not reported over wired USB (the Windows driver and firmware analysis agree). The app does not guess opcodes or send unverified vendor commands.

This is an independent community project and is not affiliated with AJAZZ. It does not distribute vendor drivers, firmware, images, GIFs, or source code. See [NOTICE.md](NOTICE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
