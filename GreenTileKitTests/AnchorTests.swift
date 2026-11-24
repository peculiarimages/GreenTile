import XCTest
@testable import GreenTileKit

/// Windows that will not shrink to their tile are pinned to the tile's outer edge.
final class AnchorTests: XCTestCase {
    let area = CGRect(x: 0, y: 31, width: 2560, height: 1369)

    func testRightThirdTooWideKeepsRightEdgeOnDisplayEdge() {
        let tile = TileLayout.rightThird.frame(in: area)
        let placed = ScreenGeometry.anchor(CGSize(width: 1100, height: tile.height), to: tile, in: area)
        XCTAssertEqual(placed.maxX, area.maxX)
        XCTAssertEqual(placed.minY, tile.minY)
        XCTAssertEqual(placed.width, 1100)
    }

    func testLeftHalfTooWideKeepsLeftEdgeOnDisplayEdge() {
        let tile = TileLayout.leftHalf.frame(in: area)
        let placed = ScreenGeometry.anchor(CGSize(width: 1500, height: tile.height), to: tile, in: area)
        XCTAssertEqual(placed.minX, area.minX)
        XCTAssertEqual(placed.minY, tile.minY)
    }

    func testCenterThirdTooWideStaysCentred() {
        let tile = TileLayout.centerThird.frame(in: area)
        let placed = ScreenGeometry.anchor(CGSize(width: 1000, height: tile.height), to: tile, in: area)
        XCTAssertEqual(placed.midX, tile.midX, accuracy: 1)
        XCTAssertTrue(area.contains(placed))
    }

    func testTooTallStaysPinnedToTheTop() {
        let tile = TileLayout.rightHalf.frame(in: area)
        let placed = ScreenGeometry.anchor(CGSize(width: tile.width, height: 1600), to: tile, in: area)
        XCTAssertEqual(placed.minY, area.minY)
        XCTAssertEqual(placed.maxX, area.maxX)
    }

    func testWiderThanTheDisplayStillPinsTheChosenEdge() {
        let tile = TileLayout.rightThird.frame(in: area)
        let placed = ScreenGeometry.anchor(CGSize(width: 3000, height: tile.height), to: tile, in: area)
        XCTAssertEqual(placed.maxX, area.maxX)
    }

    func testDisplayOffsetToTheLeft() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let tile = TileLayout.rightThird.frame(in: left)
        let placed = ScreenGeometry.anchor(CGSize(width: 900, height: 1080), to: tile, in: left)
        XCTAssertEqual(placed.maxX, 0)
        XCTAssertTrue(left.contains(placed))
    }

    func testOversizedDetection() {
        let tile = TileLayout.rightThird.frame(in: area)
        XCTAssertFalse(ScreenGeometry.isOversized(tile.size, for: tile))
        XCTAssertTrue(ScreenGeometry.isOversized(CGSize(width: tile.width + 20, height: tile.height), for: tile))
        XCTAssertTrue(ScreenGeometry.isOversized(CGSize(width: tile.width, height: tile.height + 20), for: tile))
    }
}
