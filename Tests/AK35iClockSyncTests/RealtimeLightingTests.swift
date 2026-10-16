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

    func testSolidEffectLightsEveryKey() {
        let blue = RGBColor(red: 0, green: 0, blue: 0xff)
        var animation = LiveAnimation(request: LiveRequest(effect: .solid(blue)))
        let frame = animation.frame(at: 1.5)

        XCTAssertEqual(frame.count, 104)
        XCTAssertTrue(frame.values.allSatisfy { $0 == blue })
    }

    func testParsesLiveCommands() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "solid", "--color", "0000ff", "--seconds", "5"]),
            .live(LiveRequest(effect: .solid(RGBColor(red: 0, green: 0, blue: 0xff)), seconds: 5))
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "solid"]),
            .live(LiveRequest(effect: .solid(RGBColor(red: 0xff, green: 0xff, blue: 0xff))))
        )
        for arguments in [["live"], ["live", "fireworks"], ["live", "solid", "--seconds", "0"], ["live", "solid", "--color", "blue"]] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)")
        }
    }

    private let black = RGBColor(red: 0, green: 0, blue: 0)
    private let teal = RGBColor(red: 0, green: 0x80, blue: 0xff)

    func testBreathingFadesBetweenDarkAndTheChosenColour() {
        var animation = LiveAnimation(request: LiveRequest(effect: .breathing(teal), speed: 3))
        let period = LiveAnimation.period(speed: 3)

        XCTAssertTrue(animation.frame(at: 0).values.allSatisfy { $0 == black })
        XCTAssertTrue(animation.frame(at: period / 2).values.allSatisfy { $0 == teal })
        XCTAssertTrue(animation.frame(at: period).values.allSatisfy { $0 == black })
        let quarter = animation.frame(at: period / 4)[1]!
        XCTAssertTrue(quarter.blue > 0 && quarter.blue < 0xff)
        XCTAssertGreaterThan(LiveAnimation.period(speed: 1), LiveAnimation.period(speed: 5))
    }

    func testWaveMovesARainbowAcrossTheKeyboard() {
        var animation = LiveAnimation(request: LiveRequest(effect: .wave, speed: 2))
        let period = LiveAnimation.period(speed: 2)
        let start = animation.frame(at: 0)
        let light = { KeyboardLayout.light(named: $0)! }

        XCTAssertEqual(start.count, 104)
        XCTAssertEqual(start[light("Esc")], start[light("Grave")], "same column, same colour")
        XCTAssertNotEqual(start[light("Esc")], start[light("NumMinus")])
        XCTAssertTrue(start.values.allSatisfy { max($0.red, $0.green, $0.blue) == 0xff })
        XCTAssertNotEqual(animation.frame(at: period / 3), start)
        XCTAssertEqual(animation.frame(at: period), start)
    }

    func testStarsTwinkleInTheChosenColour() {
        var animation = LiveAnimation(request: LiveRequest(effect: .starry(teal)), generator: SeededGenerator(seed: 7))
        var litCounts: [Int] = []
        for step in 0..<90 {
            let frame = animation.frame(at: Double(step) / 30)
            let lit = frame.values.filter { $0 != black }
            XCTAssertTrue(lit.allSatisfy { $0.red == 0 && $0.green <= 0x80 && $0.blue > 0 })
            litCounts.append(lit.count)
        }
        XCTAssertGreaterThan(litCounts.max()!, 0)
        XCTAssertLessThan(litCounts.max()!, 40)
    }

    func testParsesEveryLiveEffect() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse(["live", "breathing", "--color", "0080ff", "--speed", "5"]),
            .live(LiveRequest(effect: .breathing(teal), speed: 5))
        )
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "wave", "--seconds", "10"]), .live(LiveRequest(effect: .wave, seconds: 10)))
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "starry"]), .live(LiveRequest(effect: .starry(RGBColor(red: 0xff, green: 0xff, blue: 0xff)))))
        for arguments in [["live", "wave", "--color", "ff0000"], ["live", "starry", "--speed", "6"], ["live", "breathing", "--speed", "0"]] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)")
        }
    }
}

/// Deterministic stand-in for the system random source.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
