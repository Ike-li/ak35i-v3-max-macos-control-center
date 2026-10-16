import Foundation
import IOKit
import IOKit.hid

/// The information block at firmware 0x8F80: `40 30 00 00`, then VID, PID and
/// the firmware version, little endian (layout per dantje/ajazz-ak35i-v3-max).
/// The 2.4G probe `02 00` (DeviceDriver.exe 0x450360) returns it from byte 3.
struct FirmwareInfo: Equatable {
    let vendorID: Int
    let productID: Int
    let version: Int

    init(vendorID: Int, productID: Int, version: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.version = version
    }

    init?(block: [UInt8]) {
        guard block.count >= 10, Array(block[0..<4]) == [0x40, 0x30, 0x00, 0x00] else { return nil }
        func word(_ index: Int) -> Int { Int(block[index]) | Int(block[index + 1]) << 8 }
        self.init(vendorID: word(4), productID: word(6), version: word(8))
    }

    init?(probeReply: [UInt8]) {
        guard probeReply.count >= 13, probeReply.starts(with: WirelessProtocol.probe.prefix(3)) else { return nil }
        self.init(block: Array(probeReply[3...]))
    }

    /// 0x0130 is V1.30.
    static func versionText(_ version: Int) -> String {
        String(format: "V%X.%02X", version >> 8, version & 0xff)
    }

    var versionText: String { Self.versionText(version) }

    /// The wired keyboard's USB device version (bcdDevice) from the
    /// IORegistry, without opening it; on this keyboard it is the controller
    /// firmware version. The driver likewise keeps a version per device from
    /// enumeration (0x4507e5) rather than asking the keyboard.
    static func usbVersionNumber() -> Int? {
        let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = AK35iHIDClockTransport.vendorID
        matching[kIOHIDProductIDKey] = AK35iHIDClockTransport.productID
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOHIDVersionNumberKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
