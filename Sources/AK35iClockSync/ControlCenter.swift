import AppKit
import Foundation
import SwiftUI

@MainActor
final class ControlCenterModel: ObservableObject {
    @Published private(set) var snapshot: AK35iDeviceSnapshot = .disconnected
    @Published private(set) var message = "正在检测 USB 设备…"
    @Published private(set) var autoSyncEnabled = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isStreaming = false
    /// Fraction of screen blocks written, or nil when no upload is running.
    @Published private(set) var screenProgress: Double?
    private var liveStop: StopFlag?

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

    func applyKeymap(_ request: KeymapRequest) {
        do {
            message = try AK35iApplication.applyKeymap(request)
        } catch {
            message = "改键写入失败：\(error.localizedDescription)"
        }
    }

    func applyMacros(_ macros: [Macro]) {
        do {
            message = try AK35iApplication.applyMacros(macros)
        } catch {
            message = "宏写入失败：\(error.localizedDescription)"
        }
    }

    func startLive(_ request: LiveRequest) {
        guard liveStop == nil else { return }
        let stop = StopFlag()
        liveStop = stop
        isStreaming = true
        message = "正在实时推送灯效…"
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: String
            do {
                let transport = try AK35iHIDClockTransport()
                let stats = try AK35iApplication.streamLive(request, to: transport, stop: stop)
                outcome = "已停止实时灯效：发送 \(stats.sent) 帧，跳过 \(stats.skipped) 帧，平均 \(String(format: "%.1f", stats.framesPerSecond)) 帧/秒。键盘已恢复原灯效。"
                    + (stats.heardAudio == false ? "整个过程没有收到声音：可能没有在播放，或没有授予系统录音权限。" : "")
            } catch {
                outcome = "实时灯效中断：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.liveStop = nil
                self.isStreaming = false
                self.message = outcome
            }
        }
    }

    func uploadScreen(_ frames: [ScreenFrame]) {
        guard screenProgress == nil else { return }
        let upload: ScreenUpload
        do {
            upload = try ScreenProtocol.upload(frames: frames)
        } catch {
            message = "屏幕上传失败：\(error.localizedDescription)"
            return
        }
        screenProgress = 0
        message = "正在上传屏幕动画…"
        let total = Double(upload.blocks.count)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: String
            do {
                outcome = try AK35iApplication.uploadScreen(upload) { done in
                    DispatchQueue.main.async { self.screenProgress = Double(done) / total }
                }
            } catch {
                outcome = "屏幕上传失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.screenProgress = nil
                self.message = outcome
            }
        }
    }

    func stopLive() {
        liveStop?.stop()
    }

    func resetKeymap() {
        do {
            message = try KeymapLayer.allCases.map { try AK35iApplication.applyKeymap(KeymapRequest(layer: $0)) }.joined(separator: "\n")
        } catch {
            message = "恢复默认改键失败：\(error.localizedDescription)"
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
    case live
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
        case .live: return "实时灯效"
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
        case .live: return "sparkles"
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
            case .live:
                LiveView(model: model)
            case .screen:
                ScreenView(model: model)
            case .keymap:
                KeymapView(model: model)
            case .macros:
                MacroView(model: model)
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
                Text("已实机验证的时钟同步可以写入；基础灯效、单键灯光、系统设置、改键、宏和屏幕 GIF 页为实验性写入；实时灯效只推送显示、不写入键盘。电量读取在取得实机证据前保持锁定。")
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
                KeyboardCanvas(
                    color: { editor.colors[$0.light] ?? black },
                    label: { $0.name },
                    isSelected: { editor.selection.contains($0.light) },
                    onTap: { editor.toggle($0.light) }
                )
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

private struct KeymapView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var editor = KeymapEditorState()
    @State private var target = ""
    @State private var targetError: String?
    @State private var confirmsApply = false
    @State private var confirmsReset = false

    private var capability: AK35iCapability { model.snapshot.capability(.keymap) }
    private let plain = RGBColor(red: 0x3a, green: 0x3a, blue: 0x3c)
    private let changed = RGBColor(red: 0xff, green: 0x9f, blue: 0x0a)

    private var selectedKey: KeyboardKey? {
        KeyboardLayout.keys.first { $0.light == editor.selection }
    }

    var body: some View {
        Form {
            Section("板载改键") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                Picker("层", selection: $editor.layer) {
                    ForEach(KeymapLayer.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                KeyboardCanvas(
                    color: { editor.action(for: $0.light) == nil ? plain : changed },
                    label: { key in editor.action(for: key.light).map { "\(key.name)\n→\($0.displayName)" } ?? key.name },
                    isSelected: { editor.selection == $0.light },
                    onTap: { key in
                        editor.selection = key.light
                        target = editor.action(for: key.light)?.displayName ?? ""
                        targetError = nil
                    }
                )
                .frame(minHeight: 200)
                if let key = selectedKey {
                    if key.name == "Fn" {
                        Text("Fn 键本身不能改，否则可能无法再进入 Fn 层。").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            TextField("\(key.name) 改为", text: $target, prompt: Text("如 Esc、Ctrl+C、Cmd、media:mute、mouse:left"))
                                .onSubmit(assignTarget)
                            Button("设置", action: assignTarget)
                            Button("禁用") { editor.assign(.disabled); target = "disabled" }
                            Button("恢复默认") { editor.assign(.defaultKey); target = "" }
                        }
                        if let targetError {
                            Text(targetError).foregroundStyle(.red)
                        }
                    }
                } else {
                    Text("点选一个键来修改它在当前层的功能。").foregroundStyle(.secondary)
                }
                HStack {
                    Button("写入\(editor.layer.displayName)") { confirmsApply = true }
                    Button("两层恢复默认") { confirmsReset = true }
                }
                .disabled(capability.state != .experimental)
            }
            Section("说明") {
                Text("键盘不提供读取改键的命令，这里只显示本次在页面上做的修改。写入时整层替换：图上没有标橙色的键都会恢复默认，之前写入这一层的改键会被清除。")
                    .foregroundStyle(.secondary)
                Text("媒体键：" + MediaKey.allCases.map { "media:" + $0.cliName }.joined(separator: " ") + "\n鼠标：" + MouseAction.allCases.map { "mouse:" + $0.cliName }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("改键")
        .padding()
        .alert("将\(editor.layer.displayName)写入键盘？", isPresented: $confirmsApply) {
            Button("取消", role: .cancel) {}
            Button("写入") { model.applyKeymap(editor.request()) }
        } message: {
            Text("实验性功能：整层替换，未标橙色的键恢复默认。")
        }
        .alert("两层改键都恢复默认？", isPresented: $confirmsReset) {
            Button("取消", role: .cancel) {}
            Button("恢复") {
                model.resetKeymap()
                for layer in KeymapLayer.allCases {
                    editor.layer = layer
                    editor.clearLayer()
                }
                editor.layer = .base
            }
        } message: {
            Text("与 Windows 驱动的“重置键盘”相同：普通层和 Fn 层的全部改键都会清除。")
        }
    }

    private func assignTarget() {
        guard let action = KeyAction(target: target) else {
            targetError = "无法识别「\(target)」。"
            return
        }
        targetError = nil
        editor.assign(action)
    }
}

private struct LiveView: View {
    private enum Choice: String, CaseIterable {
        case wave = "彩虹波浪"
        case breathing = "呼吸"
        case starry = "繁星"
        case solid = "纯色"
        case music = "音乐律动"
    }

    @ObservedObject var model: ControlCenterModel
    @State private var choice = Choice.wave
    @State private var color = RGBColor(red: 0x00, green: 0x80, blue: 0xff)
    @State private var speed = 3

    private var request: LiveRequest {
        switch choice {
        case .wave: return LiveRequest(effect: .wave, speed: speed)
        case .breathing: return LiveRequest(effect: .breathing(color), speed: speed)
        case .starry: return LiveRequest(effect: .starry(color), speed: speed)
        case .solid: return LiveRequest(effect: .solid(color))
        case .music: return LiveRequest(effect: .music)
        }
    }

    var body: some View {
        Form {
            Section("实时灯效") {
                Text("由这台 Mac 逐帧推送，键盘不保存；停止或离开本页后，键盘立即恢复原来的灯效。效果由本项目设计，与 Windows 驱动的同名效果不同。")
                    .foregroundStyle(.secondary)
                Picker("效果", selection: $choice) {
                    ForEach(Choice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isStreaming)
                if choice == .music {
                    Text("按这台 Mac 正在播放的声音显示频谱：低音在左、高音在右，音量越大亮得越高。需要 macOS 14.2 或更高版本，首次使用会请求系统录音权限；声音不会被录制或保存。")
                        .foregroundStyle(.secondary)
                }
                if choice != .wave && choice != .music {
                    ColorPicker("颜色", selection: Binding(
                        get: { color.cgColor },
                        set: { if let picked = RGBColor(cgColor: $0) { color = picked } }
                    ), supportsOpacity: false)
                    .disabled(model.isStreaming)
                }
                if choice != .solid && choice != .music {
                    Picker("速度（1 最慢，5 最快）", selection: $speed) {
                        ForEach(LiveAnimation.speeds, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isStreaming)
                }
                if model.isStreaming {
                    Button("停止") { model.stopLive() }
                } else {
                    Button("开始") { model.startLive(request) }
                        .disabled(model.snapshot.connection != .usbWired)
                }
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("实时灯效")
        .padding()
        .onDisappear { model.stopLive() }
    }
}

private struct ScreenView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var frames = [ScreenImage.testPattern()]
    @State private var sourceName = "测试图"
    @State private var importing = false
    @State private var confirmsUpload = false
    @State private var loadError: String?

    private var capability: AK35iCapability { model.snapshot.capability(.screenUpload) }
    private var blockCount: Int { (try? ScreenProtocol.upload(frames: frames).blocks.count) ?? 0 }

    var body: some View {
        Form {
            Section("屏幕 GIF 页") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    Image(decorative: ScreenImage.preview(of: frames[0]), scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 202.5)
                        .border(Color.secondary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sourceName).fontWeight(.medium)
                        Text("\(frames.count) 帧 · \(blockCount) 块 · 约 \(Int((Double(blockCount) * 0.16).rounded(.up))) 秒")
                            .foregroundStyle(.secondary)
                        Text("预览为键盘上的实际效果（240×135，RGB565）。").font(.caption).foregroundStyle(.secondary)
                        Text("屏幕是 16:9 横屏，建议用 16:9 的图片（如 1920×1080 或 240×135）铺满；其他比例会等比缩小，空出的部分显示黑边。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let loadError {
                    Text(loadError).foregroundStyle(.red)
                }
                HStack {
                    Button("选择图片或 GIF…") { importing = true }
                    Button("使用测试图") {
                        frames = [ScreenImage.testPattern()]
                        sourceName = "测试图"
                        loadError = nil
                    }
                }
                .disabled(model.screenProgress != nil)
                if let progress = model.screenProgress {
                    ProgressView(value: progress) { Text("正在上传") }
                } else {
                    Button("上传到键盘") { confirmsUpload = true }
                        .disabled(capability.state != .experimental)
                }
            }
            Section("说明") {
                Text("上传只覆盖屏幕的 GIF 页（外置闪存 0x950000）。在这台键盘上实测：上传后屏幕立即显示新内容；拔插后上电仍播放出厂开机动画，随后回到原来的界面。上传内容断电后保留，按 Fn+PrtSc 切到 GIF 页查看，再按一次返回主页面。GIF 页原来的内容无法读回，覆盖后不能恢复。超过 \(ScreenProtocol.maxFrames) 帧的 GIF 只保留前 \(ScreenProtocol.maxFrames) 帧。")
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("屏幕")
        .padding()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let loaded = try ScreenImage.frames(from: Data(contentsOf: url))
                frames = Array(loaded.prefix(ScreenProtocol.maxFrames))
                sourceName = url.lastPathComponent + (loaded.count > ScreenProtocol.maxFrames ? "（已截取前 \(ScreenProtocol.maxFrames) 帧）" : "")
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
        .alert("上传到键盘屏幕？", isPresented: $confirmsUpload) {
            Button("取消", role: .cancel) {}
            Button("上传") { model.uploadScreen(frames) }
        } message: {
            Text("实验性功能：将覆盖屏幕 GIF 页，原内容无法恢复。上传期间请勿拔线。")
        }
    }
}

private struct MacroRow: Identifiable {
    let id = UUID()
    var script = ""
}

private struct MacroView: View {
    @ObservedObject var model: ControlCenterModel
    @State private var rows = [MacroRow()]
    @State private var confirmsApply = false
    @State private var confirmsClear = false

    private var capability: AK35iCapability { model.snapshot.capability(.macros) }

    private var parsed: [Result<Macro, Error>] {
        rows.map { row in Result { try Macro(script: row.script) } }
    }

    private var macros: [Macro]? {
        try? parsed.map { try $0.get() }
    }

    var body: some View {
        Form {
            Section("板载宏") {
                LabeledContent("协议状态", value: AK35iApplication.capabilityStateName(capability.state))
                Text(capability.detail).foregroundStyle(.secondary)
                ForEach($rows) { $row in
                    let index = rows.firstIndex { $0.id == row.id } ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("宏 \(index + 1)", text: $row.script, prompt: Text("如 Cmd+Space, 100ms, A"))
                            Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .disabled(rows.count == 1)
                        }
                        switch Result(catching: { try Macro(script: row.script) }) {
                        case .success(let macro):
                            Text("macro:\(index + 1) · \(macro.steps.count) 个事件").font(.caption).foregroundStyle(.secondary)
                        case .failure(let error):
                            Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                HStack {
                    Button("添加宏") { rows.append(MacroRow()) }
                        .disabled(rows.count >= MacroProtocol.maxMacros)
                    Button("写入键盘") { confirmsApply = true }
                        .disabled(capability.state != .experimental || macros == nil)
                    Button("清空键盘上的宏") { confirmsClear = true }
                        .disabled(capability.state != .experimental)
                }
            }
            Section("写法") {
                Text("步骤用逗号分隔：A 点按一个键；+A / -A 只按下或只松开；Cmd+Space 点按组合；mouse:left / mouse:right / mouse:middle 鼠标点击；100ms 设置上一步之后的等待（默认 \(Macro.defaultDelay) ms）。宏结束时所有按下的键都必须松开。")
                    .foregroundStyle(.secondary)
                Text("宏要绑定到键才会播放：在“改键”页把某个键设为 macro:N，也可写 macro:N:x3（播放 3 次）、macro:N:toggle（再按停止）、macro:N:hold（按住重复）。")
                    .foregroundStyle(.secondary)
                Text("键盘不提供读取宏的命令，这里只显示本次输入的内容。写入会替换键盘上的全部宏。")
                    .foregroundStyle(.secondary)
            }
            Section("状态") { Text(model.message) }
        }
        .formStyle(.grouped)
        .navigationTitle("宏")
        .padding()
        .alert("将 \(rows.count) 个宏写入键盘？", isPresented: $confirmsApply) {
            Button("取消", role: .cancel) {}
            Button("写入") { if let macros { model.applyMacros(macros) } }
        } message: {
            Text("实验性功能：替换键盘上的全部宏。")
        }
        .alert("清空键盘上的宏？", isPresented: $confirmsClear) {
            Button("取消", role: .cancel) {}
            Button("清空") { model.applyMacros([]) }
        } message: {
            Text("键盘上的全部宏都会删除；绑定了宏的键将不再播放。")
        }
    }
}

/// Keys drawn at their rectangles in the driver's layout image.
private struct KeyboardCanvas: View {
    let color: (KeyboardKey) -> RGBColor
    let label: (KeyboardKey) -> String
    let isSelected: (KeyboardKey) -> Bool
    let onTap: (KeyboardKey) -> Void
    private static let origin = CGPoint(x: 30, y: 48)
    private static let extent = CGSize(width: 740, height: 212)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.extent.width, proxy.size.height / Self.extent.height)
            ZStack(alignment: .topLeading) {
                ForEach(KeyboardLayout.keys, id: \.light) { key in
                    KeyCap(
                        key: key,
                        label: label(key),
                        color: color(key),
                        selected: isSelected(key),
                        scale: scale
                    )
                    .offset(x: (CGFloat(key.x) - Self.origin.x) * scale, y: (CGFloat(key.y) - Self.origin.y) * scale)
                    .onTapGesture { onTap(key) }
                }
            }
        }
        .aspectRatio(Self.extent.width / Self.extent.height, contentMode: .fit)
    }
}

private struct KeyCap: View {
    let key: KeyboardKey
    let label: String
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
                Text(label)
                    .font(.system(size: 7 * scale))
                    .lineLimit(2)
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
