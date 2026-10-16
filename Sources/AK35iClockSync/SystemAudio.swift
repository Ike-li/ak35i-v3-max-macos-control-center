import AudioToolbox
import CoreAudio
import Foundation

enum SystemAudioError: LocalizedError {
    case unsupportedSystem
    case coreAudio(String, OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "音乐律动需要 macOS 14.2 或更高版本（系统音频采集）。"
        case .coreAudio(let step, let status):
            return "\(step)失败（Core Audio 错误 \(status)）。如果是权限问题，请在“系统设置 › 隐私与安全性 › 屏幕与系统录音”里允许本程序或终端录制系统音频。"
        case .unsupportedFormat:
            return "系统音频不是 32 位浮点格式，无法分析。"
        }
    }
}

/// Captures what the Mac is playing through a private Core Audio process tap
/// on the default output device. Nothing is recorded or stored; only the
/// latest window of mono samples is kept for the spectrum.
@available(macOS 14.2, *)
final class SystemAudioCapture: AudioSampleSource, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate = 48_000.0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    func latestSamples() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, sampleRate)
    }

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "AK35i 音乐律动"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "创建系统音频采集")

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AK35i 音乐律动",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "创建采集设备")

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "读取音频格式")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw SystemAudioError.unsupportedFormat
        }
        lock.lock()
        sampleRate = format.mSampleRate
        lock.unlock()

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, input, _, _, _ in
            self?.append(input)
        }, "注册音频回调")
        try check(AudioDeviceStart(aggregateID, procID), "开始采集")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Mixes every channel of every buffer down to mono.
    private func append(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var mono: [Float] = []
        var channels = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let stride = max(Int(buffer.mNumberChannels), 1)
            let values = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
            let frames = count / stride
            if mono.count < frames { mono += Array(repeating: 0, count: frames - mono.count) }
            for frame in 0..<frames {
                for channel in 0..<stride { mono[frame] += values[frame * stride + channel] }
            }
            channels += stride
        }
        guard channels > 0, !mono.isEmpty else { return }
        let scale = 1 / Float(channels)
        lock.lock()
        samples += mono.map { $0 * scale }
        if samples.count > SpectrumAnalyzer.windowLength { samples.removeFirst(samples.count - SpectrumAnalyzer.windowLength) }
        lock.unlock()
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw SystemAudioError.coreAudio(step, status) }
    }

    private static func defaultOutputUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw SystemAudioError.coreAudio("查找默认输出设备", status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw SystemAudioError.coreAudio("读取输出设备标识", status) }
        return uid.takeRetainedValue() as String
    }
}
