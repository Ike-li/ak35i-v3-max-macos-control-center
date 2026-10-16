import CoreGraphics
import Foundation

/// Lighting page form state. Like the driver, only the controls the selected
/// mode shows are sent; anything left over from another mode falls back to
/// the driver default instead of being rejected.
struct LightingSettings: Equatable {
    var mode: LightingMode = .wave
    var brightness = LightingEffect.defaultBrightness
    var speed = LightingEffect.defaultSpeed
    var direction = 0
    var colorful = true
    var color = LightingEffect.defaultColor

    func effect() throws -> LightingEffect {
        try LightingEffect(
            mode: mode,
            brightness: mode.supportsBrightness ? brightness : nil,
            speed: mode.supportsSpeed ? speed : nil,
            direction: mode.allowedDirections.map { $0.contains(direction) ? direction : 0 },
            color: mode.supportsColor ? (colorful ? .colorful : .solid(color)) : nil
        )
    }
}

extension RGBColor {
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    init?(cgColor: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let srgb = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = srgb.components, components.count >= 3
        else { return nil }
        func byte(_ value: CGFloat) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(red: byte(components[0]), green: byte(components[1]), blue: byte(components[2]))
    }
}
