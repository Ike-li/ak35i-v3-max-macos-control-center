import CoreBluetooth
import Foundation
import IOKit

enum BluetoothBatteryError: LocalizedError {
    case notConnected
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未找到经蓝牙连接的 AK35i。"
        case .unavailable:
            return "无法使用蓝牙：请在系统设置 › 隐私与安全性 › 蓝牙中允许本程序，并确认蓝牙已打开。"
        case .timedOut:
            return "读取蓝牙电量超时。"
        }
    }
}

/// The keyboard on Bluetooth (0C45:FEFE, “AK35i BT-1/2/3”) and its standard
/// Battery Service (0x180F, Battery Level 0x2A19), the only data it offers there.
enum BluetoothBattery {
    static let productID = 0xfefe

    static func level(from value: Data) -> Int? {
        value.first.map { min(Int($0), 100) }
    }

    /// Looks the keyboard up in the IORegistry without opening it, so no
    /// Input Monitoring consent is needed.
    static func isKeyboardConnected() -> Bool {
        let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = AK35iHIDClockTransport.vendorID
        matching[kIOHIDProductIDKey] = productID
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }

    static func read(timeout: TimeInterval = 5) throws -> Int {
        let value = try BluetoothCharacteristicReader(service: "180F", characteristic: "2A19").read(timeout: timeout)
        guard let level = level(from: value) else { throw BluetoothBatteryError.notConnected }
        return level
    }

    /// Software Revision of the Bluetooth module (Device Information 0x2A28),
    /// for example “2024.07.26 SVN0138”; the keyboard's controller firmware is
    /// not visible over Bluetooth.
    static func moduleSoftwareRevision(timeout: TimeInterval = 5) throws -> String {
        let value = try BluetoothCharacteristicReader(service: "180A", characteristic: "2A28").read(timeout: timeout)
        return String(decoding: value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}

/// Reads one characteristic once from the connected keyboard. The system
/// keeps its own HID connection; cancelling ours afterwards does not
/// disconnect it. Never writes.
private final class BluetoothCharacteristicReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private let service: CBUUID
    private let characteristic: CBUUID

    init(service: String, characteristic: String) {
        self.service = CBUUID(string: service)
        self.characteristic = CBUUID(string: characteristic)
    }

    private let queue = DispatchQueue(label: "dev.ak35i.bluetooth-battery")
    private let finished = DispatchSemaphore(value: 0)
    private var central: CBCentralManager?
    private var keyboard: CBPeripheral?
    private var result: Result<Data, Error>?

    func read(timeout: TimeInterval) throws -> Data {
        queue.sync { central = CBCentralManager(delegate: self, queue: queue) }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            queue.sync { finish(.failure(BluetoothBatteryError.timedOut)) }
            throw BluetoothBatteryError.timedOut
        }
        return try queue.sync { result! }.get()
    }

    private func finish(_ outcome: Result<Data, Error>) {
        guard result == nil else { return }
        result = outcome
        if let keyboard { central?.cancelPeripheralConnection(keyboard) }
        finished.signal()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            let connected = central.retrieveConnectedPeripherals(withServices: [service])
            guard let keyboard = connected.first(where: { ($0.name ?? "").hasPrefix("AK35i BT") }) else {
                return finish(.failure(BluetoothBatteryError.notConnected))
            }
            self.keyboard = keyboard
            keyboard.delegate = self
            central.connect(keyboard)
        case .unauthorized, .unsupported, .poweredOff:
            finish(.failure(BluetoothBatteryError.unavailable))
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(.failure(error ?? BluetoothBatteryError.notConnected))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let found = peripheral.services?.first(where: { $0.uuid == service }) else {
            return finish(.failure(error ?? BluetoothBatteryError.notConnected))
        }
        peripheral.discoverCharacteristics([characteristic], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let wanted = service.characteristics?.first(where: { $0.uuid == characteristic }) else {
            return finish(.failure(error ?? BluetoothBatteryError.notConnected))
        }
        peripheral.readValue(for: wanted)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else {
            return finish(.failure(error ?? BluetoothBatteryError.notConnected))
        }
        finish(.success(value))
    }
}
