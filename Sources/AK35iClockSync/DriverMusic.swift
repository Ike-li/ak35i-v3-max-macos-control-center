import Foundation

/// Display modes of the driver's music page, numbered as the cases of its
/// renderer (DeviceDriver.exe 0x45de00). The same numbers are the firmware's
/// palette numbers in the 2.4G `0B` frame.
enum DriverMusicMode: Int, CaseIterable {
    case off = 0
    case greenYellowRed = 1
    case rainbow = 2
    case reverseRainbow = 3
    case gradient = 4
    case spectrumCycle = 5
    case white = 6
    case red = 7
    case orange = 8
    case yellow = 9
    case blue = 10
    case green = 11

    /// Language IDs 106–118.
    var displayName: String {
        switch self {
        case .off: return "无"
        case .greenYellowRed: return "绿色/黄色/红色"
        case .rainbow: return "彩虹色"
        case .reverseRainbow: return "彩虹色反向"
        case .gradient: return "色谱"
        case .spectrumCycle: return "频谱循环"
        case .white: return "白色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .blue: return "蓝色"
        case .green: return "绿色"
        }
    }

    var cliName: String {
        switch self {
        case .off: return "off"
        case .greenYellowRed: return "green-yellow-red"
        case .rainbow: return "rainbow"
        case .reverseRainbow: return "reverse-rainbow"
        case .gradient: return "gradient"
        case .spectrumCycle: return "spectrum-cycle"
        case .white: return "white"
        case .red: return "red"
        case .orange: return "orange"
        case .yellow: return "yellow"
        case .blue: return "blue"
        case .green: return "green"
        }
    }

    /// The display mode list (0x41f1b6) without Ambilight (屏光联动), which
    /// takes its colours from the screen.
    static let foregrounds: [DriverMusicMode] = [.greenYellowRed, .rainbow, .reverseRainbow, .gradient, .spectrumCycle, .white, .red, .orange, .yellow, .green, .blue]
    /// The background list (0x43b5bc).
    static let backgrounds: [DriverMusicMode] = [.off, .white, .red, .orange, .yellow, .blue, .green, .greenYellowRed, .rainbow, .reverseRainbow, .gradient, .spectrumCycle]
}

/// The music page's controls with the defaults of its settings table
/// (0x403041): Gradient over no background, gain 300, brightness 100.
struct DriverMusicSettings: Equatable {
    static let range = 0...100

    var foreground = DriverMusicMode.gradient
    var background = DriverMusicMode.off
    /// The slider; the driver's gain is five times it (0x4342c1).
    var amplitude = 60
    var backgroundBrightness = 100
}

/// The driver's music engine (page object + 0x87C): every 15 ms it updates
/// a 256-level spectrum from the system audio (0x45d060), renders the
/// foreground and background on 256 × 64 canvases and keeps the foreground
/// where the level under a pixel is above its height (0x45e190). Keys read
/// the canvas at x = 11 × column, y = 7 + 10 × row (0x432d20). Only those
/// pixels are computed here.
struct DriverMusicEngine {
    static let frameInterval: TimeInterval = 0.015
    static let rows = 6
    static let columns = 22

    private let settings: DriverMusicSettings
    private var spectrum = [Float](repeating: 0, count: 256)
    private var levels = [Float](repeating: 0, count: 256)
    private var hue: Float = 0
    private var shownHue: Float = 0
    private var framesRun = 0

    init(settings: DriverMusicSettings) {
        self.settings = settings
    }

    /// Runs the engine frames due by `time`, the first at time 0, each on
    /// the latest mono samples.
    mutating func advance(to time: TimeInterval, samples: [Float]) {
        let due = Int(time / Self.frameInterval) + 1
        while framesRun < due {
            analyse(samples)
            if hue >= 360 { hue = 0 }
            if hue < 0 { hue = 360 }
            shownHue = hue
            hue += Float(500) / 100
            framesRun += 1
        }
    }

