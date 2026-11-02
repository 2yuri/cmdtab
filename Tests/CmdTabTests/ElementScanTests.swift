import XCTest
@testable import CmdTab

final class ElementScanTests: XCTestCase {
    func testStartsAtZero() {
        XCTAssertEqual(ElementScan.next(after: 0, budget: 3_000), 0..<3_000)
    }

    func testCarriesOnFromWhereItStopped() {
        XCTAssertEqual(ElementScan.next(after: 8_272, budget: 3_000), 8_272..<11_272)
    }

    func testStopsAtTheCeiling() {
        XCTAssertEqual(ElementScan.next(after: ElementScan.ceiling - 10, budget: 3_000), (ElementScan.ceiling - 10)..<ElementScan.ceiling)
        XCTAssertNil(ElementScan.next(after: ElementScan.ceiling, budget: 3_000))
    }
}
