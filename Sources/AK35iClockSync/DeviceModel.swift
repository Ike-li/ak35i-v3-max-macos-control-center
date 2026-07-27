import Foundation

enum AK35iConnection: String, Codable, Equatable {
    case disconnected
    case usbWired

    var displayName: String {
        switch self {
        case .disconnected: return "未发现 USB 有线控制接口"
        case .usbWired: return "USB 有线已连接"
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
    case screenUpload
    case keymap
    case macros

    var displayName: String {
        switch self {
        case .diagnostics: return "设备诊断"
        case .clock: return "屏幕时钟"
        case .battery: return "电量"
        case .lighting: return "RGB 灯效"
        case .screenUpload: return "屏幕图片与 GIF"
        case .keymap: return "板载改键"
        case .macros: return "板载宏"
        }
    }
}

enum AK35iFeatureState: String, Codable, Equatable {
    case verified
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

    func capability(_ feature: AK35iFeature) -> AK35iCapability {
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
            return captureRequired(feature, "产品支持电量显示；读取命令须以 V3 Max 抓包验证后启用。")
        case .lighting:
            return captureRequired(feature, "不猜测 RGB 写入报文；等待 V3 Max 驱动抓包。")
        case .screenUpload:
            return captureRequired(feature, "已发现 4 KiB 屏幕传输通道，但图片/GIF 格式与提交序列尚未验证。")
        case .keymap:
            return captureRequired(feature, "板载改键需要完整读写和回滚抓包，当前保持只读。")
        case .macros:
            return captureRequired(feature, "宏事件编码与持久化序列尚未验证，当前保持只读。")
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

    private func captureRequired(_ feature: AK35iFeature, _ detail: String) -> AK35iCapability {
        AK35iCapability(feature: feature, state: .captureRequired, detail: detail)
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
        case .screenUpload:
            return .unavailable("屏幕内容尚无经验证的硬件读取协议，不能伪造备份。")
        case .diagnostics:
            return .notNeeded("设备诊断不修改板载配置。")
        case .battery, .lighting, .keymap, .macros:
            return .unavailable("此功能尚未取得 V3 Max 的读取与回滚抓包，不能安全备份。")
        }
    }
}
