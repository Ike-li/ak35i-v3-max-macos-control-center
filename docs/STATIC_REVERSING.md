# Windows 驱动静态逆向记录

记录日期：2026-07-26。所有操作均为离线读取、解压或元数据检查；没有在 macOS、虚拟机或键盘上执行 Windows 驱动。

## 已确认

- 分析对象为 `artifacts/vendor/AJAZZ_AK35I_MAX_V3_Tripe_mode_RGB_with_screen_keyboard_driver_V1.0.0.zip`，归档 SHA-256 见 [驱动溯源记录](DRIVER_PROVENANCE.md)。
- 归档中的单一文件是 29,483,325 bytes 的 Windows `PE32 GUI / Intel 80386` 可执行文件，SHA-256：`994173b09c8f40846b427dd6baa6e565f23a76e335953b3cd80e87ec0697e738`。
- 它是 Inno Setup 6.1.0 安装器，而不是键盘控制程序本体：可见 `Inno Setup Setup Data (6.1.0) (u)`、`SetupLdr.exe` 和 LZMA 解压实现；PE 映像本身约 0.9 MB，余下约 28 MB 是安装载荷。
- PE Security Directory 为空，未发现内嵌 Authenticode 签名目录。
- 外层安装器的直接导入不含 `hid.dll`、`setupapi.dll` 或 `winusb.dll`。这只能说明引导器本身不直接控制设备，不能推断内部控制程序不使用 HID。

## 已解出的载荷

使用一次性 Alpine 容器内的 `innoextract` 解出了 145 个文件；驱动 ZIP 与安装器均只读挂载，容器内没有启动任何 Windows 可执行文件。提取内容位于被 Git 忽略的 `artifacts/static-analysis/extracted/`。

- 真实控制程序：`app/DeviceDriver.exe`，SHA-256 `230931cdd8f2017707fbd2068aaf73dac239eb2e5f46490369ad306d1210c3cc`。安装器内两个同名条目逐字节相同。
- UI 库：`app/mui.dll`，SHA-256 `e9a2a9ec1c5f9682ff1cd1904bcf2fcd2fe21f124bee048297e8ade1496028ae`。
- 内含两个固件更新器（80 键和 98 键变体）；它们保持未执行、未解包、未分析，且永不纳入本项目功能范围。
- 包内还留有 `AJAZZ AK820Pro` 示例 GIF，说明这套控制程序是多型号共用平台；不能把所有资源都当作本机 V3 Max 的能力证明。

## 设备与传输层证据

- `config.xml` 的 USB 设备条目精确为 `VID_0C45&PID_8009&MI_00`、产品名 `USB KEYBOARD`；这与本机已验证设备一致。配置还列出 2.4G 接收器 `0C45:FDFD`，但未在本机验证。
- 控制程序导入 `SETUPAPI.dll`、`CreateFile`、`ReadFile`、`WriteFile`、`DeviceIoControl`，并动态解析 `HidD_GetFeature`、`HidD_SetFeature`、`HidP_GetCaps` 等 `hid.dll` API。
- 程序内直接构造标准 HID class GUID，并通过 `DeviceIoControl(0xB0192)` 获取报告描述符。
- `HidD_GetFeature` 的调用明确使用 `0x41`（65）字节缓冲区。这与 macOS 实测“64 字节 Feature 载荷 + 1 个报告 ID”的时钟控制通道相符。
- Output 传输封装会读取 HID caps 中的 Output 报告长度、按需补零，然后以异步 `WriteFile` 发送；它不是普通文件写入。
- 已定位到一个 33 字节逻辑 Output 包构造器：它会写入低 8 位字节和校验并重试读取确认。此处尚未把具体调用点可靠映射到某个用户功能，因此不能将它的字段或 opcode 直接复用于 macOS。

## 从本机配置/资源可确认的功能面

- 有线模式：宏、基础灯效、用户灯效、自定义灯效、音乐律动、TFT 屏幕、Fn 层、休眠时间、按键响应时间。
- 2.4G 配置中保留宏、基础/用户灯效和音乐律动；屏幕和自定义灯效被标为不可用。蓝牙模式的语言文件明确提示暂不支持设置。
- TFT 配置为 `240 × 135`，RGB565 图像转换存在于 `mui.dll`；单个 GIF 槽位、GIF 帧头 256 bytes、最大 141 帧。
- RGB 的配置上限为亮度 5、速度 5；支持颜色、方向、静态/动态效果、用户灯效与音乐律动。
- 改键支持顶层与 Fn 层，以及键盘/鼠标/多媒体/快捷键/程序/网页/文本等类别；宏支持录制、延时和重复策略。

这些项目说明 Windows 驱动的界面与本机硬件配置面匹配，不能单独证明某一个设置的写入报文、持久化、读回或蓝牙/2.4G 行为。

## 当前边界

静态逆向已获得 HID 报告形态、逻辑包长度和局部校验行为，但还没有每项功能的“调用点 → opcode → 真机响应 → 持久化”的完整证据链。因此 RGB、屏幕上传、改键、宏、电量读取仍保持禁写。

## 后续静态路线

1. 从已定位的 `WriteFile`/`HidD_SetFeature` 调用点继续恢复各报文构造器，并把每条候选标记为“未验证”。
2. 在实体 Windows 上，以 USBPcap 将候选与“单项改动 → 保存 → 重连”的实际报文逐条对应。
3. 只有在 Windows USBPcap 抓包与候选报文一致，并经真机“修改、保存、重连”验证后，才加入 macOS 协议层。

静态逆向会显著缩小抓包范围，但不能证明一条写入报文对 `0C45:8009` 安全、是否持久化，或在蓝牙/2.4G 模式下的行为。
