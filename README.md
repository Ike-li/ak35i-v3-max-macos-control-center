# AK35i Control Center for macOS

[![CI](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/actions/workflows/ci.yml/badge.svg)](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Ike-li/ak35i-v3-max-macos-control-center?display_name=tag&include_prereleases&sort=semver)](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases)
[![License](https://img.shields.io/github/license/Ike-li/ak35i-v3-max-macos-control-center)](LICENSE)

[English](README.en.md) · [下载](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) · [快速上手](docs/GETTING_STARTED.md) · [中英文说明书](docs/manuals/) · [故障排查](docs/TROUBLESHOOTING.md) · [功能状态](docs/PROTOCOL_STATUS.md)

面向 **AJAZZ AK35i V3 Max** 的原生 macOS 控制中心与 CLI。项目坚持“先验证、后写入”：目前开放已实机验证的屏幕时钟，以及实验性的基础灯效（灯光页或 CLI）、自定义单键灯光、系统设置、改键、宏、屏幕 GIF 页上传，以及由电脑推送的实时灯效和音乐律动；其他私有协议功能默认锁定。

> Independent community project. It is not affiliated with, endorsed by, or supported by AJAZZ. See [NOTICE.md](NOTICE.md).

## 先看这里

| 项目 | 当前状态 |
|---|---|
| 已验证硬件 | USB VID:PID `0C45:8009` 的 AK35i V3 Max |
| 已验证写入 | 屏幕时钟：UTC+8 或 Mac 当前时区 |
| 实验性写入 | 基础灯效：20 种模式及亮度、速度、方向、颜色，控制中心“灯光”页或 `ak35i light set`；自定义单键颜色：“单键灯光”页或 `ak35i keys set Esc=FF0000`；系统设置（禁用 Win / Alt+Tab / Alt+F4、休眠、响应时间、Fn 开关）：“系统设置”页或 `ak35i system set`；改键（普通层与 Fn 层）：“改键”页或 `ak35i keymap set CapsLock=Esc`；宏：“宏”页或 `ak35i macro set "Cmd+Space, 100ms, A"`，再用 `macro:N` 绑定到键；实时灯效（Windows 驱动原版的 8 种效果）与驱动原版的音乐律动（电脑逐帧推送，不写入键盘）：“实时灯效”页或 `ak35i live wave`、`ak35i live music`；屏幕 GIF 页：“屏幕”页或 `ak35i screen set 图片.gif` |
| 连接要求 | USB 有线模式；2.4G 接收器下也能同步时钟、读电量、设置灯效、系统设置、单键颜色、改键、宏、音乐律动（柱状图）和上传屏幕，只有逐键实时灯效和读回单键颜色需要数据线；蓝牙下只能读电量（键盘在蓝牙下不接受设置命令，用接收器或数据线写入的设置切回蓝牙后仍保留） |
| 支持系统 | macOS 13+，发布包同时支持 Intel 与 Apple Silicon；音乐律动需要 macOS 14.2+ |
| 只读 | 电量：经 2.4G 接收器或蓝牙读取，“电量”页或 `ak35i battery`；有线 USB 下键盘不提供 |
| 网络与隐私 | 无账号、遥测或上传；不显示、保存或写入设备序列号 |

## 下载安装

1. 从 [Releases](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) 下载最新的 `universal.dmg` 与同名 `.sha256` 校验文件。
2. 打开 DMG，将 **AK35i Control Center** 拖到“应用程序”。
3. 首次打开：应用没有 Apple 开发者签名和公证，macOS 会阻止。点“完成”，再到“系统设置 › 隐私与安全性”点“仍要打开”并输入登录密码，只需一次。macOS 14 及更早版本也可以按住 Control 点按应用，选“打开”。
4. 用数据线（USB 档）或 2.4G 接收器连接键盘，在“概览”页确认已连接。

完整步骤、连接方式对照、权限说明与 CLI 用法见 [快速上手](docs/GETTING_STARTED.md)。

## 为什么功能没有全开？

屏幕时钟已经经过真机验证。基础灯效的写入序列已在实机上取得“报文 → 设备确认 → 效果 → 重连后保留”的证据，但目前只看过静态恒亮和川流不息两种模式，因此标为实验性；写错时可以用键盘的 `Fn+\|` 等快捷键恢复。系统设置、改键和宏同样有实机证据并标为实验性，键盘读不回这三项，但都能写回默认值或清空。屏幕 GIF 页上传也已实机验证，断电后保留，按 `Fn+PrtSc` 查看、再按返回主页面；但覆盖后原内容无法恢复（出厂开机动画不受影响）。电量经 2.4G 接收器或蓝牙读取，都已实机验证；有线 USB 下键盘不提供（Windows 驱动和固件分析一致）。程序不会猜测 opcode，也不会盲发写入。

这是刻意的安全边界，不是界面遗漏。详见 [功能与协议状态](docs/PROTOCOL_STATUS.md) 与 [安全模型](docs/SAFETY_MODEL.md)。

## 从源码构建

需要 Xcode/Swift 6 与 macOS 13+：

```zsh
git clone https://github.com/Ike-li/ak35i-v3-max-macos-control-center.git
cd ak35i-v3-max-macos-control-center

swift test --disable-sandbox
./Packaging/build-app.sh
open "dist/AK35i Control Center.app"
```

创建本地 DMG：

```zsh
./Packaging/create-dmg.sh
```

`create-dmg.sh` 生成 Intel 与 Apple Silicon 通用的 DMG。本地构建和发布包都是 ad-hoc 签名，没有经过 Apple 公证，首次打开的方法见上文。

## 文档导航

| 你想做什么 | 文档 |
|---|---|
| 首次安装、同步时间或使用 CLI | [快速上手](docs/GETTING_STARTED.md) |
| 区分型号，查看 V3 Max 中英文说明书入口与快捷键 | [中英文说明书](docs/manuals/) |
| 处理 Gatekeeper、找不到设备等问题 | [故障排查](docs/TROUBLESHOOTING.md) |
| 了解已验证与锁定功能 | [功能与协议状态](docs/PROTOCOL_STATUS.md) |
| 理解为何不猜测私有 HID 命令 | [安全模型](docs/SAFETY_MODEL.md) |
| 参与开发或提交协议证据 | [贡献指南](CONTRIBUTING.md) |
| 维护发布包 | [发布流程](docs/RELEASING.md) |
| 驱动来源、静态逆向记录 | [技术文档](docs/) |

## 参与贡献

欢迎提交 bug、文档和可复现的协议证据。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。请勿在 issue、日志、截图或抓包中公开设备序列号、私人图片或未脱敏的个人路径。

## 许可与声明

代码以 [MIT License](LICENSE) 发布。型号、商标和第三方材料边界见 [NOTICE.md](NOTICE.md)。本仓库不包含、分发或修改厂商 Windows 驱动、固件、图片、GIF 或源码；为复现驱动的实时灯效和键位，收录了从驱动中取出的少量数值表和键位数据，详见 NOTICE。
