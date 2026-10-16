# 第三方与商标声明

AK35i、AJAZZ 及相关商标归其各自权利人所有。本项目是独立的社区兼容性工具，不受 AJAZZ 认可、授权或支持。

本仓库不包含、分发或修改厂商 Windows 驱动、固件、示例 GIF、图片或任何厂商源码，但为了在 macOS 上复现驱动的行为，收录了从驱动安装包中取出的少量数据：

- `Sources/AK35iClockSync/DriverLightTables.swift`：驱动实时灯效用到的 17 张数值表（色相、亮度波形、配色、按键分组等，共 1,730 字节），从 `mui.dll`（SHA-256 `e9a2a9ec1c5f9682ff1cd1904bcf2fcd2fe21f124bee048297e8ade1496028ae`）中逐字节复制，每张表注明了原地址。
- 键位数据（灯号、HID 码、行列位置和在布局图中的矩形），见 `Sources/AK35iClockSync/PerKeyLighting.swift` 和上述文件，取自驱动的 `layouts/rgb-keyboard.xml`。

这些数据不是可执行代码。文档中的型号、VID:PID、公开下载页链接、哈希和协议观察结果仅用于兼容性研究与可复现性说明。

使用者应自行确认其所在地区关于设备互操作、逆向工程和固件处理的适用条款。本项目不提供固件更新、DFU 或恢复出厂功能。
