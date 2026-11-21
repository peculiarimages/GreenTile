import XCTest
@testable import GreenTileKit

final class ScreenGeometryTests: XCTestCase {
    func testFlipMatchesRealDisplay() {
        // NSScreen.visibleFrame of the primary display (menu bar 31pt, Dock 40pt) -> AX coordinates.
        let appKit = CGRect(x: 0, y: 40, width: 2560, height: 1369)
        XCTAssertEqual(ScreenGeometry.flip(appKit, primaryHeight: 1440),
                       CGRect(x: 0, y: 31, width: 2560, height: 1369))
    }

    func testFlipIsItsOwnInverse() {
        let r = CGRect(x: -2560, y: 120, width: 800, height: 600)
        XCTAssertEqual(ScreenGeometry.flip(ScreenGeometry.flip(r, primaryHeight: 1440), primaryHeight: 1440), r)
        let p = CGPoint(x: 12, y: 34)
        XCTAssertEqual(ScreenGeometry.flip(ScreenGeometry.flip(p, primaryHeight: 1440), primaryHeight: 1440), p)
    }

    func testAreaIndexPicksTheDisplayWithMostOverlap() {
        let areas = [CGRect(x: 0, y: 0, width: 2560, height: 1440),
                     CGRect(x: -2560, y: 0, width: 2560, height: 1440)]
        XCTAssertEqual(ScreenGeometry.areaIndex(for: CGRect(x: 100, y: 100, width: 800, height: 600), in: areas), 0)
        XCTAssertEqual(ScreenGeometry.areaIndex(for: CGRect(x: -2600, y: 100, width: 800, height: 600), in: areas), 1)
    }

    func testAreaIndexForOffscreenWindowUsesNearestDisplay() {
        let areas = [CGRect(x: 0, y: 0, width: 2560, height: 1440),
                     CGRect(x: -2560, y: 0, width: 2560, height: 1440)]
        XCTAssertEqual(ScreenGeometry.areaIndex(for: CGRect(x: -5000, y: 0, width: 100, height: 100), in: areas), 1)
        XCTAssertEqual(ScreenGeometry.areaIndex(for: CGRect(x: 5000, y: 5000, width: 100, height: 100), in: areas), 0)
        XCTAssertNil(ScreenGeometry.areaIndex(for: .zero, in: []))
    }

    func testFramesMatchTolerance() {
        let a = CGRect(x: 10, y: 10, width: 500, height: 400)
        XCTAssertTrue(ScreenGeometry.framesMatch(a, a.offsetBy(dx: 2, dy: -3), tolerance: 4))
        XCTAssertFalse(ScreenGeometry.framesMatch(a, a.offsetBy(dx: 5, dy: 0), tolerance: 4))
    }
}
