import XCTest
@testable import AK35iClockSync

final class BluetoothTests: XCTestCase {
    private let wired = AK35iDeviceSnapshot.from(interfaces: [
        HIDInterfaceSnapshot(usagePage: 0xff13, usage: 0x0001, maxFeatureReportSize: 64, maxOutputReportSize: 64),
    ])

    /// The keyboard is in one mode at a time; a receiver may stay plugged in
    /// while it is on Bluetooth, and then only Bluetooth reaches it.
    func testPrefersTheCableThenBluetoothThenTheReceiver() {
        XCTAssertEqual(AK35iDeviceSnapshot.resolve(wired: wired, bluetoothConnected: true, receiverAttached: true).connection, .usbWired)
        XCTAssertEqual(AK35iDeviceSnapshot.resolve(wired: .disconnected, bluetoothConnected: true, receiverAttached: true).connection, .bluetooth)
        XCTAssertEqual(AK35iDeviceSnapshot.resolve(wired: .disconnected, bluetoothConnected: false, receiverAttached: true).connection, .wireless)
        XCTAssertEqual(AK35iDeviceSnapshot.resolve(wired: .disconnected, bluetoothConnected: false, receiverAttached: false).connection, .disconnected)
    }

    /// Over Bluetooth the keyboard exposes no vendor report and drops vendor
    /// frames, but offers the standard Battery Service.
    func testBluetoothOffersOnlyTheBattery() {
        let snapshot = AK35iDeviceSnapshot.bluetooth
        XCTAssertEqual(snapshot.capability(.battery).state, .experimental)
        for feature in [AK35iFeature.clock, .lighting, .perKeyLighting, .systemSettings, .screenUpload, .keymap, .macros] {
            XCTAssertEqual(snapshot.capability(feature).state, .notConnected, "\(feature)")
        }
    }

    /// Battery Level (0x2A19) is one byte, 0–100.
    func testReadsTheBatteryLevelCharacteristic() {
        XCTAssertEqual(BluetoothBattery.level(from: Data([0x5e])), 94)
        XCTAssertEqual(BluetoothBattery.level(from: Data([0xc8])), 100)
        XCTAssertNil(BluetoothBattery.level(from: Data()))
    }
}
