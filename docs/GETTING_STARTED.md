# 快速上手

本教程面向第一次使用 AK35i Control Center 的 macOS 用户。目标是在不触碰未知键盘功能的前提下，将屏幕时钟同步到正确时区。

## 准备

- Apple Silicon Mac，macOS 13 或更高版本。
- AK35i V3 Max，已用数据线连接并切到 USB 模式。
- 最新 [GitHub Release](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) 中的 `arm64.dmg` 和 `.sha256`。

## 1. 校验下载（建议）

在下载目录运行：

```zsh
shasum -a 256 AK35i-Control-Center-*-arm64.dmg
cat AK35i-Control-Center-*-arm64.dmg.sha256
```

两行中的 SHA-256 值应相同。

## 2. 安装并首次打开

双击 DMG，将 **AK35i Control Center** 拖到“应用程序”。预览版尚未 Apple 公证；若首次启动被阻止，在 Finder 中按住 Control 点击应用，再选择“打开”。

## 3. 确认设备

打开应用的“概览”页，应看到：

- 状态为“USB 有线已连接”；
- 产品为 `USB KEYBOARD`；
- “时钟与设置控制”和“屏幕数据传输”两条厂商 HID 通道。

若不是这些结果，请不要尝试写入，转到 [故障排查](TROUBLESHOOTING.md)。

## 4. 同步时钟

1. 打开“时钟”页。
2. 选择 `UTC+08:00（北京时间）`，或选择 Mac 当前时区。
3. 点击“立即同步”，在确认对话框中点击“同步”。
4. 查看键盘屏幕。需要时切换连接模式后再次确认时间保留。

## CLI（可选）

DMG 中的命令行程序位于应用包内：

```zsh
APP="/Applications/AK35i Control Center.app/Contents/MacOS/ak35i"

"$APP" status
"$APP" time sync --utc8 --dry-run
"$APP" time sync --utc8 --apply
```

`--dry-run` 不会打开或写入键盘。请只在状态中出现已验证时钟通道后使用 `--apply`。
