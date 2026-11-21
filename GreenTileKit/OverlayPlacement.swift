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
    /// A chevron's click area is narrower than this only when the window leaves little room beside
    /// the traffic lights; below this width the chevron is left out.
    public static let minimumChevronWidth: CGFloat = 8
    /// How far the left chevron's click area stays from the window's left edge, so it does not sit
    /// on the strip used to resize the window (given up only when the window is too tight for it).
    public static let chevronEdgeInset: CGFloat = 3
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

    /// The panel frame for the chevron that sends the window to the display on `side`: the same row
    /// as the tiling buttons, directly beside the outermost one (left of the red column, right of
    /// the green column). It is trimmed to stay inside the window, and nil when there is too little
    /// room. All rects are in the same (Accessibility) coordinate space.
    public static func chevronFrame(side: DisplaySide, trafficLights: CGRect, windowFrame: CGRect) -> CGRect? {
        let y = trafficLights.maxY + centreBelow - hitSize / 2
        let x0: CGFloat, x1: CGFloat
        switch side {
        case .left:
            x1 = trafficLights.minX
            // Keep clear of the window's edge when there is room; in a tight window use the whole
            // gap rather than give up on the chevron.
            let roomy = max(windowFrame.minX + chevronEdgeInset, x1 - hitSize)
            x0 = x1 - roomy >= minimumChevronWidth ? roomy : max(windowFrame.minX, x1 - hitSize)
        case .right:
            x0 = trafficLights.maxX
            x1 = min(windowFrame.maxX, x0 + hitSize)
        }
        guard x1 - x0 >= minimumChevronWidth else { return nil }
        return CGRect(x: x0.rounded(), y: y, width: (x1 - x0).rounded(), height: hitSize)
    }

    /// Whether a window of these bounds should carry the buttons. A window that exactly covers a
    /// display is in native full screen, where the traffic lights are hidden.
    public static func isEligible(windowBounds: CGRect, displayFrames: [CGRect]) -> Bool {
        guard windowBounds.width >= minimumWindowSize.width,
              windowBounds.height >= minimumWindowSize.height else { return false }
        return !displayFrames.contains { ScreenGeometry.framesMatch($0, windowBounds, tolerance: 1) }
    }
}
