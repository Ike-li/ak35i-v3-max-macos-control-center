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
        case .lightingList:
            return printLightingModes()
        case .lightingSet(let effect, let apply):
            return runLightingSet(effect, apply: apply)
        case .perKeyList:
            return printKeyNames()
        case .perKeySet(let request, let apply):
            return runPerKeySet(request, apply: apply)
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
        print("  light list                           列出 20 种基础灯效及可调参数")
        print("  light set --mode N [选项] [--apply]  预览或写入基础灯效（实验性）")
        print("      --brightness 0-5  --speed 0-5  --direction N  --color RRGGBB | --colorful")
        print("  keys list                            列出自定义单键灯光可用的键名")
        print("  keys set 键名=RRGGBB ... [--apply]   预览或写入单键颜色（实验性）")
        print("      --all RRGGBB  --clear  --brightness 0-5")
        print("")
        print("兼容旧命令：ak35i --apply --utc8")
        print("基础灯效为实验性功能；用户灯效、自定义颜色、屏幕 GIF、板载改键和宏尚未验证，已被安全锁定。")
    }

    private static func printLightingModes() -> Int32 {
        print("基础灯效（模式号来自 Windows 驱动默认表）：")
        for mode in LightingMode.allCases {
            var parameters: [String] = []
            if mode.supportsBrightness { parameters.append("亮度") }
            if mode.supportsSpeed { parameters.append("速度") }
            if let directions = mode.allowedDirections {
                parameters.append("方向 " + directions.map(String.init).joined(separator: "/"))
            }
            if mode.supportsColor { parameters.append("颜色/多彩") }
            let name = mode.displayName.padding(toLength: 6, withPad: "　", startingAt: 0)
            print(String(format: "  %2d  ", mode.rawValue) + name + "  " + (parameters.isEmpty ? "无参数" : parameters.joined(separator: "、")))
        }
        print("未指定的参数使用驱动默认值：亮度 5、速度 3、方向 0、多彩。")
        print("实测：亮度 0 为熄灭；速度 0 最慢、5 最快；方向 0 与 1 互为反向。")
        return EXIT_SUCCESS
    }

    private static func runLightingSet(_ effect: LightingEffect, apply: Bool) -> Int32 {
        let packets = LightingProtocol.packets(for: effect)
        print("灯效：\(effect.mode.rawValue) \(effect.mode.displayName)")
        for (index, packet) in packets.enumerated() {
            let payload = HIDFeatureReport.macOSPayload(from: packet.report)
            let bytes = payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("  \(index + 1). \(bytes)\(packet.expectsAck ? "  [需确认]" : "")")
        }
        guard apply else {
            print("预览完成；未连接或写入键盘。确认写入请加 --apply。")
            return EXIT_SUCCESS
        }

        do {
            print(try applyLighting(effect))
            return EXIT_SUCCESS
        } catch {
            fputs("错误：\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func printKeyNames() -> Int32 {
        print("自定义单键灯光键名（不区分大小写）：")
        let names = KeyboardLayout.keys.map(\.name)
        for start in stride(from: 0, to: names.count, by: 13) {
            print("  " + names[start..<min(start + 13, names.count)].joined(separator: " "))
        }
        return EXIT_SUCCESS
    }

    private static func runPerKeySet(_ request: PerKeyColorRequest, apply: Bool) -> Int32 {
        func hex(_ color: RGBColor) -> String { String(format: "%02X%02X%02X", color.red, color.green, color.blue) }
        print("自定义单键灯光：亮度 \(request.brightness)")
        print("  底色：" + (request.clear ? "全部清为黑色" : "键盘当前保存的颜色"))
        if let all = request.all { print("  全部按键：\(hex(all))") }
        let named = KeyboardLayout.keys.compactMap { key in request.keys[key.light].map { "\(key.name)=\(hex($0))" } }
        if !named.isEmpty { print("  " + named.joined(separator: " ")) }
        print("写入时会先切到自定义单键模式（0x80），读取当前颜色作为底色，写入后再读回核对。")
        guard apply else {
            print("预览完成；未连接或写入键盘。确认写入请加 --apply。")
            return EXIT_SUCCESS
        }

        do {
            print(try applyPerKeyColors(request))
            return EXIT_SUCCESS
        } catch {
            fputs("错误：\(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    /// Stored colours are only readable in custom mode, so reading switches to it.
    static func readPerKeyColors(brightness: Int) throws -> [UInt8: RGBColor] {
        let transport = try AK35iHIDClockTransport()
        try switchToCustomMode(brightness: brightness, transport)
        return try readStoredKeyColors(transport)
    }

    static func applyPerKeyColors(_ request: PerKeyColorRequest) throws -> String {
        let transport = try AK35iHIDClockTransport()
        try switchToCustomMode(brightness: request.brightness, transport)
        let target = request.resolve(stored: try readStoredKeyColors(transport))
        let write = try FeatureSequenceWriter.send(PerKeyProtocol.writePackets(colors: target), to: transport)
        guard write.unacknowledgedPackets.isEmpty else {
            throw FeatureSequenceError.packetsNotAcknowledged(write.unacknowledgedPackets)
        }

        let lit = target.values.filter { $0 != RGBColor(red: 0, green: 0, blue: 0) }.count
        guard request.brightness > 0 else {
            return "已写入自定义单键颜色（\(lit) 个按键有颜色），键盘已确认全部命令。亮度为 0 时灯全灭，未做读回核对。"
        }
        Thread.sleep(forTimeInterval: 0.3)
        let mismatched = PerKeyVerification.mismatchedLights(expected: target, readBack: try readStoredKeyColors(transport))
        guard mismatched.isEmpty else {
            let names = KeyboardLayout.keys.filter { mismatched.contains($0.light) }.map(\.name)
            throw PerKeyLightingError.verificationFailed(names)
        }
        return "已写入自定义单键颜色（\(lit) 个按键有颜色），键盘已确认全部命令，读回核对一致。可用 Fn+\\| 切回其他灯效。"
    }

    private static func switchToCustomMode(brightness: Int, _ transport: AK35iHIDClockTransport) throws {
        let mode = try FeatureSequenceWriter.send(LightingProtocol.customModePackets(brightness: brightness), to: transport)
        guard mode.unacknowledgedPackets.isEmpty else {
            throw FeatureSequenceError.packetsNotAcknowledged(mode.unacknowledgedPackets)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Reads twice: in custom mode the readback is static; differing reads mean
    /// the keyboard is still showing an animated effect.
    private static func readStoredKeyColors(_ transport: AK35iHIDClockTransport) throws -> [UInt8: RGBColor] {
        let first = try FeatureBlockReader.read(request: PerKeyProtocol.readRequest, chunks: PerKeyProtocol.chunkCount, from: transport)
        Thread.sleep(forTimeInterval: 0.3)
        let second = try FeatureBlockReader.read(request: PerKeyProtocol.readRequest, chunks: PerKeyProtocol.chunkCount, from: transport)
        guard first == second, let colors = PerKeyProtocol.colors(fromBlock: first) else {
            throw PerKeyLightingError.storedColorsUnstable
        }
        return colors
    }

    static func applyLighting(_ effect: LightingEffect) throws -> String {
        let transport = try AK35iHIDClockTransport()
        let result = try FeatureSequenceWriter.send(LightingProtocol.packets(for: effect), to: transport)
        guard result.unacknowledgedPackets.isEmpty else {
            throw FeatureSequenceError.packetsNotAcknowledged(result.unacknowledgedPackets)
        }
        return "已写入灯效「\(effect.mode.displayName)」，键盘已确认全部命令。如效果不符，可用 Fn+\\| 切换灯效、Fn+↑/↓ 调亮度恢复。"
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
        for feature in [AK35iFeature.clock, .screenUpload, .lighting, .perKeyLighting, .keymap, .macros] {
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
        case .experimental: return "实验性"
        case .captureRequired: return "等待抓包"
        case .notConnected: return "未连接"
        }
    }
}