    /// Light → colour of the last frame.
    var frame: [UInt8: RGBColor] {
        Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.enumerated().map { index, key in
            let place = DriverLightTables.rowColumn[index]
            let (x, y) = Self.position(row: place.row, column: place.column)
            let color = isLit(x: x, y: y)
                ? color(settings.foreground, parameter: 100, x: x, y: y)
                : color(settings.background, parameter: settings.backgroundBrightness, x: x, y: y)
            return (key.light, color)
        })
    }

    /// Per column, rows − row of the highest lit key (0x4339f0), for the
    /// 2.4G frame.
    var heights: [Int] {
        var heights = Array(repeating: 0, count: Self.columns)
        for place in DriverLightTables.rowColumn {
            let (x, y) = Self.position(row: place.row, column: place.column)
            if isLit(x: x, y: y) { heights[place.column] = max(heights[place.column], Self.rows - place.row) }
        }
        return heights
    }

    /// The driver sends a frame only when some key's COLORREF is above 1
    /// (0x433aed).
    static func hasLight(_ colors: [UInt8: RGBColor]) -> Bool {
        colors.values.contains { $0.red > 1 || $0.green > 0 || $0.blue > 0 }
    }

    /// Integer HSV of 0x45ba00, hue in degrees.
    static func hsv(hue: Int, saturation: UInt8, value: UInt8) -> RGBColor {
        guard saturation != 0 else { return RGBColor(red: value, green: value, blue: value) }
        let s = Int(saturation)
        let v = Int(value)
        let h = Int(UInt32(truncatingIfNeeded: hue) % 360)
        let sector = h / 60
        let p = (256 - s) * v / 256
        let q = ((60 * sector - h) * s + 15_360) * v / 15_360
        let t = ((h - 60 * (sector + 1)) * s + 15_360) * v / 15_360
        let (r, g, b): (Int, Int, Int)
        switch sector {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGBColor(red: UInt8(truncatingIfNeeded: r), green: UInt8(truncatingIfNeeded: g), blue: UInt8(truncatingIfNeeded: b))
    }

    // MARK: - Spectrum (0x45d060)

    /// Hann over the first half of the 512 values (window 1, + 0x504c4).
    private static let hann: [Float] = {
        let step = atan(1.0) * 4 * 2 * 0.00390625
        return (0..<256).map { Float((1 - cos(Double($0) * step)) * 0.5) }
    }()

    /// Rising weights of table 0x594b40.
    private static let weights: [Float] = (0..<256).map { Float($0) * 0.00390625 * 0.5 + 0.04 }

    private static let cosines = (0..<512).map { cos(2 * Double.pi * Double($0) / 512) }
    private static let sines = (0..<512).map { sin(2 * Double.pi * Double($0) / 512) }

    private mutating func analyse(_ samples: [Float]) {
        let decay = Float(80) / 100
        for index in spectrum.indices { spectrum[index] *= decay }

        // A ring of 256 values, each from two frames: (L₀ + R₀ + L₁ + R₁) / 4
        // doubled and times the gain, stored twice.
        let gain = Float(settings.amplitude * 5)
        let recent = Array(samples.suffix(512))
        let pairs = stride(from: recent.count % 2, to: recent.count, by: 2).map { index in
            var value = (recent[index] + recent[index + 1]) * 0.5
            value += value
            return value * gain
        }
        let ring = [Float](repeating: 0, count: 256 - pairs.count) + pairs
        var buffer = ring.flatMap { [$0, $0] }
        for index in 0..<256 { buffer[index] *= Self.hann[index] }

        // realft leaves [X₀, X₂₅₆, Re X₁, Im X₁, …]; the driver then copies
        // Re X₁ over X₀ and weights the first 256 values.
        var transformed = [Float](repeating: 0, count: 128)
        transformed[1] = Float(buffer.enumerated().reduce(0.0) { $0 + Double($1.element) * ($1.offset % 2 == 0 ? 1 : -1) })
        for bin in 1..<64 {
            var real = 0.0
            var imaginary = 0.0
            for (index, value) in buffer.enumerated() {
                let phase = bin * index % 512
                real += Double(value) * Self.cosines[phase]
                imaginary -= Double(value) * Self.sines[phase]
            }
            transformed[2 * bin] = Float(real)
            transformed[2 * bin + 1] = Float(imaginary)
        }
        transformed[0] = transformed[2]
        for index in transformed.indices { transformed[index] *= Self.weights[index] }

        for bin in 0..<64 {
            let real = transformed[2 * bin]
            let imaginary = transformed[2 * bin + 1]
            let magnitude = Float(sqrt(Double(real * real + imaginary * imaginary)))
            let value = min(1, Float(log10(Double(magnitude * 1.1))) * 0.5 + magnitude * 0.9)
            if value > spectrum[4 * bin] { spectrum[4 * bin] = value }
            if spectrum[4 * bin] < 0 { spectrum[4 * bin] = 0 }
            for offset in 1...3 { spectrum[4 * bin + offset] = spectrum[4 * bin] }
        }

        // Smoothing mode 1 with width 8, in place (0x45d424).
        let width = 8
        for index in 0..<width {
            let count = width + index + 1
            var front: Float = 0
            var back: Float = 0
            for offset in 0..<count {
                front += spectrum[offset]
                back += spectrum[255 - offset]
            }
            spectrum[index] = front / Float(count)
            spectrum[255 - index] = back / Float(count)
        }
        for index in width..<(256 - width) {
            var sum: Float = 0
            for offset in 1...width {
                sum += spectrum[index - offset]
                sum += spectrum[index + offset]
            }
            spectrum[index] = (spectrum[index] + sum) / Float(2 * width + 1)
        }

        // Interpolation factor 1.0 (+ 0x50450).
        for index in levels.indices { levels[index] = (spectrum[index] - levels[index]) * 1 + levels[index] }
    }

    // MARK: - Canvas

    private static func position(row: Int, column: Int) -> (x: Int, y: Int) {
        (255 / columns * column, Int(Float(62 / rows * row + 2) + Float(62 / rows) * 0.5))
    }

    private func isLit(x: Int, y: Int) -> Bool {
        levels[x] > (64 - Float(y)) * 0.015625
    }

    /// The renderer's colour at one pixel, scaled by k = int(parameter × 2.55).
    private func color(_ mode: DriverMusicMode, parameter: Int, x: Int, y: Int) -> RGBColor {
        let k = Int(Float(parameter) * Float(2.55))
        func scaled(_ red: Int, _ green: Int, _ blue: Int) -> RGBColor {
            RGBColor(red: UInt8((red * k) >> 8), green: UInt8((green * k) >> 8), blue: UInt8((blue * k) >> 8))
        }
        /// Row bands of 0x45d7d0: entry int(n − n / 63 × y), the last at the top.
        func band(_ colors: [(Int, Int, Int)]) -> RGBColor {
            let n = Float(colors.count)
            let color = colors[Int(n - n / 63 * Float(y))]
            return scaled(color.0, color.1, color.2)
        }
        let rainbow = [(255, 0, 0), (255, 255, 0), (0, 255, 0), (0, 255, 255), (0, 0, 255), (255, 0, 255)]
        switch mode {
        case .off: return scaled(0, 0, 0)
        case .greenYellowRed: return band([(0, 255, 0), (255, 255, 0), (255, 0, 0)])
        case .rainbow: return band(rainbow)
        case .reverseRainbow: return band(rainbow.reversed())
        case .gradient:
            // Colour wheel of 0x45dbf0 around (128, 32).
            let angle = atan2(Double(y - 32), Double(x - 128)) * 57.295827908797776 + 180
            let degrees = Int(angle) % 360
            return Self.hsv(hue: Int(Float(degrees) + shownHue), saturation: 255, value: UInt8(truncatingIfNeeded: k))
        case .spectrumCycle: return Self.hsv(hue: Int(shownHue), saturation: 255, value: UInt8(truncatingIfNeeded: k))
        case .white: return scaled(255, 255, 255)
        case .red: return scaled(255, 0, 0)
        case .orange: return scaled(255, 0x40, 0)
        case .yellow: return scaled(255, 255, 0)
        case .blue: return scaled(0, 0, 255)
        case .green: return scaled(0, 255, 0)
        }
    }
}
