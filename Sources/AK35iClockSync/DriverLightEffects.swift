import Foundation

/// Effects of the driver's realtime page (DeviceDriver.exe 0x428800), with
/// the numbers it passes to mui.dll `CustomLightMode::SetKeyLightMode`.
enum DriverLightEffect: Int, CaseIterable {
    case staticOn = 1
    case starlight = 4
    case fluttering = 5
    case breathing = 7
    case fountain = 9
    case rainbowWave = 10
    case currents = 11
    case rotating = 12

    var displayName: String {
        switch self {
        case .staticOn: return "静态恒亮"
        case .starlight: return "繁星点点"
        case .fluttering: return "漫天飞舞"
        case .breathing: return "动态呼吸"
        case .fountain: return "彩泉涌动"
        case .rainbowWave: return "多彩纵横"
        case .currents: return "随波逐流"
        case .rotating: return "峰回路转"
        }
    }

    var cliName: String {
        switch self {
        case .staticOn: return "static"
        case .starlight: return "starlight"
        case .fluttering: return "fluttering"
        case .breathing: return "breathing"
        case .fountain: return "fountain"
        case .rainbowWave: return "wave"
        case .currents: return "currents"
        case .rotating: return "rotating"
        }
    }

    /// Static On has no speed; Fluttering is always colourful (0x428800).
    var takesSpeed: Bool { self != .staticOn }
    var takesColor: Bool { self != .fluttering }
}

/// mui.dll CustomLightMode with every key on one effect. Each step runs the
/// effects in the order of UpdateLightEffect (0x10023e80); all of them
/// advance every step, because Fluttering also draws from the colour
/// counter that Starlight uses. Brightness only scales the colour when the
/// frame is taken, (c × brightness) >> 8, as DeviceDriver.exe 0x428110 does.
struct DriverLightEngine {
    private typealias T = DriverLightTables

    private let effect: DriverLightEffect
    private let colorful: Bool
    private var colors: [RGBColor]
    private var brightness: [UInt8]
    /// Usage at column × 8 + row (`row_col`), 0 where there is no key.
    private var grid = [UInt8](repeating: 0, count: 22 * 8)
    private var keyOfUsage: [UInt8: Int] = [:]
    private var levelOfUsage = [UInt8](repeating: 0, count: 256)

    private var colorCounter = 0
    private var stars = T.starPhases
    private var rain = Array(T.rainBits.prefix(22))
    private var breathStep = 0
    private var fountainHue = T.fountainHues.map(Int.init)
    private var fountainPhase = T.fountainPhases.map(Int.init)
    private var waveHue = (0..<6).map { 32 * $0 }
    private var wavePhase = T.waveRowPhases.map(Int.init)
    private var currentHue = T.currentHues.map(Int.init)
    private var currentPhase = T.currentPhases.map(Int.init)
    private var rotateHue = T.rotateHues.map(Int.init)
    private var rotatePhase = T.rotatePhases.map(Int.init)

    init(effect: DriverLightEffect, color: RGBColor, colorful: Bool) {
        self.effect = effect
        self.colorful = colorful
        colors = Array(repeating: color, count: KeyboardLayout.keys.count)
        brightness = Array(repeating: 255, count: KeyboardLayout.keys.count)
        for (index, key) in KeyboardLayout.keys.enumerated() {
            let place = T.rowColumn[index]
            grid[place.column * 8 + place.row] = key.usage
            keyOfUsage[key.usage] = index
        }
    }

    /// SetSpeed (0x10020ff0) waits 15 − speed ticks of the 16 ms timer, at
    /// least one, between steps; speeds outside 1…15 wait 15.
    static func stepInterval(speed: Int) -> TimeInterval {
        let ticks = (1...15).contains(speed) ? 15 - speed : 15
        return 0.016 * Double(max(ticks, 1))
    }

