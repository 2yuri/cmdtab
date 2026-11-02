import XCTest
@testable import CmdTab

final class ScreenPaddingTests: XCTestCase {
    private let area = CGRect(x: 32, y: 57, width: 1176, height: 656)

    func testWindowAlreadyInsideIsLeftAlone() {
        XCTAssertNil(ScreenPadding.fitted(CGRect(x: 100, y: 100, width: 400, height: 300), inside: area))
    }

    func testMaximizedWindowFillsThePaddedArea() {
        let maximized = CGRect(x: 0, y: 25, width: 1240, height: 720)
        XCTAssertEqual(ScreenPadding.fitted(maximized, inside: area), area)
    }

    func testWindowTouchingAnEdgeSlidesInKeepingItsSize() {
        let atLeftEdge = CGRect(x: 0, y: 200, width: 400, height: 300)
        XCTAssertEqual(ScreenPadding.fitted(atLeftEdge, inside: area), CGRect(x: 32, y: 200, width: 400, height: 300))
        let pastBottom = CGRect(x: 500, y: 600, width: 400, height: 300)
        XCTAssertEqual(ScreenPadding.fitted(pastBottom, inside: area)?.maxY, area.maxY)
    }

    // A 1440×900 screen with a 25 pt menu bar on top and a 70 pt Dock at the bottom (y grows downwards).
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 805)

    func testMenuBarCountsAsPadding() {
        let area = ScreenPadding.area(frame: screenFrame, visible: visibleFrame, padding: 32)
        XCTAssertEqual(area.minY, 32, "Top padding is measured from the screen edge, like the sides")
        XCTAssertEqual(area.minX, 32)
        XCTAssertEqual(area.maxX, 1408)
        XCTAssertEqual(area.maxY, 830, "Still clear of the Dock")
    }

    func testPaddingIsNeverLessThanTheMenuBar() {
        let area = ScreenPadding.area(frame: screenFrame, visible: visibleFrame, padding: 8)
        XCTAssertEqual(area.minX, 25)
        XCTAssertEqual(area.minY, 25)
        XCTAssertEqual(ScreenPadding.minimum(frame: screenFrame, visible: visibleFrame), 25)
    }

    func testNoPaddingUsesTheVisibleFrame() {
        XCTAssertEqual(ScreenPadding.area(frame: screenFrame, visible: visibleFrame, padding: 0), visibleFrame)
    }
}
