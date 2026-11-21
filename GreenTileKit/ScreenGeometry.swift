import CoreGraphics

/// Coordinate and placement maths shared by the app.
///
/// Two coordinate systems are in play:
/// * AppKit (`NSScreen`, `NSEvent.mouseLocation`, `NSWindow`): origin bottom-left of the primary
///   display, y grows upward.
/// * Accessibility / Quartz (`AXPosition`, `CGWindowList`): origin top-left of the primary
///   display, y grows downward.
/// Converting between them is the same flip in both directions.
public enum ScreenGeometry {
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Index of the area that holds most of `window`. A window that is entirely off-screen maps to
    /// the area whose centre is nearest, so it can still be pulled back.
    public static func areaIndex(for window: CGRect, in areas: [CGRect]) -> Int? {
        guard !areas.isEmpty else { return nil }
        var best: (index: Int, overlap: CGFloat)?
        for (i, area) in areas.enumerated() {
            let r = window.intersection(area)
            let overlap = r.isNull ? 0 : r.width * r.height
            if overlap > (best?.overlap ?? 0) { best = (i, overlap) }
        }
        if let best { return best.index }
        let centre = CGPoint(x: window.midX, y: window.midY)
        return areas.indices.min { distance(centre, areas[$0]) < distance(centre, areas[$1]) }
    }

    /// True when every edge of the two frames is within `tolerance` points.
    public static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = p.x - r.midX, dy = p.y - r.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}
