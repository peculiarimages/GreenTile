import XCTest
@testable import GreenTileKit

final class OverlayPlacementTests: XCTestCase {
    /// Red-to-green span of a standard window: three 16pt buttons 7pt apart, 14pt from the top.
    private let lights = CGRect(x: 22, y: 14, width: 62, height: 16)

    /// Centres of the three traffic lights, derived from the same cluster.
    private var lightCentres: [CGFloat] { [lights.minX + 8, lights.midX, lights.maxX - 8] }

    func testButtonSizes() {
        XCTAssertEqual(OverlayPlacement.buttonDiameter, 10)
        // The click area is as big as a traffic light itself, with the circle centred in it.
        XCTAssertEqual(OverlayPlacement.hitSize, lights.height)
        XCTAssertEqual(OverlayPlacement.hitSlop, 3)
        XCTAssertEqual(OverlayPlacement.buttonDiameter + 2 * OverlayPlacement.hitSlop, OverlayPlacement.hitSize)
    }

    func testEachColumnIsCentredUnderItsTrafficLight() {
        for column in 0...2 {
            let panel = OverlayPlacement.frame(column: column, trafficLights: lights)
            XCTAssertEqual(panel.midX, lightCentres[column], accuracy: 0.5, "column \(column)")
            XCTAssertEqual(panel.size, CGSize(width: 16, height: 16))
        }
    }

    func testColumnsLineUpWithTheClusterEdges() {
        // Red column starts at the cluster's left edge, green column ends at its right edge.
        XCTAssertEqual(OverlayPlacement.frame(column: 0, trafficLights: lights).minX, lights.minX)
        XCTAssertEqual(OverlayPlacement.frame(column: 2, trafficLights: lights).maxX, lights.maxX)
    }

    func testCircleIsCentredBelowTheLights() {
        let panel = OverlayPlacement.frame(column: 1, trafficLights: lights)
        // The circle's centre is `centreBelow` under the lights, and the panel is whole points.
        XCTAssertEqual(panel.midY, lights.maxY + OverlayPlacement.centreBelow)
        XCTAssertEqual(panel.minY, panel.minY.rounded())
        let circle = panel.insetBy(dx: OverlayPlacement.hitSlop, dy: OverlayPlacement.hitSlop)
        XCTAssertEqual(circle.size, CGSize(width: 10, height: 10))
        // The click area starts right at the bottom of the lights, without overlapping them.
        XCTAssertEqual(panel.minY, lights.maxY)
        XCTAssertEqual(OverlayPlacement.centreBelow, 8)
        // The circle itself is drawn half a point higher than the middle of its click area, so its
        // centre is 7.5 pt below the lights.
        XCTAssertEqual(OverlayPlacement.circleNudgeY, -0.5)
        XCTAssertEqual(panel.midY + OverlayPlacement.circleNudgeY, lights.maxY + 7.5)
    }

    /// The nudge moves the circle, not the panel, so it must never push the circle out of its panel.
    func testNudgedCircleStaysInsideItsClickArea() {
        let panel = OverlayPlacement.frame(column: 1, trafficLights: lights)
        let centre = CGPoint(x: panel.midX, y: panel.midY + OverlayPlacement.circleNudgeY)
        let circle = CGRect(x: centre.x - OverlayPlacement.buttonDiameter / 2,
                            y: centre.y - OverlayPlacement.buttonDiameter / 2,
                            width: OverlayPlacement.buttonDiameter, height: OverlayPlacement.buttonDiameter)
        XCTAssertTrue(panel.contains(circle))
        XCTAssertLessThanOrEqual(abs(OverlayPlacement.circleNudgeY), OverlayPlacement.hitSlop)
        // The circle is still clear of the traffic lights above it.
        XCTAssertGreaterThan(circle.minY, lights.maxY)
    }

    func testPanelsNeverOverlapEachOtherOrTheLights() {
        let panels = (0...2).map { OverlayPlacement.frame(column: $0, trafficLights: lights) }
        for panel in panels { XCTAssertFalse(panel.intersects(lights)) }
        for (a, b) in zip(panels, panels.dropFirst()) { XCTAssertFalse(a.intersects(b)) }
    }

    func testPlacementWorksOnNegativeOriginDisplays() {
        // Real measurement from a window on the display to the left of the primary one.
        let l = CGRect(x: -1262, y: 49, width: 62, height: 16)
        XCTAssertEqual(OverlayPlacement.frame(column: 0, trafficLights: l).minX, -1262)
        XCTAssertEqual(OverlayPlacement.frame(column: 2, trafficLights: l).maxX, -1200)
    }

    func testPitchFallsBackWhenOnlyTheGreenButtonIsKnown() {
        XCTAssertEqual(OverlayPlacement.lightPitch(of: lights), 23)
        let greenOnly = CGRect(x: 68, y: 14, width: 16, height: 16)
        XCTAssertGreaterThanOrEqual(OverlayPlacement.lightPitch(of: greenOnly), 16)
    }

    func testEligibility() {
        let displays = [CGRect(x: 0, y: 0, width: 2560, height: 1440),
                        CGRect(x: -2560, y: 0, width: 2560, height: 1440)]
        // Normal window.
        XCTAssertTrue(OverlayPlacement.isEligible(windowBounds: CGRect(x: 100, y: 100, width: 900, height: 600), displayFrames: displays))
        // The same window filling the usable area (below the menu bar) is still a normal window.
        XCTAssertTrue(OverlayPlacement.isEligible(windowBounds: CGRect(x: 0, y: 31, width: 2560, height: 1369), displayFrames: displays))
        // Native full screen covers the whole display, on either display.
        XCTAssertFalse(OverlayPlacement.isEligible(windowBounds: displays[0], displayFrames: displays))
        XCTAssertFalse(OverlayPlacement.isEligible(windowBounds: displays[1], displayFrames: displays))
        // Stage Manager thumbnails, tiny helper windows and narrow dialogs.
        XCTAssertFalse(OverlayPlacement.isEligible(windowBounds: CGRect(x: -269, y: 270, width: 156, height: 157), displayFrames: displays))
        XCTAssertFalse(OverlayPlacement.isEligible(windowBounds: CGRect(x: 0, y: 0, width: 1, height: 1), displayFrames: displays))
        XCTAssertFalse(OverlayPlacement.isEligible(windowBounds: CGRect(x: 100, y: 100, width: 200, height: 600), displayFrames: displays))
    }
}
