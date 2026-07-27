# AK35I V3 Max Windows 驱动溯源记录

记录日期：2026-07-26

## 设备与选择依据

- 公共版本不记录任何实体设备序列号，也不以序列号末尾作为型号或驱动匹配证据。
- 官方索引没有公开“序列号末尾 → 产品条码”的对应表，因此不把用户设备序列号当作可独立验证的条码匹配结果。
- AJAZZ 官方驱动索引直接列有完全同名型号的归档：`AJAZZ_AK35I MAX V3_Tripe mode RGB with screen_keyboard driver_V1.0.0.zip`。这是选择该归档的依据，而不是名称相近的单模 V3、V3 Pro 或 V4 包。

## 归档

- 官方下载页：[AJAZZ Client Side Driver](https://www.a-jazz.com/en/h-col-159.html)
- 原始官方文件地址：`https://download.s21i.co99.net/25789609/0/0/ABUIABBPGAAg_onDuAYo6KOpmwI.zip?f=AJAZZ_AK35I%20MAX%20V3_Tripe%20mode%20RGB%20with%20screen_keyboard%20driver_V1.0.0.zip&v=1729152251`
- 本地留存：`artifacts/vendor/AJAZZ_AK35I_MAX_V3_Tripe_mode_RGB_with_screen_keyboard_driver_V1.0.0.zip`（不纳入 Git）
- 归档大小：28,924,504 bytes
- 归档 SHA-256：`045de166d10358d12586c574b59cef584df0be2b62ebb91fdffb66c808e07ca5`

## 静态校验结果

- `unzip -t` 已通过，没有压缩数据错误。
- 归档包含一个 Windows `PE32 GUI / Intel 80386` 可执行文件；未在 macOS 上启动、安装或执行。
- 内部可执行文件 SHA-256：`994173b09c8f40846b427dd6baa6e565f23a76e335953b3cd80e87ec0697e738`。
- 内部文件名显示为 `AK35I PRO V3`（受原始压缩包中文编码影响，部分字符不可读）。这与外层“AK35I MAX V3”官方归档名不一致，表明厂商可能复用了同一个控制程序。它不影响“官方索引存在精确 MAX V3 条目”的事实，但在实体 Windows 上必须先确认软件能识别本机 `0C45:8009`，再开始 USB 抓包。

## 接下来

该归档仅作为 Windows 抓包的受控来源，不作为 macOS 写入协议的证据。待有实体 Windows 后，先用 USB 模式确认识别键盘；随后按 [抓包工作单](CAPTURE_WORKSHEET.md) 对每个功能做“基线 → 单项修改 → 保存 → 恢复”的独立抓包。
