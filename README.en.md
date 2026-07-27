# AK35i Control Center for macOS

[中文](README.md) · [Download](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) · [Getting started](docs/GETTING_STARTED.md) · [Protocol status](docs/PROTOCOL_STATUS.md)

A safety-first native macOS control center and CLI for the AJAZZ AK35i V3 Max. The project enables only writes that have been verified on the physical device; all unknown vendor-HID writes remain locked.

## At a glance

| Item | Status |
|---|---|
| Verified hardware | AK35i V3 Max, USB VID:PID `0C45:8009` |
| Verified write | Screen clock sync: UTC+8 or the Mac system time zone |
| Connection | USB wired mode only |
| Release build | Apple Silicon (`arm64`), macOS 13+ |
| Deliberately locked | RGB, image/GIF upload, remapping, macros, battery reads |
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

See the [Chinese getting-started guide](docs/GETTING_STARTED.md), [troubleshooting](docs/TROUBLESHOOTING.md), and [protocol status](docs/PROTOCOL_STATUS.md) for detail.

## Scope and safety

RGB, display upload, key mapping, macros, and battery reads need action-to-packet-to-response-to-persistence evidence before they can be enabled. The app does not guess opcodes or send unverified vendor commands.

This is an independent community project and is not affiliated with AJAZZ. It does not distribute vendor drivers, firmware, images, GIFs, or source code. See [NOTICE.md](NOTICE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
