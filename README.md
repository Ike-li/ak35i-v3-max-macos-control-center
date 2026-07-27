# AK35i Control Center for macOS

[![CI](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/actions/workflows/ci.yml/badge.svg)](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Ike-li/ak35i-v3-max-macos-control-center?display_name=tag&include_prereleases&sort=semver)](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases)
[![License](https://img.shields.io/github/license/Ike-li/ak35i-v3-max-macos-control-center)](LICENSE)

[English](README.en.md) · [下载](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) · [快速上手](docs/GETTING_STARTED.md) · [故障排查](docs/TROUBLESHOOTING.md) · [功能状态](docs/PROTOCOL_STATUS.md)

面向 **AJAZZ AK35i V3 Max** 的原生 macOS 控制中心与 CLI。项目坚持“先验证、后写入”：目前只允许向已实机验证的 USB HID 时钟通道写入时间；所有其他私有协议功能默认锁定。

> Independent community project. It is not affiliated with, endorsed by, or supported by AJAZZ. See [NOTICE.md](NOTICE.md).

## 先看这里

| 项目 | 当前状态 |
|---|---|
| 已验证硬件 | USB VID:PID `0C45:8009` 的 AK35i V3 Max |
| 已验证写入 | 屏幕时钟：UTC+8 或 Mac 当前时区 |
| 连接要求 | USB 有线模式；蓝牙与 2.4G 不提供控制承诺 |
| 支持系统 | 当前发布包为 Apple Silicon (`arm64`)、macOS 13+ |
| 未开放写入 | RGB、图片/GIF、改键、宏、电量读取 |
| 网络与隐私 | 无账号、遥测或上传；不显示、保存或写入设备序列号 |

## 下载并同步时间

1. 从 [Releases](https://github.com/Ike-li/ak35i-v3-max-macos-control-center/releases) 下载最新的 `arm64.dmg` 与同名 `.sha256` 校验文件。
2. 确认键盘通过数据线连接，且已切到 USB 模式。
3. 打开 DMG，将 **AK35i Control Center** 拖到“应用程序”。首次若被 Gatekeeper 阻止，按住 Control 点击应用并选择“打开”。
4. 在控制中心的“时钟”页选择 `UTC+08:00（北京时间）` 或 Mac 当前时区，点击“立即同步”。

完整步骤、校验命令与 CLI 用法见 [快速上手](docs/GETTING_STARTED.md)。

## 为什么功能没有全开？

屏幕时钟已经经过真机验证。RGB、屏幕图片/GIF、板载改键、宏和电量读取尚未取得每个功能的“操作 → 报文 → 应答 → 重连持久化”完整证据，因此程序不会猜测 opcode 或盲发写入。

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

本地构建与当前预览发布均为 ad-hoc 签名，尚未 Apple 公证。正式稳定分发前仍需 Developer ID 签名与公证。

## 文档导航

| 你想做什么 | 文档 |
|---|---|
| 首次安装、同步时间或使用 CLI | [快速上手](docs/GETTING_STARTED.md) |
| 处理 Gatekeeper、找不到设备等问题 | [故障排查](docs/TROUBLESHOOTING.md) |
| 了解已验证与锁定功能 | [功能与协议状态](docs/PROTOCOL_STATUS.md) |
| 理解为何不猜测私有 HID 命令 | [安全模型](docs/SAFETY_MODEL.md) |
| 参与开发或提交抓包证据 | [贡献指南](CONTRIBUTING.md) |
| 维护发布包 | [发布流程](docs/RELEASING.md) |
| 驱动来源、抓包工作单、静态逆向记录 | [技术文档](docs/) |

## 参与贡献

欢迎提交 bug、文档和可复现的抓包证据。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。请勿在 issue、日志、截图或抓包中公开设备序列号、私人图片或未脱敏的个人路径。

## 许可与声明

代码以 [MIT License](LICENSE) 发布。型号、商标和第三方材料边界见 [NOTICE.md](NOTICE.md)。本仓库不包含、分发或修改厂商 Windows 驱动、固件、图片、GIF 或源码。
