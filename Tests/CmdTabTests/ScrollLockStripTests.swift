import XCTest
@testable import CmdTab

final class ScrollLockStripTests: XCTestCase {
    private typealias Strip = ScrollLockStrip<Int>

    private func strip(_ windows: [Int], focused: Int? = nil) -> Strip {
        var strip = Strip()
        for window in windows { strip.append(window, width: .half) }
        if let focused { strip.focus(focused) }
        return strip
    }

    private func layoutOfColumns(_ strip: Strip) -> [[Int]] {
        strip.columns.map(\.windows)
    }

    func testInsertGoesRightAfterTheFocusedColumn() {
        var strip = strip([1, 2, 3], focused: 1)
        strip.insert(4, width: .third)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [4], [2], [3]])
        XCTAssertEqual(strip.columns[1].width, .third)
    }

    func testInsertWithoutFocusGoesAtTheEnd() {
        var strip = strip([1, 2])
        strip.insert(3, width: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2], [3]])
    }

    func testRemovingTheFocusedWindowFocusesTheNeighbour() {
        var strip = strip([1, 2, 3], focused: 2)
        strip.remove(2)
        XCTAssertEqual(strip.focused, 3)
        strip.remove(3)
        XCTAssertEqual(strip.focused, 1)
        strip.remove(1)
        XCTAssertNil(strip.focused)
        XCTAssertTrue(strip.isEmpty)
    }

    func testFocusColumnStopsAtTheEnds() {
        var strip = strip([1, 2, 3], focused: 2)
        XCTAssertEqual(strip.focusColumn(by: 1), 3)
        XCTAssertEqual(strip.focusColumn(by: 1), 3)
        XCTAssertEqual(strip.focusColumn(by: -5), 1)
    }

    func testFocusColumnWrapsAroundWhenAsked() {
        var strip = strip([1, 2, 3], focused: 1)
        XCTAssertEqual(strip.focusColumn(by: -1, wrapping: true), 3)
        XCTAssertEqual(strip.focusColumn(by: 1, wrapping: true), 1)
    }

    func testMoveFocusedColumnSwapsWithNeighbour() {
        var strip = strip([1, 2, 3], focused: 1)
        strip.moveFocusedColumn(by: 1)
        XCTAssertEqual(layoutOfColumns(strip), [[2], [1], [3]])
        strip.moveFocusedColumn(by: -1)
        strip.moveFocusedColumn(by: -1)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2], [3]])
    }

    func testArrangeBarKeepsThreeNeighboursOnEachSide() {
        let widths = Array(repeating: CGFloat(100), count: 12)
        func range(_ focused: Int, from start: Int) -> Range<Int> {
            ArrangeHUD.visibleRange(widths: widths, focused: focused, previousStart: start, available: 980, gap: 8, marker: 40)
        }
        XCTAssertEqual(range(0, from: 0), 0..<8, "Eight fit; the rest hide behind …")
        XCTAssertEqual(range(4, from: 0), 0..<8, "Three to the right are still visible: no slide")
        XCTAssertEqual(range(5, from: 0), 1..<9, "Fewer than three to the right: slide by one")
        XCTAssertEqual(range(11, from: 4), 4..<12, "At the end, the last tiles are all shown")
        XCTAssertEqual(range(6, from: 4), 3..<11, "Going back keeps three on the left too")
        XCTAssertEqual(ArrangeHUD.visibleRange(widths: [100, 100], focused: 0, previousStart: 0, available: 600, gap: 8, marker: 40), 0..<2)
    }

    func testArrangeBarKeymap() {
        typealias Hud = ArrangeHUD
        XCTAssertEqual(Hud.action(keyCode: 124, flags: []), .focusColumnRight)                 // →
        XCTAssertEqual(Hud.action(keyCode: 123, flags: .option), .arrangeLeft)                // ⌥←
        XCTAssertEqual(Hud.action(keyCode: 124, flags: .command), .arrangeToEnd)              // ⌘→
        XCTAssertEqual(Hud.action(keyCode: 123, flags: .shift), .arrangeNarrower)             // ⇧←
        XCTAssertEqual(Hud.action(keyCode: 126, flags: .shift), .arrangeTaller)               // ⇧↑
        XCTAssertEqual(Hud.action(keyCode: 125, flags: []), .focusStackDown)                   // ↓
        XCTAssertEqual(Hud.action(keyCode: 1, flags: []), .arrangeStack)                       // S
        XCTAssertEqual(Hud.action(keyCode: 53, flags: []), .arrangeDone)                       // esc
        XCTAssertNil(Hud.action(keyCode: 18, flags: []), "No number keys")
        XCTAssertNil(Hud.action(keyCode: 124, flags: [.shift, .option]), "One combination per command")
        // Stack mode.
        XCTAssertEqual(Hud.action(keyCode: 123, flags: [], stacking: true), .arrangeStackLeft)
        XCTAssertEqual(Hud.action(keyCode: 2, flags: [], stacking: true), .arrangeUnstack)    // D
        XCTAssertEqual(Hud.action(keyCode: 1, flags: [], stacking: true), .arrangeStack)      // S: back
        XCTAssertEqual(Hud.action(keyCode: 53, flags: [], stacking: true), .arrangeStack)     // esc: back
    }

    func testDroppingATileOntoAnotherStacksThem() {
        var strip = strip([1, 2, 3, 4])
        XCTAssertTrue(strip.stackColumn(3, into: 0))
        XCTAssertEqual(layoutOfColumns(strip), [[1, 4], [2], [3]])
        XCTAssertFalse(strip.stackColumn(1, into: 1))
    }

    func testStackIntoEitherNeighbour() {
        var strip = strip([1, 2, 3])
        XCTAssertTrue(strip.stackIntoNeighbour(2, toTheRight: true))
        XCTAssertEqual(layoutOfColumns(strip), [[1], [3, 2]])
        XCTAssertTrue(strip.stackIntoNeighbour(1, toTheRight: true))
        XCTAssertEqual(layoutOfColumns(strip), [[3, 2, 1]])
        XCTAssertFalse(strip.stackIntoNeighbour(1, toTheRight: true), "Nothing on that side")
    }

    func testDragToAColumnsEdgeMovesTheWindowThere() {
        var strip = strip([1, 2, 3, 4])
        strip.move(4, besideColumnOf: 1, after: true)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [4], [2], [3]])
        strip.move(1, besideColumnOf: 3, after: false)
        XCTAssertEqual(layoutOfColumns(strip), [[4], [2], [1], [3]])
        strip.toggleStack(1, height: .half) // 1 joins 2's column.
        strip.move(1, besideColumnOf: 3, after: true)
        XCTAssertEqual(layoutOfColumns(strip), [[4], [2], [3], [1]], "Leaves its stack")
    }

    func testArrangeModeMoves() {
        var strip = strip([1, 2, 3, 4], focused: 2)
        strip.moveFocusedColumnToEnd(true)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [3], [4], [2]])
        strip.moveFocusedColumnToEnd(false)
        XCTAssertEqual(layoutOfColumns(strip), [[2], [1], [3], [4]])
        strip.moveColumn(from: 3, to: 1)
        XCTAssertEqual(layoutOfColumns(strip), [[2], [4], [1], [3]])
        XCTAssertEqual(strip.focusColumn(at: 2), 1)
        XCTAssertEqual(strip.focusColumn(at: 9), 1, "Out of range keeps focus")
    }

    func testToggleStackJoinsTheLeftColumnAndLeavesAgain() {
        var strip = strip([1, 2, 3], focused: 2)
        strip.toggleStack(2, height: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[1, 2], [3]])
        XCTAssertEqual(strip.focused, 2)

        strip.toggleStack(2, height: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2], [3]])
        XCTAssertTrue(strip.columns[0].heights.isEmpty)
    }

    func testToggleStackOnTheFirstColumnDoesNothing() {
        var strip = strip([1, 2], focused: 1)
        strip.toggleStack(1, height: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2]])
    }

    func testStacksHoldAtMostThreeWindows() {
        var strip = strip([1, 2, 3, 4])
        strip.toggleStack(2, height: .third)
        strip.toggleStack(3, height: .third)
        XCTAssertEqual(layoutOfColumns(strip), [[1, 2, 3], [4]])
        strip.toggleStack(4, height: .third)
        XCTAssertEqual(layoutOfColumns(strip), [[1, 2, 3], [4]])
        XCTAssertFalse(strip.canStack(4, onto: 1))
    }

    func testDragOntoTheTopOrBottomHalf() {
        var strip = strip([1, 2, 3])
        strip.stack(3, onto: 1, below: false, height: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[3, 1], [2]])
        strip.stack(2, onto: 1, below: true, height: .third)
        XCTAssertEqual(layoutOfColumns(strip), [[3, 1, 2]])
    }

    func testDragInsideTheSameStackReorders() {
        var strip = strip([1, 2])
        strip.stack(2, onto: 1, below: true, height: .half)
        strip.stack(1, onto: 2, below: true, height: .half)
        XCTAssertEqual(layoutOfColumns(strip), [[2, 1]])
    }

    func testFullHeightUnstacks() {
        var strip = strip([1, 2])
        strip.toggleStack(2, height: .half)
        strip.setHeight(.full, of: 2)
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2]])
    }

    func testFocusInStack() {
        var strip = strip([1, 2, 3], focused: 1)
        strip.toggleStack(2, height: .third)
        strip.toggleStack(3, height: .third)
        XCTAssertEqual(strip.focusInStack(by: 1), 2)
        XCTAssertEqual(strip.focusInStack(by: 5), 3)
        XCTAssertEqual(strip.focusInStack(by: -1), 2)
    }

    func testHeightFractions() {
        var strip = strip([1, 2, 3])
        strip.toggleStack(2, height: .full) // Joins without an explicit height.
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]), [0.5, 0.5])

        strip.setHeight(.third, of: 2)
        let fractions = strip.heightFractions(of: strip.columns[0])
        XCTAssertEqual(fractions[0], 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(fractions[1], 1.0 / 3, accuracy: 0.001)

        strip.setHeight(.half, of: 1)
        strip.setHeight(.half, of: 2)
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]), [0.5, 0.5])
    }

    func testCycleHeightSwitchesBetweenAThirdAndHalfWithoutUnstacking() {
        var strip = strip([1, 2])
        strip.toggleStack(2, height: .half)
        XCTAssertEqual(strip.cycleHeight(of: 2), .third)
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]).map { ($0 * 100).rounded() }, [67, 33])
        XCTAssertEqual(strip.cycleHeight(of: 2), .half)
        XCTAssertEqual(strip.columns.count, 1, "Still stacked")
        XCTAssertEqual(strip.cycleHeight(of: 1), .third, "The other window can be resized too")
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]).map { ($0 * 100).rounded() }, [33, 67])
        XCTAssertNil(strip.cycleHeight(of: 3))
    }

    func testStepHeightUsesTheWholeColumn() {
        var strip = strip([1, 2])
        strip.toggleStack(2, height: .full) // 50 / 50, no explicit heights.
        XCTAssertEqual(strip.stepHeight(of: 1, taller: true), .twoThirds)
        XCTAssertEqual(strip.stepHeight(of: 1, taller: true), .threeQuarters)
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]), [0.75, 0.25], "The other keeps the rest")
        XCTAssertNil(strip.stepHeight(of: 1, taller: true), "The other keeps at least a quarter")
        XCTAssertEqual(strip.stepHeight(of: 1, taller: false), .twoThirds)
    }

    func testArrowsMoveTheEdgeThatCanMove() {
        var strip = strip([1, 2])
        strip.toggleStack(2, height: .full) // 1 on top, 2 below, 50 / 50.
        XCTAssertEqual(strip.moveHeightEdge(of: 1, up: true), .third, "Top window: its bottom edge goes up, it shrinks")
        XCTAssertEqual(strip.moveHeightEdge(of: 2, up: true), .threeQuarters, "Bottom window (at 66%): its top edge goes up, it grows")
        XCTAssertEqual(strip.moveHeightEdge(of: 2, up: false), .twoThirds)
        var alone = self.strip([3])
        XCTAssertEqual(alone.moveHeightEdge(of: 3, up: true), .threeQuarters, "Alone: the bottom edge goes up")
        XCTAssertEqual(alone.moveHeightEdge(of: 3, up: false), .full)
    }

    func testAWindowOnItsOwnCanBeShorterThanItsColumn() {
        var strip = strip([1])
        XCTAssertNil(strip.stepHeight(of: 1, taller: true), "Already full")
        XCTAssertEqual(strip.stepHeight(of: 1, taller: false), .threeQuarters)
        XCTAssertEqual(strip.stepHeight(of: 1, taller: false), .twoThirds)
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]).first!, 2.0 / 3, accuracy: 0.001)
        strip.stepHeight(of: 1, taller: true)
        XCTAssertEqual(strip.stepHeight(of: 1, taller: true), .full)
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]), [1])
    }

    func testHeightsThatDontFitAreEvenedOut() {
        var strip = strip([1, 2, 3])
        strip.toggleStack(2, height: .half)
        strip.toggleStack(3, height: .half) // 50% + 50% leaves nothing for window 1.
        XCTAssertEqual(strip.heightFractions(of: strip.columns[0]).map { ($0 * 1000).rounded() }, [333, 333, 333])
    }

    func testRetainDropsClosedWindows() {
        var strip = strip([1, 2, 3], focused: 3)
        strip.retain([1, 2])
        XCTAssertEqual(layoutOfColumns(strip), [[1], [2]])
        XCTAssertEqual(strip.focused, 2)
    }

    func testWidthStepsStopAtTheEnds() {
        XCTAssertEqual(ColumnWidth.half.step(true), .twoThirds)
        XCTAssertEqual(ColumnWidth.full.step(true), .full)
        XCTAssertEqual(ColumnWidth.third.step(false), .third)
    }

    func testPresetCyclingAndSnapping() {
        XCTAssertEqual(ColumnWidth.full.next, .third)
        XCTAssertEqual(ColumnWidth.nearest(to: 0.62), .twoThirds)
        XCTAssertEqual(ColumnWidth.nearest(to: 0.45), .half)
        XCTAssertEqual(ColumnWidth.nearest(to: 0.4), .third)
        XCTAssertEqual(StackHeight.half.next, .full)
        XCTAssertEqual(StackHeight.nearest(to: 0.9), .threeQuarters)
    }
}
