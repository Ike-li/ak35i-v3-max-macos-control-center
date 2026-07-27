# 贡献指南

感谢你帮助完善 AK35i Control Center。项目的首要原则是：**未知私有 HID 命令不写入真机**。

## 适合贡献的内容

- macOS UI、可访问性、文档和测试改进。
- 已被复现的设备发现或校时问题。
- 经过脱敏的 Windows USBPcap/Wireshark 证据，用于验证一个尚未开放的功能。
- 可复现的构建、打包或 Gatekeeper 问题。

## 提交代码前

```zsh
swift test --disable-sandbox
./Packaging/build-app.sh
```

- 保持改动最小；协议写入改动必须先增加失败测试。
- 不要加入 `artifacts/`、`dist/`、厂商驱动、固件或示例素材。
- 不要添加设备序列号、个人路径、截图中的私人内容、令牌或账号信息。
- 对每个新的写入命令，说明报文来源、应答、持久化和恢复验证。

## 提交抓包证据

请遵循 [抓包工作单](docs/CAPTURE_WORKSHEET.md)。每项功能需要“基线 → 只改一项 → 保存 → 恢复基线”的独立记录。提交前移除序列号、个人图片/GIF 和无关 USB 设备数据。

## 提交 issue

请使用对应模板，并提供 macOS 版本、应用版本、连接模式、VID:PID、复现步骤和已脱敏的日志。不要公开敏感报告；见 [SECURITY.md](SECURITY.md)。
