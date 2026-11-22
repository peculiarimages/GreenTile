import XCTest
@testable import GreenTileKit

final class ButtonColorsTests: XCTestCase {
    func testFillIsTheAverageTrafficLightGreen() {
        XCTAssertEqual(ButtonColors.fill, SRGBColor(hex: 0x66CC3D))
        XCTAssertEqual(ButtonColors.fill.hexString, "#66CC3D")
        XCTAssertEqual(ButtonColors.fill.red, 102.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(ButtonColors.fill.green, 204.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(ButtonColors.fill.blue, 61.0 / 255, accuracy: 1e-9)
    }

    /// The outline is the fill with 33% black added: every channel at 67% of the fill's.
    func testOutlineIsTheFillWithThirtyThreePercentBlack() {
        XCTAssertEqual(ButtonColors.outlineBlack, 0.33)
        let fill = ButtonColors.fill, outline = ButtonColors.outline
        XCTAssertEqual(outline.red, fill.red * 0.67, accuracy: 1e-9)
        XCTAssertEqual(outline.green, fill.green * 0.67, accuracy: 1e-9)
        XCTAssertEqual(outline.blue, fill.blue * 0.67, accuracy: 1e-9)
        XCTAssertEqual(outline.hexString, "#448929")
    }

    func testMixingBlackBehavesAtTheEnds() {
        let c = SRGBColor(hex: 0x66CC3D)
        XCTAssertEqual(c.mixedWithBlack(0), c)
        XCTAssertEqual(c.mixedWithBlack(1), SRGBColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(c.mixedWithBlack(-1), c)          // clamped
        XCTAssertEqual(c.mixedWithBlack(2).hexString, "#000000")
    }

    func testShiftingLightensDarkensAndClamps() {
        let c = SRGBColor(hex: 0x66CC3D)
        XCTAssertGreaterThan(c.shifted(by: 0.05).red, c.red)
        XCTAssertLessThan(c.shifted(by: -0.05).green, c.green)
        XCTAssertEqual(c.shifted(by: 1).hexString, "#FFFFFF")
        XCTAssertEqual(c.shifted(by: -1).hexString, "#000000")
    }

    /// Background windows' buttons keep 67% of their colour: a third of the way to grey.
    func testBackgroundMuteTakesAThirdOfTheColourOut() {
        XCTAssertEqual(ButtonColors.backgroundMute, 0.33)
        let fill = ButtonColors.fill
        let grey = 0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue
        let muted = fill.desaturated(ButtonColors.backgroundMute)
        XCTAssertEqual(muted.red, fill.red + (grey - fill.red) * 0.33, accuracy: 1e-9)
        XCTAssertEqual(muted.green, fill.green + (grey - fill.green) * 0.33, accuracy: 1e-9)
        XCTAssertEqual(muted.blue, fill.blue + (grey - fill.blue) * 0.33, accuracy: 1e-9)
        // Still green, just less so.
        XCTAssertGreaterThan(muted.green, muted.red)
        XCTAssertLessThan(muted.green - muted.blue, fill.green - fill.blue)
    }

    func testDesaturatingBehavesAtTheEnds() {
        let c = ButtonColors.fill
        XCTAssertEqual(c.desaturated(0), c)
        let grey = c.desaturated(1)
        XCTAssertEqual(grey.red, grey.green, accuracy: 1e-9)
        XCTAssertEqual(grey.green, grey.blue, accuracy: 1e-9)
        XCTAssertEqual(c.desaturated(-1), c)             // clamped
        let white = SRGBColor(red: 1, green: 1, blue: 1)
        XCTAssertEqual(white.desaturated(0.33).hexString, "#FFFFFF")
    }
}
