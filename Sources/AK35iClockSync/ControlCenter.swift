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

    func readKeyColors(brightness: Int) -> [UInt8: RGBColor]? {
        do {
            let colors = try AK35iApplication.readPerKeyColors(brightness: brightness)
            message = "已从键盘读取单键颜色；键盘已切到自定义单键模式。"
            return colors
        } catch {
            message = "读取失败：\(error.localizedDescription)"
            return nil
        }
    }

    func applyKeyColors(_ request: PerKeyColorRequest) {
        do {
            message = try AK35iApplication.applyPerKeyColors(request)
        } catch {
            message = "单键颜色写入失败：\(error.localizedDescription)"
        }
    }

    func applySystemSettings(_ settings: SystemSettings) {
        do {
            message = try AK35iApplication.applySystemSettings(settings)
        } catch {
            message = "系统设置写入失败：\(error.localizedDescription)"
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
    case perKey
    case system
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
        case .perKey: return "单键灯光"
        case .system: return "系统设置"
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
        case .perKey: return "square.grid.3x3"
        case .system: return "gearshape"
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
            case .perKey:
                PerKeyView(model: model)
            case .system:
                SystemSettingsView(model: model)
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
                Text("已实机验证的时钟同步可以写入；基础灯效、单键灯光和系统设置为实验性写入。屏幕、改键与宏在取得实机证据前保持锁定。")
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
                    Picker("亮度（0 为熄灭）", selection: $settings.brightness) {
                        ForEach(levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode.supportsSpeed {
                    Picker("速度（0 最慢，5 最快）", selection: $settings.speed) {
                        ForEach(levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let directions = mode.allowedDirections {
                    Picker(directions == [0, 1] ? "方向（0 与 1 相反）" : "方向", selection: Binding(
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
                        get: { settings.color.cgColor },
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

private struct SystemSettingsView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var settings = SystemSettings()
    @State private var confirmsApply = false

    private var capability: AK35iCapability { model.snapshot.capability(.systemSettings) }

    var body: some View {
        Form {
            Section("系统设置") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                Toggle("禁用 Win 键", isOn: $settings.disableWin)
                Toggle("禁用 Alt+Tab", isOn: $settings.disableAltTab)
                Toggle("禁用 Alt+F4", isOn: $settings.disableAltF4)
                Text("实测：只开「禁用 Win 键」不生效，需同时开「禁用 Alt+F4」；键盘背面开关在 Mac 档时禁用 Win 无效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("休眠时间", selection: $settings.sleep) {
                    ForEach(SleepTimeout.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("按键响应（档位越低延迟越小，过低可能连击）", selection: $settings.responseLevel) {
                    ForEach(SystemSettings.responseLevels, id: \.self) { Text("\($0) 档").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Fn 开关（含义为推断）", selection: $settings.fnSwitch) {
                    Text("0 使用单键").tag(0)
                    Text("1 使用组合键").tag(1)
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("写入键盘") { confirmsApply = true }
                        .disabled(capability.state != .experimental)
                    Button("表单恢复默认值") { settings = SystemSettings() }
                }
            }
            Section("说明") {
                Text("键盘不提供读取命令，这里显示的是驱动默认值，不是键盘当前的设置。每次写入都会覆盖全部六项。")
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("系统设置")
        .padding()
        .alert("将系统设置写入键盘？", isPresented: $confirmsApply) {
            Button("取消", role: .cancel) {}
            Button("写入") { model.applySystemSettings(settings) }
        } message: {
            Text("实验性功能：将按表单覆盖键盘上全部六项系统设置。")
        }
    }
}

private struct PerKeyView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var editor = PerKeyEditorState()
    @State private var brush = RGBColor(red: 0xff, green: 0x00, blue: 0x00)
    @State private var brightness = LightingEffect.defaultBrightness
    @State private var confirmsRead = false
    @State private var confirmsApply = false

    private var capability: AK35iCapability { model.snapshot.capability(.perKeyLighting) }
    private let black = RGBColor(red: 0, green: 0, blue: 0)

    var body: some View {
        Form {
            Section("自定义单键灯光") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                KeyboardCanvas(editor: $editor)
                    .frame(minHeight: 200)
                HStack {
                    ColorPicker("画笔颜色", selection: Binding(
                        get: { brush.cgColor },
                        set: { if let picked = RGBColor(cgColor: $0) { brush = picked } }
                    ), supportsOpacity: false)
                    Button("涂到所选键") { editor.paintSelection(brush) }
                        .disabled(editor.selection.isEmpty)
                    Button("全部涂成此色") { editor.fill(brush) }
                    Button("全部熄灭") { editor.fill(black) }
                }
                HStack {
                    Text("已选 \(editor.selection.count) 个键").foregroundStyle(.secondary)
                    Button("全选") { editor.selection = Set(editor.colors.keys) }
                    Button("取消选择") { editor.selection = [] }
                }
                Picker("亮度（0 为熄灭）", selection: $brightness) {
                    ForEach(LightingEffect.levels, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("从键盘读取") { confirmsRead = true }
                    Button("写入键盘") { confirmsApply = true }
                }
                .disabled(capability.state != .experimental)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("单键灯光")
        .padding()
        .alert("从键盘读取单键颜色？", isPresented: $confirmsRead) {
            Button("取消", role: .cancel) {}
            Button("读取") {
                if let colors = model.readKeyColors(brightness: brightness) { editor.colors = colors }
            }
        } message: {
            Text("已保存的单键颜色只能在自定义单键模式下读出，读取会把键盘灯效切到该模式。")
        }
        .alert("将单键颜色写入键盘？", isPresented: $confirmsApply) {
            Button("取消", role: .cancel) {}
            Button("写入") { model.applyKeyColors(editor.request(brightness: brightness)) }
        } message: {
            Text("实验性功能：键盘会切到自定义单键模式，并按编辑器中的颜色写入全部 104 个键。")
        }
    }
}

/// Keys drawn at their rectangles in the driver's layout image.
private struct KeyboardCanvas: View {
    @Binding var editor: PerKeyEditorState
    private static let origin = CGPoint(x: 30, y: 48)
    private static let extent = CGSize(width: 740, height: 212)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.extent.width, proxy.size.height / Self.extent.height)
            ZStack(alignment: .topLeading) {
                ForEach(KeyboardLayout.keys, id: \.light) { key in
                    KeyCap(
                        key: key,
                        color: editor.colors[key.light] ?? RGBColor(red: 0, green: 0, blue: 0),
                        selected: editor.selection.contains(key.light),
                        scale: scale
                    )
                    .offset(x: (CGFloat(key.x) - Self.origin.x) * scale, y: (CGFloat(key.y) - Self.origin.y) * scale)
                    .onTapGesture { editor.toggle(key.light) }
                }
            }
        }
        .aspectRatio(Self.extent.width / Self.extent.height, contentMode: .fit)
    }
}

private struct KeyCap: View {
    let key: KeyboardKey
    let color: RGBColor
    let selected: Bool
    let scale: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3 * scale)
        let isLight = 0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue) > 140
        shape
            .fill(Color(cgColor: color.cgColor))
            .overlay(shape.stroke(selected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: selected ? 3 : 1))
            .overlay(
                Text(key.name)
                    .font(.system(size: 7 * scale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(1)
                    .foregroundStyle(isLight ? Color.black : Color.white)
            )
            .frame(width: CGFloat(key.width) * scale, height: CGFloat(key.height) * scale)
            .contentShape(shape)
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
