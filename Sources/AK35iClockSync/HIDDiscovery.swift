import Foundation
import IOKit
import IOKit.hid

enum HIDDiscoveryError: LocalizedError {
    case managerOpenFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .managerOpenFailed(let status):
            let code = String(format: "0x%08X", UInt32(bitPattern: status))
            return "无法打开 HID 管理器（\(code)）。"
        }
    }
}

struct AK35iHIDUsage: Equatable {
    let usagePage: Int
    let usage: Int
}

struct AK35iHIDDeviceDiscovery {
    /// Restrict discovery to non-keyboard vendor collections. Matching only by
    /// VID/PID also includes the standard keyboard collection, which macOS
    /// protects with Input Monitoring consent for graphical applications.
    static let discoveryCollections = [
        AK35iHIDUsage(
            usagePage: AK35iHIDClockTransport.controlUsagePage,
            usage: AK35iHIDClockTransport.controlUsage
        ),
        AK35iHIDUsage(usagePage: 0xff68, usage: 0x0061),
    ]

    func snapshot() throws -> AK35iDeviceSnapshot {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = Self.discoveryCollections.map { collection in
            [
                kIOHIDVendorIDKey as String: AK35iHIDClockTransport.vendorID,
                kIOHIDProductIDKey as String: AK35iHIDClockTransport.productID,
                kIOHIDPrimaryUsagePageKey as String: collection.usagePage,
                kIOHIDPrimaryUsageKey as String: collection.usage,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDDiscoveryError.managerOpenFailed(status) }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let devices = ((IOHIDManagerCopyDevices(manager) as NSSet?)?.allObjects as? [IOHIDDevice]) ?? []
        return AK35iDeviceSnapshot.from(interfaces: devices.map(HIDInterfaceSnapshot.init(device:)))
    }
}

private extension HIDInterfaceSnapshot {
    init(device: IOHIDDevice) {
        func intProperty(_ key: CFString) -> Int {
            (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
        }
        func stringProperty(_ key: CFString) -> String? {
            IOHIDDeviceGetProperty(device, key) as? String
        }

        self.init(
            usagePage: intProperty(kIOHIDPrimaryUsagePageKey as CFString),
            usage: intProperty(kIOHIDPrimaryUsageKey as CFString),
            maxFeatureReportSize: intProperty(kIOHIDMaxFeatureReportSizeKey as CFString),
            maxOutputReportSize: intProperty(kIOHIDMaxOutputReportSizeKey as CFString),
            product: stringProperty(kIOHIDProductKey as CFString) ?? "USB KEYBOARD",
            transport: stringProperty(kIOHIDTransportKey as CFString) ?? "USB",
            serialNumber: nil
        )
    }
}
