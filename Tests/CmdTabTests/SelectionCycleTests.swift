import XCTest
@testable import CmdTab

final class SelectionCycleTests: XCTestCase {
    func testForwardWrapsAround() {
        var cycle = SelectionCycle(count: 3)
        cycle.moveForward()
        cycle.moveForward()
        XCTAssertEqual(cycle.index, 2)
        cycle.moveForward()
        XCTAssertEqual(cycle.index, 0)
    }

    func testBackwardFromStartGoesToLast() {
        var cycle = SelectionCycle(count: 4)
        cycle.moveBackward()
        XCTAssertEqual(cycle.index, 3)
    }

    func testSingleItemStaysPut() {
        var cycle = SelectionCycle(count: 1)
        cycle.moveForward()
        XCTAssertEqual(cycle.index, 0)
    }

    func testEmptyCycleIgnoresMoves() {
        var cycle = SelectionCycle(count: 0)
        cycle.moveForward()
        cycle.moveBackward()
        XCTAssertEqual(cycle.index, 0)
    }

    func testSelectIgnoresOutOfRangeIndex() {
        var cycle = SelectionCycle(count: 2)
        cycle.select(1)
        cycle.select(5)
        XCTAssertEqual(cycle.index, 1)
    }
}
