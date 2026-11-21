import CoreGraphics

/// Where the tiling buttons sit and which windows get them.
///
/// Each button sits directly below one of the window's three traffic lights, centred on it. All
/// coordinates are in the Accessibility space (origin top-left, y down).
public enum OverlayPlacement {
    /// Diameter of each round button (the system traffic lights are 16 pt).
    public static let buttonDiameter: CGFloat = 10
    /// Side of each button's square click area (and of its panel): the same as a traffic light.
    /// Keeping it a whole, even number keeps every panel on whole points.
    public static let hitSize: CGFloat = 16
    /// Invisible margin around each circle that still counts as a click on it.
    public static var hitSlop: CGFloat { (hitSize - buttonDiameter) / 2 }
    /// Distance from the bottom of the traffic lights to the middle of each button's click area. At
    /// half of `hitSize` the click area starts exactly at the bottom edge of the lights, which is as
    /// high as the click areas can go without overlapping them. (The circle itself sits a little
    /// higher still: see `circleNudgeY`.)
    public static let centreBelow: CGFloat = 8
    /// How far the drawn circle sits from the middle of its click area, in points, measured the way
    /// y grows on screen (negative is up). The circle is moved inside the panel rather than moving
    /// the panel itself, so every panel stays on whole points (crisp on displays that are not
    /// Retina) and its click area never reaches into the traffic lights. It must stay within
    /// `hitSlop` so the circle remains inside the click area.
    public static let circleNudgeY: CGFloat = -0.5
    /// Smaller windows (dialogs, utility panels, Stage Manager thumbnails) get no buttons.
    public static let minimumWindowSize = CGSize(width: 220, height: 80)

    /// Centre-to-centre distance between neighbouring traffic lights, read off the cluster that
    /// spans the red to the green button. The floor only matters if the close button was missing
    /// and the cluster is just the green button.
    public static func lightPitch(of trafficLights: CGRect) -> CGFloat {
        max((trafficLights.width - trafficLights.height) / 2, trafficLights.height + 4)
    }

    /// The panel frame for the button under `column` (0 red, 1 yellow, 2 green). `trafficLights` is
    /// the rectangle spanning the close and zoom buttons.
    public static func frame(column: Int, trafficLights: CGRect) -> CGRect {
        let centreX = trafficLights.midX + CGFloat(column - 1) * lightPitch(of: trafficLights)
        return CGRect(x: (centreX - hitSize / 2).rounded(),
                      y: trafficLights.maxY + centreBelow - hitSize / 2,
                      width: hitSize,
                      height: hitSize)
    }

    /// Whether a window of these bounds should carry the buttons. A window that exactly covers a
    /// display is in native full screen, where the traffic lights are hidden.
    public static func isEligible(windowBounds: CGRect, displayFrames: [CGRect]) -> Bool {
        guard windowBounds.width >= minimumWindowSize.width,
              windowBounds.height >= minimumWindowSize.height else { return false }
        return !displayFrames.contains { ScreenGeometry.framesMatch($0, windowBounds, tolerance: 1) }
    }
}
