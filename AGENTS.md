# AGENTS.md

Native macOS app and CLI (`ak35i`) for the AJAZZ AK35i V3 Max keyboard. Swift 6, SwiftPM, SwiftUI; one executable target.

## Layout

- `Sources/AK35iClockSync/`: app, CLI and protocol encoders. The same binary opens the app when launched from Finder and runs the CLI when given arguments.
- `Tests/AK35iClockSyncTests/`: XCTest.
- `Packaging/`: `Info.plist`, `build-app.sh` (app bundle), `create-dmg.sh` (universal DMG).
- `docs/`: protocol status, safety model and reverse-engineering notes, mostly in Chinese.
- `.github/workflows/`: `ci.yml` runs the tests; `release.yml` builds and drafts a release when a `v*` tag is pushed.

## Build and test

```zsh
swift test --disable-sandbox          # needs Xcode; set DEVELOPER_DIR if only the Command Line Tools are selected
zsh Packaging/build-app.sh            # dist/AK35i Control Center.app
zsh Packaging/create-dmg.sh           # dist/AK35i-Control-Center-<version>-universal.dmg
```

CI compiles with Swift 6.1 (Xcode 16). Newer compilers accept long expressions that 6.1 cannot type-check in time, so keep expressions short and typed.

## Rules

- Send only packets reproduced byte for byte from the vendor's Windows driver (see `docs/SAFETY_MODEL.md`). Never probe unknown commands.
- Never implement firmware update, DFU or factory reset, and never write to the Bluetooth `FEE0` / `FEE1` service, which is the module's over-the-air update channel.
- Device writes need explicit confirmation: a dialog in the app, `--apply` on the CLI.
- Add a failing test before changing a protocol encoder.
- Do not commit vendor binaries, firmware, USB captures, device serial numbers, personal paths or tokens.
