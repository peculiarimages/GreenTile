import AppKit
import GreenTileKit

extension NSColor {
    convenience init(_ color: SRGBColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

/// The colours the buttons and chevrons are drawn with. The green fill and its outline come from
/// `ButtonColors` (the outline is the fill with 33% black); the rest is the shading around them.
enum ButtonPalette {
    static let outline = NSColor(ButtonColors.outline)

    /// The green body is shaded from a lighter top to a deeper bottom (`spread` either side of the
    /// middle). The faint white gloss over the top lifts each channel by a different amount (it
    /// matters most for blue, least for green), so that lift is taken back out of the shading,
    /// channel by channel: the green you see then averages out at the fill colour. The lift was
    /// measured from a render at the gloss strength below; change one and re-measure the other.
    static let glossAlpha: CGFloat = 0.18
    private static let spread = 0.055
    private static let glossLift = (red: 0.0133, green: 0.0035, blue: 0.0176)

    static let fill = NSColor(ButtonColors.fill)
    static let fillTop = shaded(by: spread)
    static let fillBottom = shaded(by: -spread)

    private static func shaded(by offset: Double) -> NSColor {
        let base = ButtonColors.fill
        func channel(_ value: Double, _ lift: Double) -> Double { min(max(value + offset - lift, 0), 1) }
        return NSColor(srgbRed: channel(base.red, glossLift.red),
                       green: channel(base.green, glossLift.green),
                       blue: channel(base.blue, glossLift.blue), alpha: 1)
    }

    /// The white half is white at the top and a touch grey at the bottom, to match the same light.
    static let whiteTop = NSColor.white
    static let whiteBottom = NSColor(srgbRed: 0.88, green: 0.90, blue: 0.88, alpha: 1)
}