    /// Light → colour as sent in the `04 20` frame.
    var frame: [UInt8: RGBColor] {
        Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.enumerated().map { index, key in
            let level = Int(brightness[index])
            let color = colors[index]
            return (key.light, RGBColor(
                red: UInt8((Int(color.red) * level) >> 8),
                green: UInt8((Int(color.green) * level) >> 8),
                blue: UInt8((Int(color.blue) * level) >> 8)
            ))
        })
    }

    mutating func step() {
        updateStars()
        updateRain()
        updateBreath()
        updateFountain()
        updateRainbowWave()
        updateCurrents()
        updateRotation()
    }

    /// `srand(0xE8)` followed by `rand()` is always 796, so the “random”
    /// colour is a counter (0x10024067).
    private mutating func nextColorIndex() -> Int {
        colorCounter += 1
        if colorCounter > 100 { colorCounter -= 100 }
        var index = (796 + colorCounter) & 127
        if index > 106 { index -= 106 }
        return index
    }

    private static func color(_ table: [UInt8], _ index: Int) -> RGBColor {
        RGBColor(red: table[3 * index], green: table[3 * index + 1], blue: table[3 * index + 2])
    }

    private static func hue(_ h: Int) -> RGBColor {
        RGBColor(red: T.hue[(h + 64) % 192], green: T.hue[(h + 128) % 192], blue: T.hue[h % 192])
    }

    /// SetKeyRGBValue (0x10020e10): only keys on that effect and colourful.
    private mutating func setColor(_ usage: UInt8, _ color: RGBColor, for owner: DriverLightEffect) {
        guard usage != 0, owner == effect, colorful, let index = keyOfUsage[usage] else { return }
        colors[index] = color
    }

    private mutating func applyLevels(for owner: DriverLightEffect) {
        guard owner == effect else { return }
        for (index, key) in KeyboardLayout.keys.enumerated() { brightness[index] = levelOfUsage[Int(key.usage)] }
    }

    /// 0x10023fc0: each key counts down from its phase and relights at 255.
    private mutating func updateStars() {
        guard effect == .starlight else { return }
        for index in KeyboardLayout.keys.indices {
            brightness[index] = stars[index]
            if stars[index] == 0 {
                stars[index] = 255
                if colorful { colors[index] = Self.color(T.starColors, nextColorIndex()) }
            } else {
                stars[index] -= 1
            }
        }
    }

    /// 0x100241d0: each column's bits shift up a row per step; lit cells
    /// take the next colour. Brightness is left alone.
    private mutating func updateRain() {
        for column in 0..<22 {
            rain[column] = rain[column] &<< 1
            if rain[column] & 0x80 != 0 { rain[column] = 1 }
            for row in 0..<6 where (rain[column] >> row) & 1 == 1 {
                let index = nextColorIndex()
                setColor(grid[column * 8 + row], Self.color(T.rainColors, index), for: .fluttering)
            }
        }
    }

    /// 0x100244a0: a colour per column (stored G, R, B) and one shared level.
    private mutating func updateBreath() {
        for column in 0..<22 {
            let color = RGBColor(red: T.breathColumnColors[3 * column + 1], green: T.breathColumnColors[3 * column], blue: T.breathColumnColors[3 * column + 2])
            for row in 0..<6 { setColor(grid[column * 8 + row], color, for: .breathing) }
        }
        let level = T.breath[breathStep]
        breathStep = (breathStep + 1) % 128
        if effect == .breathing { brightness = brightness.map { _ in level } }
    }

    /// 0x10024970: twelve rings of twelve keys, hue and wave moving forwards.
    private mutating func updateFountain() {
        for ring in 0..<12 {
            fountainHue[ring] = (fountainHue[ring] + 1) % 192
            for slot in 0..<12 { setColor(T.fountainRings[12 * ring + slot], Self.hue(fountainHue[ring]), for: .fountain) }
        }
        for ring in 0..<12 {
            fountainPhase[ring] = (fountainPhase[ring] + 1) % 96
            for slot in 0..<12 { levelOfUsage[Int(T.fountainRings[12 * ring + slot])] = T.wave[fountainPhase[ring]] }
        }
        applyLevels(for: .fountain)
    }

    /// 0x10024cb0: by row, hue and wave moving backwards.
    private mutating func updateRainbowWave() {
        for row in 0..<6 {
            waveHue[row] = (waveHue[row] + 191) % 192
            wavePhase[row] = (wavePhase[row] + 95) % 96
            for column in 0..<22 {
                let usage = grid[column * 8 + row]
                guard usage != 0 else { continue }
                setColor(usage, Self.hue(waveHue[row]), for: .rainbowWave)
                levelOfUsage[Int(usage)] = T.wave[wavePhase[row]]
            }
        }
        applyLevels(for: .rainbowWave)
    }

    /// 0x10024fb0: by column, hue and wave moving backwards.
    private mutating func updateCurrents() {
        for column in 0..<22 {
            currentHue[column] = (currentHue[column] + 191) % 192
            currentPhase[column] = (currentPhase[column] + 95) % 96
            for row in 0..<6 {
                let usage = grid[column * 8 + row]
                guard usage != 0 else { continue }
                setColor(usage, Self.hue(currentHue[column]), for: .currents)
                levelOfUsage[Int(usage)] = T.wave[currentPhase[column]]
            }
        }
        applyLevels(for: .currents)
    }

    /// 0x10025320: 45 groups of three keys, hue and wave moving forwards.
    private mutating func updateRotation() {
        for group in 0..<45 {
            rotateHue[group] = (rotateHue[group] + 1) % 192
            rotatePhase[group] = (rotatePhase[group] + 1) % 96
            for slot in 0..<3 {
                let usage = T.rotateGroups[3 * group + slot]
                guard usage != 0 else { continue }
                setColor(usage, Self.hue(rotateHue[group]), for: .rotating)
                levelOfUsage[Int(usage)] = T.wave[rotatePhase[group]]
            }
        }
        applyLevels(for: .rotating)
    }
}
