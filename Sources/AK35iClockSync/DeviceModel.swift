import Foundation

enum AK35iConnection: String, Codable, Equatable {
    case disconnected
    case usbWired
    /// Only the 2.4G receiver: commands go through its 32-byte interface.
    case wireless

    var displayName: String {
        switch self {
        case .disconnected: return "未发现 USB 有线控制接口"
        case .usbWired: return "USB 有线已连接"
        case .wireless: return "2.4G 接收器已连接"
        }
    }
}

enum AK35iChannelKind: String, Codable, CaseIterable, Equatable {
    case clockAndSettings
    case stateQuery
    case screenTransfer
    case unknown

    var displayName: String {
        switch self {
        case .clockAndSettings: return "时钟与设置控制"
        case .stateQuery: return "状态查询"
        case .screenTransfer: return "屏幕数据传输"
        case .unknown: return "未分类厂商接口"
        }
    }
}

struct HIDInterfaceSnapshot: Codable, Equatable {
    let usagePage: Int
    let usage: Int
    let maxFeatureReportSize: Int
    let maxOutputReportSize: Int
    let product: String
    let transport: String
    let serialNumber: String?

    init(
        usagePage: Int,
        usage: Int,
        maxFeatureReportSize: Int,
        maxOutputReportSize: Int,
        product: String = "USB KEYBOARD",
        transport: String = "USB",
        serialNumber: String? = nil
    ) {
        self.usagePage = usagePage
        self.usage = usage
        self.maxFeatureReportSize = maxFeatureReportSize
        self.maxOutputReportSize = maxOutputReportSize
        self.product = product
        self.transport = transport
        self.serialNumber = serialNumber
    }
}

struct AK35iChannel: Codable, Equatable {
    let kind: AK35iChannelKind
    let interface: HIDInterfaceSnapshot
}

enum AK35iFeature: String, Codable, CaseIterable, Equatable {
    case diagnostics
    case clock
    case battery
    case lighting
    case perKeyLighting
    case systemSettings
    case screenUpload
    case keymap
    case macros

    var displayName: String {
        switch self {
        case .diagnostics: return "设备诊断"
        case .clock: return "屏幕时钟"
        case .battery: return "电量"
        case .lighting: return "RGB 灯效"
        case .perKeyLighting: return "自定义单键灯光"
        case .systemSettings: return "系统设置"
        case .screenUpload: return "屏幕图片与 GIF"
        case .keymap: return "板载改键"
        case .macros: return "板载宏"
        }
    }
}

enum AK35iFeatureState: String, Codable, Equatable {
    case verified
    case experimental
    case captureRequired
    case notConnected
}

struct AK35iCapability: Codable, Equatable {
    let feature: AK35iFeature
    let state: AK35iFeatureState
    let detail: String
}

struct AK35iDeviceSnapshot: Codable, Equatable {
    let connection: AK35iConnection
    let channels: [AK35iChannel]
    let product: String?
    let serialNumber: String?

    static func from(interfaces: [HIDInterfaceSnapshot]) -> AK35iDeviceSnapshot {
        let publicInterfaces = interfaces.map { interface in
            HIDInterfaceSnapshot(
                usagePage: interface.usagePage,
                usage: interface.usage,
                maxFeatureReportSize: interface.maxFeatureReportSize,
                maxOutputReportSize: interface.maxOutputReportSize,
                product: interface.product,
                transport: interface.transport,
                serialNumber: nil
            )
        }
        let channels = publicInterfaces.compactMap { interface -> AK35iChannel? in
            let kind = classify(interface)
            guard kind != .unknown else { return nil }
            return AK35iChannel(kind: kind, interface: interface)
        }
        return AK35iDeviceSnapshot(
            connection: publicInterfaces.isEmpty ? .disconnected : .usbWired,
            channels: channels,
            product: publicInterfaces.first?.product,
            serialNumber: nil
        )
    }

    static let disconnected = AK35iDeviceSnapshot(
        connection: .disconnected,
        channels: [],
        product: nil,
        serialNumber: nil
    )

    static let wireless = AK35iDeviceSnapshot(
        connection: .wireless,
        channels: [],
        product: AK35iReceiverTransport.productName,
        serialNumber: nil
    )

