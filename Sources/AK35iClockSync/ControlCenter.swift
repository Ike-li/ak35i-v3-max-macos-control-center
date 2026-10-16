import AppKit
import Foundation
import SwiftUI

@MainActor
final class ControlCenterModel: ObservableObject {
    @Published private(set) var snapshot: AK35iDeviceSnapshot = .disconnected
    @Published private(set) var message = "正在检测 USB 设备…"
    @Published private(set) var autoSyncEnabled = false
    @Published private(set) var isSyncing = false

    let executablePath: String

    init(executablePath: String) {
        self.executablePath = executablePath
        refresh()
    }

    func refresh() {
        do {
            snapshot = try AK35iHIDDeviceDiscovery().snapshot()
            message = snapshot.connection == .usbWired ? "已刷新 USB HID 设备状态。" : "未发现 USB 有线控制接口。"
        } catch {
            snapshot = .disconnected
            message = error.localizedDescription
        }
        autoSyncEnabled = AutoSyncLaunchAgentStore().isEnabled()
    }

    func syncNow(timeZone: ClockTimeZone) {
        isSyncing = true
        defer { isSyncing = false }
        do {
            message = try AK35iApplication.syncClock(timeZone: timeZone)
        } catch {
            message = "同步失败：\(error.localizedDescription)"
        }
    }

    func applyLighting(_ settings: LightingSettings) {
        do {
            message = try AK35iApplication.applyLighting(try settings.effect())
        } catch {
            message = "灯效写入失败：\(error.localizedDescription)"
        }
    }

    func setAutoSync(_ enabled: Bool) {
        do {
            let store = AutoSyncLaunchAgentStore()
            if enabled {
                let url = try store.enable(executablePath: executablePath)
                message = "已启用每日 UTC+8 自动校时：\(url.lastPathComponent)"
            } else {
                try store.disable()
                message = "已关闭自动 UTC+8 校时。"
            }
            autoSyncEnabled = store.isEnabled()
        } catch {
            autoSyncEnabled = AutoSyncLaunchAgentStore().isEnabled()
            message = "自动校时设置失败：\(error.localizedDescription)"
        }
    }
}

private enum ControlCenterPage: String, CaseIterable, Identifiable {
    case overview
    case clock
    case battery
    case lighting
    case screen
    case keymap
    case macros

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .clock: return "时钟"
        case .battery: return "电量"
        case .lighting: return "灯光"
        case .screen: return "屏幕"
        case .keymap: return "改键"
        case .macros: return "宏"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "keyboard"
        case .clock: return "clock"
        case .battery: return "battery.75percent"
        case .lighting: return "lightbulb.2"
        case .screen: return "rectangle.on.rectangle"
        case .keymap: return "command"
        case .macros: return "record.circle"
        }
    }
}

private struct ControlCenterRootView: View {
    @StateObject private var model: ControlCenterModel
    @State private var selectedPage: ControlCenterPage? = .overview

    init(executablePath: String) {
        _model = StateObject(wrappedValue: ControlCenterModel(executablePath: executablePath))
    }

    var body: some View {
        NavigationSplitView {
            List(ControlCenterPage.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationTitle("AK35i V3 Max")
        } detail: {
            switch selectedPage ?? .overview {
            case .overview:
                OverviewView(model: model)
            case .clock:
                ClockView(model: model)
            case .battery:
                LockedFeatureView(model: model, feature: .battery)
            case .lighting:
                LightingView(model: model)
            case .screen:
                LockedFeatureView(model: model, feature: .screenUpload)
            case .keymap:
                LockedFeatureView(model: model, feature: .keymap)
            case .macros:
                LockedFeatureView(model: model, feature: .macros)
            }
        }
        .frame(minWidth: 840, minHeight: 560)
    }
}

private struct OverviewView: View {
    @ObservedObject var model: ControlCenterModel

