/// A colour in the sRGB space, each channel from 0 to 1.
public struct SRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From 8-bit channels packed as 0xRRGGBB.
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// This colour with `fraction` of black mixed in: 0.33 scales every channel to 67%.
    public func mixedWithBlack(_ fraction: Double) -> SRGBColor {
        let keep = 1 - min(max(fraction, 0), 1)
        return SRGBColor(red: red * keep, green: green * keep, blue: blue * keep)
    }

    /// Every channel moved by `delta` (positive lightens, negative darkens), kept within 0...1.
    public func shifted(by delta: Double) -> SRGBColor {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return SRGBColor(red: clamp(red + delta), green: clamp(green + delta), blue: clamp(blue + delta))
    }

    /// The channels as 8-bit values, e.g. "#66CC3D".
    public var hexString: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

/// The green of the tiling buttons and chevrons, defined once so they always match.
public enum ButtonColors {
    /// The green fill: the average colour of the system's green traffic light.
    public static let fill = SRGBColor(hex: 0x66CC3D)
    /// How much black is mixed into the fill to get the outline.
    public static let outlineBlack: Double = 0.33
    /// The outline: the fill with 33% black added.
    public static var outline: SRGBColor { fill.mixedWithBlack(outlineBlack) }
    /// How opaque the buttons of a window in the background are (0.5: half see-through), so the
    /// active window's buttons stand out.
    public static let backgroundOpacity: Double = 0.5
}
