import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class RealtimeLightingTests: XCTestCase {
    /// Frame layout of DeviceDriver.exe 0x428110 with rgb_keyboard = 1.
    func testFrameListsEveryKeySequentiallyWithoutTrailer() {
        let blue = RGBColor(red: 0, green: 0, blue: 0xff)
        let packets = RealtimeFrameProtocol.packets(colors: [1: blue, 123: blue])
        let block = packets[1...8].flatMap { $0.report.dropFirst() }

        XCTAssertEqual(packets.count, 10)
        XCTAssertEqual(packets.map(\.expectsAck), [true] + Array(repeating: false, count: 8) + [true])
        XCTAssertEqual(Array(packets[0].report[1...9]), [0x04, 0x20, 0, 0, 0, 0, 0, 0, 8])
        XCTAssertEqual(Array(packets[9].report[1...2]), [0x04, 0x02])
        XCTAssertEqual(block.count, 512)
        XCTAssertEqual(Array(block[0...3]), [1, 0, 0, 0xff], "Esc comes first in layout order")
        XCTAssertEqual(Array(block[4...7]), [2, 0, 0, 0])
        XCTAssertEqual(stride(from: 0, to: 416, by: 4).map { block[$0] }, KeyboardLayout.keys.map(\.light))
        XCTAssertTrue(block[416...].allSatisfy { $0 == 0 })
        XCTAssertEqual(block.firstIndex(of: 123).map { Array(block[$0...$0 + 3]) }, [123, 0, 0, 0xff])
    }

    private let red = RGBColor(red: 0xff, green: 0, blue: 0)
    private let blue = RGBColor(red: 0, green: 0, blue: 0xff)

    /// The driver steps its effect every (15 − speed) × 16 ms; frames show
    /// the effect after however many steps are due.
    func testDriverEffectStepsAtTheSpeedInterval() {
        var animation = LiveAnimation(request: LiveRequest(effect: .driver(.fountain), speed: 13))
        var engine = DriverLightEngine(effect: .fountain, color: red, colorful: true)

        XCTAssertEqual(animation.frame(at: 0), engine.frame)
        for _ in 0..<3 { engine.step() }
        XCTAssertEqual(animation.frame(at: 0.1), engine.frame, "0.1 s at 32 ms a step is 3 steps")
        engine.step()
        XCTAssertEqual(animation.frame(at: 0.13), engine.frame)
    }

    func testChosenColourWithoutColourfulStaysSingleColour() {
        var animation = LiveAnimation(request: LiveRequest(effect: .driver(.staticOn), color: blue, colorful: false))
        let frame = animation.frame(at: 1.5)

        XCTAssertEqual(frame.count, 104)
        XCTAssertTrue(frame.values.allSatisfy { $0 == RGBColor(red: 0, green: 0, blue: 0xfe) })
    }

    func testParsesLiveCommands() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "static", "--color", "0000ff", "--seconds", "5"]),
            .live(LiveRequest(effect: .driver(.staticOn), color: blue, colorful: false, seconds: 5))
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "breathing", "--speed", "5"]),
            .live(LiveRequest(effect: .driver(.breathing), speed: 5))
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "wave"]),
            .live(LiveRequest(effect: .driver(.rainbowWave), color: red, colorful: true, speed: 15)),
            "driver defaults: red, colourful, fastest"
        )
        for effect in DriverLightEffect.allCases {
            XCTAssertEqual(try AK35iCommandParser.parse(["live", effect.cliName]), .live(LiveRequest(effect: .driver(effect))))
        }
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "solid"]), .live(LiveRequest(effect: .driver(.staticOn))))
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "starry"]), .live(LiveRequest(effect: .driver(.starlight))))
        for arguments in [
            ["live"], ["live", "fireworks"], ["live", "static", "--seconds", "0"], ["live", "static", "--color", "blue"],
            ["live", "static", "--speed", "3"], ["live", "fluttering", "--color", "ff0000"],
            ["live", "wave", "--speed", "0"], ["live", "wave", "--speed", "16"], ["live", "wave", "--speed", "3", "--speed", "4"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)")
        }
    }
}
