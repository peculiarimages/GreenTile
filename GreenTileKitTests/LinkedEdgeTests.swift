import XCTest
@testable import GreenTileKit

final class LinkedEdgeTests: XCTestCase {
    let area = CGRect(x: 0, y: 31, width: 2560, height: 1369)

    func testResizedEdge() {
        let left = TileLayout.leftHalf.frame(in: area)
        XCTAssertEqual(LinkedEdge.resizedEdge(from: left, to: CGRect(x: 0, y: 31, width: 1400, height: 1369)), .right)
        let right = TileLayout.rightHalf.frame(in: area)
        XCTAssertEqual(LinkedEdge.resizedEdge(from: right, to: CGRect(x: 1100, y: 31, width: 1460, height: 1369)), .left)
        XCTAssertNil(LinkedEdge.resizedEdge(from: left, to: left.offsetBy(dx: 50, dy: 0)))
        XCTAssertNil(LinkedEdge.resizedEdge(from: left, to: left))
    }

    func testNeighbourAcrossTheBorder() {
        let left = TileLayout.leftHalf.frame(in: area)
        let right = TileLayout.rightHalf.frame(in: area)
        let elsewhere = CGRect(x: 300, y: 300, width: 600, height: 400)
        XCTAssertEqual(LinkedEdge.neighbour(of: left, edge: .right, in: [elsewhere, right]), 1)
        XCTAssertEqual(LinkedEdge.neighbour(of: right, edge: .left, in: [left]), 0)
        XCTAssertNil(LinkedEdge.neighbour(of: left, edge: .left, in: [right]))
        XCTAssertNil(LinkedEdge.neighbour(of: left, edge: .right, in: [elsewhere]))
    }

    func testNeighbourFrameKeepsTheFarEdge() {
        let right = TileLayout.rightHalf.frame(in: area)
        let moved = LinkedEdge.neighbourFrame(border: 1500, outer: right.maxX, side: .right, keeping: right)
        XCTAssertEqual(moved, CGRect(x: 1500, y: right.minY, width: 1060, height: right.height))
        let left = TileLayout.leftHalf.frame(in: area)
        let grown = LinkedEdge.neighbourFrame(border: 1500, outer: left.minX, side: .left, keeping: left)
        XCTAssertEqual(grown, CGRect(x: 0, y: left.minY, width: 1500, height: left.height))
    }

    func testCustomTileRoundTrips() {
        let frame = CGRect(x: 0, y: 31, width: 1536, height: 1369)
        let tile = Tile.fitting(frame, in: area)
        XCTAssertEqual(tile.frame(in: area), frame)
        // Carried to a smaller display it keeps the same share.
        let small = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        XCTAssertEqual(tile.frame(in: small).width, 1152)
        XCTAssertEqual(tile.frame(in: small).minX, -1920)
    }

    func testCustomTileKeepsItsSideWhenDropped() {
        let tile = Tile.custom(CGRect(x: 0.6, y: 0, width: 0.4, height: 1))
        XCTAssertEqual(tile.dropped(atX: 10, in: area), tile)
        XCTAssertEqual(Tile.layout(.leftHalf).dropped(atX: 2000, in: area), .layout(.rightHalf))
    }

    func testNeighbourBehindAnotherWindowOnTheDraggedSideIsRaised() {
        let left = TileLayout.leftHalf.frame(in: area)
        let right = TileLayout.rightHalf.frame(in: area)
        // Front to back: the dragged left half, a second left half, the right half at the bottom.
        // The second left half only touches the right one, but would hide it as it grows left.
        XCTAssertTrue(LinkedEdge.neighbourIsHidden(2, dragged: 0, in: [left, left, right]))
        // A window over part of the right half hides it too.
        let small = CGRect(x: 1500, y: 200, width: 400, height: 300)
        XCTAssertTrue(LinkedEdge.neighbourIsHidden(2, dragged: 0, in: [left, small, right]))
    }

    func testNeighbourAlreadyVisibleIsLeftAlone() {
        let left = TileLayout.leftHalf.frame(in: area)
        let right = TileLayout.rightHalf.frame(in: area)
        // Already just below the dragged window.
        XCTAssertFalse(LinkedEdge.neighbourIsHidden(1, dragged: 0, in: [left, right, left]))
        // Only the dragged window is in front of it.
        XCTAssertFalse(LinkedEdge.neighbourIsHidden(1, dragged: 0, in: [left, right]))
        // A window in front that is nowhere near the two.
        let elsewhere = CGRect(x: 3000, y: 31, width: 500, height: 500)
        XCTAssertFalse(LinkedEdge.neighbourIsHidden(2, dragged: 0, in: [left, elsewhere, right]))
        // The neighbour is in front of the dragged window (dragged from behind it).
        XCTAssertFalse(LinkedEdge.neighbourIsHidden(0, dragged: 1, in: [right, left]))
    }
}
