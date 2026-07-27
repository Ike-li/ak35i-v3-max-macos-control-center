# AK35i V3 Max 控制中心（macOS）

这是一个原生 macOS 控制中心和 CLI，不安装内核驱动。当前版本只会向键盘写入已经在真机验证过的屏幕时钟报文。

> 本项目是独立的社区工具，与 AJAZZ 没有隶属、授权或合作关系；不包含、分发或复用任何厂商驱动、固件、图片、GIF 或源码。

## 使用

- 双击 `dist/AK35i Control Center.app` 打开图形界面。
- 命令行程序位于 `dist/ak35i`，或 `dist/AK35i Control Center.app/Contents/MacOS/ak35i`。
- 若 macOS 首次阻止未公证的本地应用，在 Finder 中按住 Control 点击应用并选择“打开”一次；正式分发前需 Developer ID 签名和公证。

```zsh
APP="./dist/ak35i"

"$APP" status
"$APP" time sync --utc8 --apply
"$APP" preview time --utc8
"$APP" autosync status
"$APP" autosync enable --utc8
"$APP" autosync disable
```

自动校时仅在显式启用后创建当前用户的 LaunchAgent；登录时与每 24 小时尝试一次。键盘不在 USB 模式时不会写入。

## 从源码构建

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --disable-sandbox
```

源代码位于 `Sources/`，打包用的应用信息在 `Packaging/Info.plist`。`dist/` 保存当前构建的交付物，不纳入 Git。

生成可双击打开的应用：

```zsh
./Packaging/build-app.sh
open "dist/AK35i Control Center.app"
```

打包脚本会从 Release 构建生成新的应用包、清理会破坏签名的 Finder 元数据、ad-hoc 签名并校验。若已有旧版本，会移动为带时间戳的备份而非删除。

创建本地 DMG：

```zsh
./Packaging/create-dmg.sh
```

当前 DMG 是本地 ad-hoc 签名构建，尚未经过 Apple Developer ID 签名或公证；首次运行可能需要在 Finder 中按住 Control 点击应用并选择“打开”。

## 兼容性与隐私

- 当前发布构建为 Apple Silicon (`arm64`)，需要 macOS 13 或更高版本；键盘须以 USB 有线模式连接。
- 已实机验证的设备为 USB VID:PID `0C45:8009`。屏幕 GIF、RGB、板载改键、宏和电量读取仍不会写入设备。
- 应用不实现网络上传、遥测或账号登录，也不会显示、保存或写入设备序列号。
- 自动校时仅在显式启用后创建当前用户的 LaunchAgent；日志仅保存在当前用户的 `~/Library/Logs/`。

## 发布者检查单

公开发布前，请勿使用 `git add -f` 以绕过 `.gitignore`。该规则特意排除了本机构建产物、厂商驱动和静态逆向载荷。

正式面向其他用户分发前，建议以 Apple Developer ID 签名并完成公证；公开仓库提供的是可复现源码与本地 DMG 打包脚本，不承诺绕过 Gatekeeper。

## 当前已验证

- USB 有线设备识别：VID:PID `0C45:8009`。
- 64 字节 Feature 控制通道：usage `0xFF13:0x0001`。
- 4 KiB 屏幕数据通道：usage `0xFF68:0x0061`。
- UTC+8 或 Mac 当前时区的屏幕时钟同步。

## 安全锁定的功能

电量、RGB、GIF/图片、板载改键和宏尚未有 AK35I V3 Max 的 Windows 抓包证据，因此控制中心只显示状态，不会写入。`backup` 和 `restore` 不会伪造成功；例如屏幕内容无法从硬件读出前，不允许声称已备份。

正确的 Windows 驱动归档已从 AJAZZ 官方站点留存并做过完整性校验；其来源、哈希与已知边界见 [驱动溯源记录](docs/DRIVER_PROVENANCE.md)。下一阶段请按 [抓包工作单](docs/CAPTURE_WORKSHEET.md) 在实体 Windows 上录制该 V3 Max 驱动的 USB 报文。

Windows 归档的离线静态逆向记录见 [静态逆向记录](docs/STATIC_REVERSING.md)。它用于缩小协议探索范围，但不会绕过每项功能的真机抓包验证。
