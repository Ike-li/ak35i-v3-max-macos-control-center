import Foundation
import IOKit
import IOKit.hid

enum ReceiverError: LocalizedError {
    case notFound
    case ambiguous(count: Int)
    case writeFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到 AK35i 的 2.4G 接收器。电量只能经接收器读取：请插上接收器，把键盘拨到 2.4G 档。"
        case .ambiguous(let count):
            return "发现了 \(count) 个可能的接收器接口；为避免发错设备，已停止。"
        case .writeFailed(let status):
            return "无法向接收器发送请求（\(String(format: "0x%08X", UInt32(bitPattern: status)))）。"
        }
    }
}

struct ReceiverInterface: Equatable {
    var vendorID: Int
    var productID: Int
    var product: String?
    var usagePage: Int
    var usage: Int
    var maxOutputReportSize: Int

    /// The 2.4G receiver's vendor interface (MI_03 in config.xml). The driver
    /// writes 33 bytes to it with WriteFile, so its Output report is 32 bytes
    /// without a report ID. config.xml lists the receiver as 0C45:FDFD, but on
    /// a Mac it has been seen as 05AC:024F named "2.4G Dongle", so both count.
    var isBatteryChannel: Bool {
        let isReceiver = (vendorID == AK35iHIDClockTransport.vendorID && productID == 0xfdfd) || product == AK35iReceiverTransport.productName
        return isReceiver && usagePage == 0xff60 && usage == 0x61 && maxOutputReportSize == BatteryProtocol.reportLength
    }
}

/// Talks to the keyboard through the receiver; answers arrive as Input reports.
final class AK35iReceiverTransport {
    static let productName = "2.4G Dongle"

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private var replies: [[UInt8]] = []

    /// Whether the receiver is plugged in, without opening it.
    static func isAttached() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return (try? batteryChannels(of: manager))?.isEmpty == false
    }

    private static func batteryChannels(of manager: IOHIDManager) throws -> [IOHIDDevice] {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDPrimaryUsagePageKey as String: 0xff60,
            kIOHIDPrimaryUsageKey as String: 0x61,
        ] as CFDictionary)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDClockError.managerOpenFailed(status) }

        let devices = ((IOHIDManagerCopyDevices(manager) as NSSet?)?.allObjects as? [IOHIDDevice]) ?? []
        return devices.filter { device in
            func number(_ key: String) -> Int { IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0 }
            return ReceiverInterface(
                vendorID: number(kIOHIDVendorIDKey),
                productID: number(kIOHIDProductIDKey),
                product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
                usagePage: number(kIOHIDPrimaryUsagePageKey),
                usage: number(kIOHIDPrimaryUsageKey),
                maxOutputReportSize: number(kIOHIDMaxOutputReportSizeKey)
            ).isBatteryChannel
        }
    }

    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let candidates = try Self.batteryChannels(of: manager)
        guard !candidates.isEmpty else { throw ReceiverError.notFound }
        guard candidates.count == 1 else { throw ReceiverError.ambiguous(count: candidates.count) }
        device = candidates[0]
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDClockError.deviceOpenFailed(status) }

        let context = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceRegisterInputReportCallback(device, buffer.baseAddress!, buffer.count, { context, _, _, _, _, report, length in
                guard let context else { return }
                let transport = Unmanaged<AK35iReceiverTransport>.fromOpaque(context).takeUnretainedValue()
                transport.replies.append(Array(UnsafeBufferPointer(start: report, count: length)))
            }, context)
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends one report and returns the first reply that echoes its first
    /// three bytes, as 0x4501c0 waits for (20 reads 10 ms apart), or nil.
    func exchange(_ report: [UInt8], timeout: TimeInterval = 0.3) throws -> [UInt8]? {
        replies.removeAll()
        let status = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
        guard status == kIOReturnSuccess else { throw ReceiverError.writeFailed(status) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let reply = replies.first(where: { $0.starts(with: report.prefix(3)) }) { return reply }
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        return replies.first(where: { $0.starts(with: report.prefix(3)) })
    }
}
