import CoreGraphics

/// Where a window is tiled: one of the fixed layouts, or a custom share of the display left by
/// resizing two tiles together (a 60/40 split, say).
public enum Tile: Equatable, Sendable {
    case layout(TileLayout)
    /// A rectangle in unit space of the display's usable area (0...1, origin top-left).
    case custom(CGRect)

    public func frame(in area: CGRect, gap: CGFloat = 0) -> CGRect {
        switch self {
        case .layout(let layout):
            return layout.frame(in: area, gap: gap)
        case .custom(let unit):
            let x0 = (area.minX + unit.minX * area.width).rounded()
            let x1 = (area.minX + unit.maxX * area.width).rounded()
            let y0 = (area.minY + unit.minY * area.height).rounded()
            let y1 = (area.minY + unit.maxY * area.height).rounded()
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// The side a window dropped at `x` should take. Only the fixed layouts change side; a custom
    /// split keeps its place.
    public func dropped(atX x: CGFloat, in area: CGRect) -> Tile {
        switch self {
        case .layout(let layout): return .layout(layout.dropped(atX: x, in: area))
        case .custom: return self
        }
    }

    /// `frame` as a custom tile of `area`.
    public static func fitting(_ frame: CGRect, in area: CGRect) -> Tile {
        guard area.width > 0, area.height > 0 else { return .custom(CGRect(x: 0, y: 0, width: 1, height: 1)) }
        return .custom(CGRect(x: (frame.minX - area.minX) / area.width, y: (frame.minY - area.minY) / area.height,
                              width: frame.width / area.width, height: frame.height / area.height))
    }
}

/// Which vertical edge of a window.
public enum VerticalEdge: Sendable {
    case left, right
}

/// The maths for resizing two side-by-side windows together, so the border between them moves as
/// one.
public enum LinkedEdge {
    /// Which vertical edge of a window was dragged between `before` and `after`, if it was resized
    /// by one vertical edge only (the other stayed within `tolerance`). A move, or no horizontal
    /// change, gives nil.
    public static func resizedEdge(from before: CGRect, to after: CGRect, tolerance: CGFloat = 1) -> VerticalEdge? {
        let leftStill = abs(after.minX - before.minX) <= tolerance
        let rightStill = abs(after.maxX - before.maxX) <= tolerance
        if leftStill && !rightStill { return .right }
        if rightStill && !leftStill { return .left }
        return nil
    }

    /// Index of the window in `candidates` whose opposite edge touches `window`'s `edge` (within
    /// `tolerance`) and that sits beside it for at least half the shorter height. The closest one
    /// wins.
    public static func neighbour(of window: CGRect, edge: VerticalEdge, in candidates: [CGRect],
                                 tolerance: CGFloat = 2) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, other) in candidates.enumerated() {
            let distance = edge == .right ? abs(other.minX - window.maxX) : abs(other.maxX - window.minX)
            guard distance <= tolerance else { continue }
            let shared = min(window.maxY, other.maxY) - max(window.minY, other.minY)
            guard shared >= min(window.height, other.height) / 2 else { continue }
            if best == nil || distance < best!.distance { best = (i, distance) }
        }
        return best?.index
    }

    /// The neighbour's frame for a border at `border`: its far edge (`outer`) stays put and the
    /// near edge meets the border. The neighbour sits on the `side` of the border; its vertical
    /// extent is kept.
    public static func neighbourFrame(border: CGFloat, outer: CGFloat, side: VerticalEdge, keeping frame: CGRect) -> CGRect {
        let x0 = side == .right ? border : outer
        let x1 = side == .right ? outer : border
        return CGRect(x: x0.rounded(), y: frame.minY, width: max(1, (x1 - x0).rounded()), height: frame.height)
    }

    /// Whether the neighbour (at `neighbour` in a front-to-back list of frames) should be raised to
    /// just below the dragged window (at `dragged`): true when some other window in front of the
    /// neighbour overlaps the space the two share, so part of the neighbour, or the space it grows
    /// into as the border moves, is hidden. Windows that only touch along an edge do not count.
    public static func neighbourIsHidden(_ neighbour: Int, dragged: Int, in frontToBack: [CGRect]) -> Bool {
        guard frontToBack.indices.contains(neighbour), frontToBack.indices.contains(dragged) else { return false }
        let space = frontToBack[neighbour].union(frontToBack[dragged])
        return frontToBack[..<neighbour].indices.contains { other in
            guard other != dragged else { return false }
            let overlap = frontToBack[other].intersection(space)
            return !overlap.isNull && overlap.width > 1 && overlap.height > 1
        }
    }
}
