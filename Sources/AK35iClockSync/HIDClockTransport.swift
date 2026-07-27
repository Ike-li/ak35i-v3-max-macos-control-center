import Foundation
import IOKit
import IOKit.hid

enum HIDClockError: LocalizedError {
    case deviceNotFound
    case ambiguousDevice(count: Int)
    case managerOpenFailed(IOReturn)
    case deviceOpenFailed(IOReturn)
    case featureWriteFailed(packet: Int, status: IOReturn)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未找到 AK35i V3 Max 的有线控制接口。请确认键盘已用数据线连接，并切到 USB 模式。"
        case .ambiguousDevice(let count):
            return "发现了 \(count) 个匹配的 HID 控制接口；为避免写错设备，已停止。"
        case .managerOpenFailed(let status):
            return "无法打开 HID 管理器（\(formatted(status))）。"
        case .deviceOpenFailed(let status):
            return "无法打开键盘的 HID 控制接口（\(formatted(status))）。"
        case .featureWriteFailed(let packet, let status):
            return "第 \(packet) 个时钟报文未写入（\(formatted(status))）。"
        }
    }

    private func formatted(_ status: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }
}

final class AK35iHIDClockTransport {
    static let vendorID = 0x0c45
    static let productID = 0x8009
    static let controlUsagePage = 0xff13
    static let controlUsage = 0x0001

    private let manager: IOHIDManager
    private let device: IOHIDDevice

    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
            kIOHIDPrimaryUsagePageKey as String: Self.controlUsagePage,
            kIOHIDPrimaryUsageKey as String: Self.controlUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let managerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerStatus == kIOReturnSuccess else {
            throw HIDClockError.managerOpenFailed(managerStatus)
        }

        let devices: [IOHIDDevice] = ((IOHIDManagerCopyDevices(manager) as NSSet?)?.allObjects as? [IOHIDDevice]) ?? []
        guard !devices.isEmpty else { throw HIDClockError.deviceNotFound }
        guard devices.count == 1 else { throw HIDClockError.ambiguousDevice(count: devices.count) }

        device = devices[0]
        let deviceStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceStatus == kIOReturnSuccess else {
            throw HIDClockError.deviceOpenFailed(deviceStatus)
        }
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func description() -> String {
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "AK35i"
        return "\(name) (VID:PID \(String(format: "%04X:%04X", Self.vendorID, Self.productID)))"
    }

    func writeFeature(_ report: [UInt8], packetIndex: Int) throws {
        let payload = HIDFeatureReport.macOSPayload(from: report)
        let status = payload.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                0,
                buffer.baseAddress!,
                buffer.count
            )
        }
        guard status == kIOReturnSuccess else {
            throw HIDClockError.featureWriteFailed(packet: packetIndex, status: status)
        }
    }

    func readFeatureBestEffort() {
        var report = Array(repeating: UInt8(0), count: ClockProtocol.reportLength - 1)
        var length = report.count
        _ = report.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                0,
                buffer.baseAddress!,
                &length
            )
        }
    }
}
