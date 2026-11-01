import XCTest
@testable import CmdTab

final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    func testCentredHorizontallyAndSlightlyAboveMiddle() {
        let origin = WindowPlacement.centeredOrigin(for: CGSize(width: 720, height: 552), in: screen)
        XCTAssertEqual(origin.x, 504)
        XCTAssertEqual(origin.y, 355) // 532 free points: 177 above, 355 below (AppKit's y grows upwards).
    }

    func testSecondScreenOffsetIsRespected() {
        let external = CGRect(x: 1728, y: 200, width: 2560, height: 1415)
        let origin = WindowPlacement.centeredOrigin(for: CGSize(width: 720, height: 552), in: external)
        XCTAssertEqual(origin.x, 1728 + 920)
        XCTAssertGreaterThan(origin.y, 200)
    }

    func testWindowLargerThanScreenStaysInside() {
        let origin = WindowPlacement.centeredOrigin(for: CGSize(width: 2000, height: 1200), in: screen)
        XCTAssertEqual(origin, CGPoint(x: 0, y: 0))
    }
}