    var body: some View {
        Form {
            Section("连接") {
                LabeledContent("状态", value: model.snapshot.connection.displayName)
                LabeledContent("产品", value: model.snapshot.product ?? "未检测到")
                Button("刷新设备") { model.refresh() }
            }
            Section("厂商 HID 通道") {
                if model.snapshot.channels.isEmpty {
                    Text("未发现。请使用数据线连接并切换到 USB 模式。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.channels, id: \.interface.usagePage) { channel in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.kind.displayName).fontWeight(.medium)
                        Text("usage \(hex(channel.interface.usagePage)):\(hex(channel.interface.usage)) · Feature \(channel.interface.maxFeatureReportSize) B · Output \(channel.interface.maxOutputReportSize) B")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("安全策略") {
                Text("已实机验证的时钟同步可以写入；基础灯效为实验性写入。屏幕、用户灯效、改键与宏在取得实机证据前保持锁定。")
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("概览")
        .padding()
    }
}

private struct ClockView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var useUTC8 = true
    @State private var confirmsSync = false

    private var selectedTimeZone: ClockTimeZone { useUTC8 ? .utcPlusEight : .system }
    private var capability: AK35iCapability { model.snapshot.capability(.clock) }

    var body: some View {
        Form {
            Section("屏幕时钟") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                Picker("同步时区", selection: $useUTC8) {
                    Text("UTC+08:00（北京时间）").tag(true)
                    Text("Mac 当前时区").tag(false)
                }
                Button("立即同步") { confirmsSync = true }
                    .disabled(capability.state != .verified || model.isSyncing)
            }
            Section("可选自动同步") {
                Toggle("登录时及每 24 小时同步 UTC+8", isOn: Binding(
                    get: { model.autoSyncEnabled },
                    set: { model.setAutoSync($0) }
                ))
                Text("只有启用时才会创建用户级 LaunchAgent；任务在键盘未通过 USB 连接时不会写入任何设备。")
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("时钟")
        .padding()
        .alert("将时间写入键盘？", isPresented: $confirmsSync) {
            Button("取消", role: .cancel) {}
            Button("同步") { model.syncNow(timeZone: selectedTimeZone) }
        } message: {
            Text("将以 \(selectedTimeZone.displayName) 写入屏幕 RTC。")
        }
    }
}

private struct LightingView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var settings = LightingSettings()
    @State private var confirmsApply = false

    private var capability: AK35iCapability { model.snapshot.capability(.lighting) }
    private let levels = LightingEffect.levels

    var body: some View {
        let mode = settings.mode
        Form {
            Section("基础灯效") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                Picker("灯效", selection: $settings.mode) {
                    ForEach(LightingMode.allCases, id: \.self) { mode in
                        Text("\(mode.rawValue)  \(mode.displayName)").tag(mode)
                    }
                }
                if mode.supportsBrightness {
                    Picker("亮度", selection: $settings.brightness) {
                        ForEach(levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode.supportsSpeed {
                    Picker("速度", selection: $settings.speed) {
                        ForEach(levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let directions = mode.allowedDirections {
                    Picker("方向", selection: Binding(
                        get: { directions.contains(settings.direction) ? settings.direction : 0 },
                        set: { settings.direction = $0 }
                    )) {
                        ForEach(directions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode.supportsColor {
                    Toggle("多彩", isOn: $settings.colorful)
                    ColorPicker("颜色", selection: Binding(
                        get: {
                            CGColor(
                                srgbRed: CGFloat(settings.color.red) / 255,
                                green: CGFloat(settings.color.green) / 255,
                                blue: CGFloat(settings.color.blue) / 255,
                                alpha: 1
                            )
                        },
                        set: { if let picked = RGBColor(cgColor: $0) { settings.color = picked } }
                    ), supportsOpacity: false)
                    .disabled(settings.colorful)
                }
                Button("写入键盘") { confirmsApply = true }
                    .disabled(capability.state != .experimental)
            }
            Section("恢复") {
                Text("键盘没有灯效读回命令，写入前无法备份当前设置。效果不符时可用 Fn+\\| 切换灯效、Fn+↑/↓ 调亮度、Fn+-/= 调速度。")
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("灯光")
        .padding()
        .alert("将灯效写入键盘？", isPresented: $confirmsApply) {
            Button("取消", role: .cancel) {}
            Button("写入") { model.applyLighting(settings) }
        } message: {
            Text("实验性功能：将写入「\(mode.displayName)」并保存到键盘。")
        }
    }
}

private struct LockedFeatureView: View {
    @ObservedObject var model: ControlCenterModel
    let feature: AK35iFeature

    var body: some View {
        let capability = model.snapshot.capability(feature)
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(feature.displayName)尚未开放")
                .font(.title2)
            Text(capability.detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(feature.displayName)
    }
}

@MainActor
func startControlCenter(executablePath: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = ControlCenterAppDelegate(executablePath: executablePath)
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}

@MainActor
private final class ControlCenterAppDelegate: NSObject, NSApplicationDelegate {
    private let executablePath: String
    private var window: NSWindow?

    init(executablePath: String) {
        self.executablePath = executablePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AK35i V3 Max 控制中心"
        window.contentView = NSHostingView(rootView: ControlCenterRootView(executablePath: executablePath))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private func hex(_ value: Int) -> String {
    String(format: "0x%04X", value)
}
