import Foundation

private struct StatusDocument: Codable {
    let snapshot: AK35iDeviceSnapshot
    let capabilities: [AK35iCapability]
}

enum AK35iApplication {
    static func run(_ command: AK35iCommand, executablePath: String) -> Int32 {
        switch command {
        case .help:
            printUsage()
            return EXIT_SUCCESS
        case .status(let json):
            return printStatus(json: json)
        case .timeSync(let timeZone, let apply):
            return runTimeSync(timeZone: timeZone, apply: apply)
        case .previewTime(let timeZone):
            return previewTime(timeZone: timeZone)
        case .backup:
            return describeBackupSafety()
        case .restore:
            fputs("恢复已阻止：尚未取得可读取的板载配置备份。不会伪造恢复操作。\n", stderr)
            return EXIT_FAILURE
        case .autoSync(let action):
            return runAutoSync(action: action, executablePath: executablePath)
        case .gui:
            return EXIT_SUCCESS
        }
    }

    static func syncClock(timeZone: ClockTimeZone) throws -> String {
        let time = ClockTime.from(Date(), timeZone: timeZone.timeZone)
        let transport = try AK35iHIDClockTransport()

        for (index, report) in ClockProtocol.reports(for: time).enumerated() {
            Thread.sleep(forTimeInterval: 0.03)
            try transport.writeFeature(report, packetIndex: index + 1)
            transport.readFeatureBestEffort()
        }
        Thread.sleep(forTimeInterval: 0.1)
        return "已同步 \(timeZone.displayName) 时间 \(formatted(time)) 到 \(transport.description())。"
    }

    private static func printUsage() {
        print("AK35i V3 Max macOS 控制中心与 CLI")
        print("")
        print("用法：ak35i <命令>")
        print("  gui                                  打开图形化控制中心")
        print("  status [--json]                      检查 USB HID 接口与功能状态")
        print("  time sync [--utc8] [--apply]         预览或同步屏幕时钟")
        print("  preview time [--utc8]                不连接键盘，仅预览时间报文")
        print("  autosync status|enable|disable        查看、启用或关闭每日 UTC+8 自动校时")
        print("  backup | restore                      显示安全备份/恢复状态")
        print("")
        print("兼容旧命令：ak35i --apply --utc8")
        print("屏幕 GIF、RGB、板载改键和宏尚未取得 V3 Max 抓包验证，已被安全锁定。")
    }

    private static func printStatus(json: Bool) -> Int32 {
        do {
            let snapshot = try AK35iHIDDeviceDiscovery().snapshot()
            let capabilities = AK35iFeature.allCases.map(snapshot.capability)
            if json {
                let document = StatusDocument(snapshot: snapshot, capabilities: capabilities)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(document), as: UTF8.self))
            } else {
                print("连接：\(snapshot.connection.displayName)")
                print("设备：\(snapshot.product ?? "AK35i V3 Max")")
                print("厂商 HID 通道：")
                if snapshot.channels.isEmpty {
                    print("  未发现。请连接 USB 数据线并切换到 USB 模式。")
                }
                for channel in snapshot.channels {
                    let interface = channel.interface
                    print("  \(channel.kind.displayName)：usage \(hex(interface.usagePage)):\(hex(interface.usage))，Feature \(interface.maxFeatureReportSize) B，Output \(interface.maxOutputReportSize) B")
                }
                print("功能状态：")
                for capability in capabilities {
                    print("  \(capability.feature.displayName)：\(capabilityStateName(capability.state)) - \(capability.detail)")
                }
            }
            return EXIT_SUCCESS
        } catch {
            fputs("无法读取 AK35i USB 接口：\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func runTimeSync(timeZone: ClockTimeZone, apply: Bool) -> Int32 {
        let time = ClockTime.from(Date(), timeZone: timeZone.timeZone)
        do {
            let transport = try AK35iHIDClockTransport()
            print("已找到：\(transport.description())")
            print("待同步时间（\(timeZone.displayName)）：\(formatted(time))")
            guard apply else {
                print("预检通过；未向键盘写入。确认执行请加 --apply。")
                return EXIT_SUCCESS
            }

            for (index, report) in ClockProtocol.reports(for: time).enumerated() {
                Thread.sleep(forTimeInterval: 0.03)
                try transport.writeFeature(report, packetIndex: index + 1)
                transport.readFeatureBestEffort()
            }
            Thread.sleep(forTimeInterval: 0.1)
            print("同步报文已写入。请查看键盘屏幕；必要时切回蓝牙模式确认时间仍保留。")
            return EXIT_SUCCESS
        } catch {
            fputs("错误：\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func previewTime(timeZone: ClockTimeZone) -> Int32 {
        let time = ClockTime.from(Date(), timeZone: timeZone.timeZone)
        let reports = ClockProtocol.reports(for: time)
        print("预览时间（\(timeZone.displayName)）：\(formatted(time))")
        print("RTC 写入将使用 \(reports.count) 个 65 字节 Feature Report；本命令未打开或写入键盘。")
        return EXIT_SUCCESS
    }

    private static func describeBackupSafety() -> Int32 {
        print("备份安全状态：")
        for feature in [AK35iFeature.clock, .screenUpload, .lighting, .keymap, .macros] {
            switch SafetyGate.backupAvailability(for: feature) {
            case .available:
                print("  \(feature.displayName)：可安全备份")
            case .notNeeded(let detail):
                print("  \(feature.displayName)：无需备份 - \(detail)")
            case .unavailable(let detail):
                print("  \(feature.displayName)：不可用 - \(detail)")
            }
        }
        return EXIT_SUCCESS
    }

    private static func runAutoSync(action: AutoSyncAction, executablePath: String) -> Int32 {
        let store = AutoSyncLaunchAgentStore()
        do {
            switch action {
            case .status:
                print(store.isEnabled() ? "自动 UTC+8 校时：已启用（每日一次，并在登录时尝试）。" : "自动 UTC+8 校时：未启用。")
            case .enable:
                let url = try store.enable(executablePath: executablePath)
                print("已启用自动 UTC+8 校时：\(url.path)")
            case .disable:
                try store.disable()
                print("已关闭自动 UTC+8 校时。")
            }
            return EXIT_SUCCESS
        } catch {
            fputs("自动校时设置失败：\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func formatted(_ time: ClockTime) -> String {
        String(format: "%04d-%02d-%02d %02d:%02d:%02d", time.year, time.month, time.day, time.hour, time.minute, time.second)
    }

    private static func hex(_ value: Int) -> String {
        String(format: "0x%04X", value)
    }

    static func capabilityStateName(_ state: AK35iFeatureState) -> String {
        switch state {
        case .verified: return "已验证"
        case .captureRequired: return "等待抓包"
        case .notConnected: return "未连接"
        }
    }
}
