import Foundation
import IOKit
import IOKit.hid

enum ScreenTransportError: LocalizedError {
    case blockWriteFailed(block: Int, status: IOReturn)

    var errorDescription: String? {
        switch self {
        case .blockWriteFailed(let block, let status):
            return "第 \(block) 块屏幕数据未写入（\(String(format: "0x%08X", UInt32(bitPattern: status)))）。"
        }
    }
}

/// The 4 KiB Output interface (usage page 0xFF68, usage 0x61) that carries
/// screen images. The firmware answers each block with a short Input report
/// once it has written the block to flash; the driver waits up to 300 ms.
final class AK35iScreenTransport {
    static let usagePage = 0xff68
    static let usage = 0x0061

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private var replies: [[UInt8]] = []

    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: AK35iHIDClockTransport.vendorID,
            kIOHIDProductIDKey as String: AK35iHIDClockTransport.productID,
            kIOHIDPrimaryUsagePageKey as String: Self.usagePage,
            kIOHIDPrimaryUsageKey as String: Self.usage,
        ] as CFDictionary)
        let managerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerStatus == kIOReturnSuccess else { throw HIDClockError.managerOpenFailed(managerStatus) }

        let devices = ((IOHIDManagerCopyDevices(manager) as NSSet?)?.allObjects as? [IOHIDDevice]) ?? []
        guard !devices.isEmpty else { throw HIDClockError.deviceNotFound }
        guard devices.count == 1 else { throw HIDClockError.ambiguousDevice(count: devices.count) }
        device = devices[0]
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDClockError.deviceOpenFailed(status) }

        let context = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceRegisterInputReportCallback(device, buffer.baseAddress!, buffer.count, { context, _, _, _, _, report, length in
                guard let context else { return }
                let transport = Unmanaged<AK35iScreenTransport>.fromOpaque(context).takeUnretainedValue()
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

    /// Writes one 4096-byte block and waits for the keyboard's reply.
    /// Returns the reply, or nil when none arrived in time.
    func send(block: [UInt8], index: Int, timeout: TimeInterval = 1.0) throws -> [UInt8]? {
        replies.removeAll()
        let status = block.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
        guard status == kIOReturnSuccess else { throw ScreenTransportError.blockWriteFailed(block: index, status: status) }
        let deadline = Date().addingTimeInterval(timeout)
        while replies.isEmpty, Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        return replies.first
    }
}
