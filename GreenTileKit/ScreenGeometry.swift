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

/// Which side of a display another display can sit on.
public enum DisplaySide: Sendable {
    case left, right
}

extension ScreenGeometry {
    /// The display touching display `index` on `side` and sharing some of that edge, if there is
    /// one. A display that only meets at a corner does not count. When several qualify (a stack of
    /// displays down one side) the one beside `window` wins, so a window is offered the display it
    /// is actually next to. `frames` and `window` must be in the same coordinate space.
    public static func neighbourIndex(of index: Int, on side: DisplaySide, in frames: [CGRect],
                                      preferring window: CGRect? = nil, tolerance: CGFloat = 1) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let own = frames[index]
        var best: (index: Int, score: CGFloat)?
        for (j, other) in frames.enumerated() where j != index {
            let touches: Bool
            switch side {
            case .right: touches = abs(other.minX - own.maxX) <= tolerance
            case .left: touches = abs(other.maxX - own.minX) <= tolerance
            }
            let shared = overlapLength(own.minY, own.maxY, other.minY, other.maxY)
            guard touches, shared > 0 else { continue }
            let besideWindow = window.map { overlapLength($0.minY, $0.maxY, other.minY, other.maxY) } ?? 0
            let score = besideWindow * 1_000_000 + shared
            if score > (best?.score ?? -1) { best = (j, score) }
        }
        return best?.index
    }

    /// Carries `frame` from one display's usable area to another's so that it covers the same share
    /// of the new area: a window tiled to a left half stays a left half, whatever the sizes of the
    /// two displays. Edges are rounded to whole points and the result is kept inside `destination`.
    public static func mapProportionally(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return destination }
        func map(_ value: CGFloat, _ sourceOrigin: CGFloat, _ sourceLength: CGFloat,
                 _ destinationOrigin: CGFloat, _ destinationLength: CGFloat) -> CGFloat {
            (destinationOrigin + (value - sourceOrigin) / sourceLength * destinationLength).rounded()
        }
        var x0 = map(frame.minX, source.minX, source.width, destination.minX, destination.width)
        let x1 = map(frame.maxX, source.minX, source.width, destination.minX, destination.width)
        var y0 = map(frame.minY, source.minY, source.height, destination.minY, destination.height)
        let y1 = map(frame.maxY, source.minY, source.height, destination.minY, destination.height)
        let width = min(x1 - x0, destination.width)
        let height = min(y1 - y0, destination.height)
        x0 = min(max(x0, destination.minX), destination.maxX - width)
        y0 = min(max(y0, destination.minY), destination.maxY - height)
        return CGRect(x: x0, y: y0, width: width, height: height)
    }

    private static func overlapLength(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        max(0, min(a1, b1) - max(a0, b0))
    }
}