    func capability(_ feature: AK35iFeature) -> AK35iCapability {
        if connection == .wireless {
            return wirelessCapability(feature)
        }
        guard connection == .usbWired else {
            return AK35iCapability(
                feature: feature,
                state: .notConnected,
                detail: "请通过数据线连接键盘并切换到 USB 模式。"
            )
        }

        switch feature {
        case .diagnostics:
            return AK35iCapability(feature: feature, state: .verified, detail: "已读取 USB 厂商 HID 接口信息。")
        case .clock:
            let exists = channels.contains { $0.kind == .clockAndSettings }
            return AK35iCapability(
                feature: feature,
                state: exists ? .verified : .notConnected,
                detail: exists
                    ? "UTC+8 校时已在此键盘上实机验证。"
                    : "未找到 0xFF13 时钟控制接口。"
            )
        case .battery:
            return AK35iCapability(
                feature: feature,
                state: .notConnected,
                detail: "有线 USB 下键盘不提供电量，请看键盘屏幕；插上 2.4G 接收器并拨到 2.4G 档后可读取。"
            )
        case .lighting:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "基础灯效已在此键盘实机验证静态恒亮（设备确认、重连后保留），川流不息目测正常；其余模式按静态逆向发送。可在灯光页或用 CLI ak35i light set 写入，可用 Fn+\\| 恢复。"
            )
        case .perKeyLighting:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "已在此键盘实机验证单键写入（设备确认、读回一致、重连后保留）。写入前读取已保存的颜色并合并；可在单键灯光页或用 CLI ak35i keys set 写入，可用 Fn+\\| 切回其他灯效。"
            )
        case .systemSettings:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "已在此键盘实机验证：Win 档下禁用 Alt+Tab、禁用 Alt+F4 生效；只开禁用 Win 不生效，需同时开禁用 Alt+F4；Mac 档下禁用 Win 不拦截。休眠、响应时间、Fn 开关和拔插后是否保留尚未确认。键盘不提供读取，每次整体写入；可在系统设置页或用 CLI ak35i system set 写入。"
            )
        case .screenUpload:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "已在此键盘实机验证上传单帧测试图：16 块全部收到键盘回复，上传后屏幕立即显示该图，拔插后上电仍播放出厂开机动画，随后回到原来的界面。上传只覆盖屏幕 GIF 页，断电后保留，按 Fn+PrtSc 显示、再按返回。键盘不提供读取，原 GIF 页内容无法恢复。可在屏幕页或用 CLI ak35i screen set 上传。"
            )
        case .keymap:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "已在此键盘实机验证普通层 CapsLock→Esc（拔插后保留）和 Fn 层 F1→静音，并能恢复默认。键盘不提供读取，每次写入整层，未列出的键恢复默认；可在改键页或用 CLI ak35i keymap set 写入，ak35i keymap reset --apply 恢复。"
            )
        case .macros:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "已在此键盘实机验证：两个宏（单键、Shift 组合）绑定到 F12、F11 后按设置播放（含重复 3 次），拔插后保留，清空宏并恢复改键后复原。键盘不提供读取，每次写入替换全部宏；宏需在改键中绑定为 macro:N 才会播放。可在宏页面或用 CLI ak35i macro set 写入，ak35i macro clear --apply 清空。"
            )
        }
    }

    private static func classify(_ interface: HIDInterfaceSnapshot) -> AK35iChannelKind {
        switch (interface.usagePage, interface.usage) {
        case (0xff13, 0x0001): return .clockAndSettings
        case (0xfffd, 0x0001): return .stateQuery
        case (0xff68, 0x0061): return .screenTransfer
        default: return .unknown
        }
    }
}

extension AK35iDeviceSnapshot {
    /// Through the receiver the keyboard takes the driver's 2.4G packets
    /// (firmware 0x67C8); features are listed here as they are ported.
    fileprivate func wirelessCapability(_ feature: AK35iFeature) -> AK35iCapability {
        switch feature {
        case .diagnostics:
            return AK35iCapability(feature: feature, state: .verified, detail: "已识别 2.4G 接收器的 0xFF60 接口。")
        case .battery:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "经 2.4G 接收器只读读取，已在此键盘实测（应答 20 01 00 加百分比）。"
            )
        case .clock:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "经 2.4G 接收器发送一包 0C（与 Windows 驱动相同），已在此键盘实测。"
            )
        case .lighting:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "经 2.4G 接收器发送一包 05（与 Windows 驱动相同），已在此键盘实测静态恒亮。可用 Fn+\\| 恢复。"
            )
        case .systemSettings:
            return AK35iCapability(
                feature: feature,
                state: .experimental,
                detail: "经 2.4G 接收器发送一包 07（与 Windows 驱动相同），已在此键盘实测禁用 Alt+Tab 和恢复默认。"
            )
        default:
            return AK35iCapability(
                feature: feature,
                state: .notConnected,
                detail: "2.4G 下尚未支持，请用数据线连接并切到 USB 模式。"
            )
        }
    }
}

enum BackupAvailability: Equatable {
    case available
    case notNeeded(String)
    case unavailable(String)
}

enum SafetyGate {
    static func backupAvailability(for feature: AK35iFeature) -> BackupAvailability {
        switch feature {
        case .clock:
            return .notNeeded("时钟同步是一次性写入，不存在可导出的板载时钟配置。")
        case .perKeyLighting:
            return .notNeeded("写入前会读取键盘已保存的单键颜色并在其上合并，未指定的按键保持不变。")
        case .systemSettings:
            return .unavailable("键盘不提供读取命令；不带参数运行 ak35i system set --apply 可写回驱动默认值。")
        case .screenUpload:
            return .unavailable("屏幕内容尚无经验证的硬件读取协议，不能伪造备份。")
        case .diagnostics:
            return .notNeeded("设备诊断不修改板载配置。")
        case .keymap:
            return .unavailable("键盘不提供读取命令；ak35i keymap reset --apply 可写回两层默认（与驱动“重置键盘”相同）。")
        case .macros:
            return .unavailable("键盘不提供读取命令；ak35i macro clear --apply 可清空全部宏。")
        case .battery:
            return .notNeeded("读电量只发送读取请求，不修改板载配置。")
        case .lighting:
            return .unavailable("此功能尚未取得 V3 Max 的读取与回滚抓包，不能安全备份。")
        }
    }
}
