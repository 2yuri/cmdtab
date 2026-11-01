import XCTest
@testable import CmdTab

/// Grid of 8 tiles, 3 per row:
///   0 1 2
///   3 4 5
///   6 7
final class GridNavigationTests: XCTestCase {
    private func move(_ index: Int, _ direction: GridNavigation.Direction, count: Int = 8, columns: Int = 3) -> Int {
        GridNavigation.move(from: index, direction, count: count, columns: columns)
    }

    func testRightAndLeftWalkInOrderAndWrap() {
        XCTAssertEqual(move(2, .right), 3)
        XCTAssertEqual(move(7, .right), 0)
        XCTAssertEqual(move(0, .left), 7)
    }

    func testDownMovesToSameColumnOnNextRow() {
        XCTAssertEqual(move(1, .down), 4)
        XCTAssertEqual(move(4, .down), 7)
    }

    func testDownFromLastRowWrapsToTop() {
        XCTAssertEqual(move(7, .down), 1)
        XCTAssertEqual(move(6, .down), 0)
    }

    func testUpFromTopWrapsToLastRow() {
        XCTAssertEqual(move(0, .up), 6)
        XCTAssertEqual(move(1, .up), 7)
    }

    func testMissingColumnInShortLastRowLandsOnLastTile() {
        XCTAssertEqual(move(5, .down), 7)
        XCTAssertEqual(move(2, .up), 7)
    }

    func testSingleRowIgnoresUpAndDown() {
        XCTAssertEqual(move(2, .down, count: 5, columns: 5), 2)
        XCTAssertEqual(move(2, .up, count: 5, columns: 5), 2)
    }

    func testEmptyGridStaysAtZero() {
        XCTAssertEqual(move(0, .right, count: 0), 0)
    }
}
