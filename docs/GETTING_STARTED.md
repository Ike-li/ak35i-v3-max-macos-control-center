# 快速上手

本教程面向第一次使用 AK35i Control Center 的 macOS 用户。

## 准备

- macOS 13 或更高版本，Intel 或 Apple Silicon 均可；音乐律动需要 macOS 14.2 或更高版本。
- AJAZZ AK35i V3 Max 三模带屏版。用数据线连接时，系统里的 USB VID:PID 为 `0C45:8009`。

## 1. 下载并校验

从 [GitHub Releases](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) 下载 `AK35i-Control-Center-<版本>-universal.dmg` 和同名的 `.sha256` 文件，在下载目录运行：

```zsh
shasum -a 256 -c AK35i-Control-Center-*-universal.dmg.sha256
```

显示 `OK` 表示文件完整。

## 2. 安装与首次打开

1. 打开 DMG，把 **AK35i Control Center** 拖到“应用程序”。
2. 双击打开。本项目没有 Apple 开发者签名，也没有经过 Apple 公证，macOS 会提示无法验证开发者或无法检查恶意软件，先点“完成”。
3. 打开“系统设置 › 隐私与安全性”，在“安全性”部分找到 AK35i Control Center，点“仍要打开”，输入登录密码后再确认一次。之后就能正常打开。

macOS 14 及更早版本也可以在 Finder 中按住 Control 点按应用，选择“打开”。不需要关闭 Gatekeeper，也不要运行来路不明的命令。

## 3. 连接键盘

| 连接方式 | 可用功能 |
|---|---|
| USB 数据线（键盘拨到 USB 档） | 全部功能，但键盘在有线下不提供电量 |
| 2.4G 接收器 | 时钟、电量、灯光、系统设置、单键颜色、改键、宏、音乐律动（柱状图）、屏幕上传；不能做逐键实时灯效，也不能读回单键颜色 |
| 蓝牙 | 只能读电量；用接收器或数据线写入的设置切回蓝牙后仍然保留 |

打开应用的“概览”页，确认连接方式和固件版本。

## 4. 常用操作

- **时钟**：在“时钟”页选择 `UTC+08:00（北京时间）` 或 Mac 当前时区，点“立即同步”。
- **灯光、单键灯光、系统设置、改键、宏、屏幕**：写入前都会弹出确认。改键、宏和屏幕读不回来，确认前请看清提示。屏幕上传会覆盖 GIF 页，原内容无法恢复，出厂开机动画不受影响。
- **实时灯效与音乐律动**：由 Mac 逐帧推送，键盘不保存；离开页面或点“停止”后，键盘立即恢复原来的灯效。

各功能的验证程度见 [功能与协议状态](PROTOCOL_STATUS.md)。

## 5. 系统权限

- **蓝牙**：只在键盘用蓝牙连接、读取电量时请求。
- **系统录音**：只在使用音乐律动时请求。声音只用来计算频谱，不会被录制或保存。

## 命令行（可选）

命令行程序就在应用包里：

```zsh
APP="/Applications/AK35i Control Center.app/Contents/MacOS/ak35i"

"$APP" --help
"$APP" status
"$APP" time sync --utc8 --dry-run
"$APP" time sync --utc8 --apply
```

设置类命令默认只预览，加 `--apply` 才会写入键盘。
