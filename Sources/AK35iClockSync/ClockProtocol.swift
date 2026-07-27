import Foundation

struct ClockTime: Equatable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    let weekday: Int

    static func from(_ date: Date, timeZone: TimeZone) -> ClockTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        return ClockTime(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            day: components.day ?? 1,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            weekday: max(0, (components.weekday ?? 1) - 1)
        )
    }
}

enum ClockProtocol {
    static let reportLength = 65

    static func reports(for time: ClockTime) -> [[UInt8]] {
        var start = blankReport()
        start[1] = 0x04
        start[2] = 0x18

        var preamble = blankReport()
        preamble[1] = 0x04
        preamble[2] = 0x28
        preamble[9] = 0x01

        var data = blankReport()
        data[2] = 0x01
        data[3] = 0x5a
        data[4] = yearOffset(time.year)
        data[5] = UInt8(time.month)
        data[6] = UInt8(time.day)
        data[7] = UInt8(time.hour)
        data[8] = UInt8(time.minute)
        data[9] = UInt8(time.second)
        data[11] = UInt8(clamping: time.weekday)
        data[63] = 0xaa
        data[64] = 0x55

        var save = blankReport()
        save[1] = 0x04
        save[2] = 0x02

        return [start, preamble, data, save]
    }

    private static func blankReport() -> [UInt8] {
        Array(repeating: 0, count: reportLength)
    }

    private static func yearOffset(_ year: Int) -> UInt8 {
        if year < 2000 { return 0 }
        if year >= 2255 { return 0xff }
        return UInt8(year - 2000)
    }
}

enum HIDFeatureReport {
    /// hidapi represents an unnumbered HID report with a leading zero byte.
    /// IOKit receives the report ID separately, so it must be omitted from the
    /// data buffer passed to IOHIDDeviceSetReport/GetReport.
    static func macOSPayload(from report: [UInt8]) -> [UInt8] {
        precondition(report.first == 0, "AK35i RTC reports are unnumbered")
        return Array(report.dropFirst())
    }
}
