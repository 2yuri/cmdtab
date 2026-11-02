import XCTest
@testable import CmdTab

final class ScrollLockLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1240, height: 720)

    private func layout(
        _ widths: [ColumnWidth],
        focused: Int,
        mode: CentreMode = .whenOverflowing,
        padding: CGFloat = 20,
        gap: CGFloat = 10,
        previousScroll: CGFloat = 0
    ) -> ScrollLockLayout<Int>.Result {
        var strip = ScrollLockStrip<Int>()
        for (index, width) in widths.enumerated() { strip.append(index, width: width) }
        strip.focus(focused)
        let layout = ScrollLockLayout<Int>(options: .init(padding: padding, gap: gap, centreMode: mode))
        return layout.layout(strip, in: screen, previousScroll: previousScroll)
    }

    func testThreeThirdsFillTheScreenExactly() {
        let result = layout([.third, .third, .third], focused: 0)
        XCTAssertEqual(result.frames[0]?.minX, 20)
        XCTAssertEqual(result.frames[2]?.maxX, 1220)
        XCTAssertEqual(result.frames[1]!.minX - result.frames[0]!.maxX, 10, accuracy: 1)
        XCTAssertEqual(result.scroll, 0)
    }

    func testPaddingAppliesOnEverySide() {
        let result = layout([.full], focused: 0, padding: 32)
        XCTAssertEqual(result.frames[0], CGRect(x: 32, y: 57, width: 1176, height: 656))
    }

    func testAlwaysCentresTheFocusedColumn() {
        let result = layout([.half, .half, .half], focused: 0, mode: .always)
        let frame = result.frames[0]!
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1)
    }

    func testWhenOverflowingDoesNotScrollAStripThatFits() {
        let result = layout([.half, .half], focused: 1)
        XCTAssertEqual(result.scroll, 0)
        XCTAssertEqual(result.frames[1]?.maxX, 1220)
    }

    func testWhenOverflowingCentresButStaysInsideTheStrip() {
        let middle = layout([.half, .half, .half, .half], focused: 2)
        XCTAssertEqual(middle.frames[2]!.midX, screen.midX, accuracy: 1)

        let last = layout([.half, .half, .half, .half], focused: 3)
        XCTAssertEqual(last.frames[3]?.maxX, 1220) // Clamped: no empty space after the last column.
    }

    func testNeverScrollsOnlyEnoughToShowTheFocusedColumn() {
        let first = layout([.half, .half, .half], focused: 1, mode: .never)
        XCTAssertEqual(first.scroll, 0)
        let second = layout([.half, .half, .half], focused: 2, mode: .never, previousScroll: first.scroll)
        XCTAssertEqual(second.frames[2]?.maxX, 1220)
    }

    func testColumnsOffScreenAreParkedAtTheEdge() {
        let result = layout([.full, .full, .full], focused: 0)
        XCTAssertEqual(result.frames[2]?.minX, screen.maxX - 1)
        let back = layout([.full, .full, .full], focused: 2)
        XCTAssertEqual(back.frames[0]?.minX, screen.maxX - 1, "Left of the view, still parked on the right")
        XCTAssertLessThanOrEqual(back.slideFrames[0]!.maxX, screen.minX, "Slides out to the left first")
    }

    func testParkedColumnsLeaveThePaddingEmpty() {
        var strip = ScrollLockStrip<Int>()
        for index in 0..<4 { strip.append(index, width: .twoThirds) }
        let layout = ScrollLockLayout<Int>(options: .init(padding: 0, gap: 10, centreMode: .always))
        let padded = CGRect(x: 38, y: 38, width: 1652, height: 1008)
        let whole = CGRect(x: 0, y: 0, width: 1728, height: 1117)

        strip.focus(0)
        let atStart = layout.layout(strip, in: padded, previousScroll: 0, parkingBounds: whole)
        XCTAssertEqual(atStart.frames[2]?.minX, 1727, "Parked past the screen edge, not in the padding")
        XCTAssertEqual(atStart.frames[3]?.minX, 1727)

        strip.focus(3)
        let atEnd = layout.layout(strip, in: padded, previousScroll: 0, parkingBounds: whole)
        XCTAssertEqual(atEnd.frames[0]?.minX, 1727)
        XCTAssertEqual(atEnd.frames[1]?.minX, 1727)
        XCTAssertLessThanOrEqual(atEnd.slideFrames[1]!.maxX, 0)
    }

    func testInBetweenScrollFramesGlideThroughThePadding() {
        var strip = ScrollLockStrip<Int>()
        for index in 0..<3 { strip.append(index, width: .full) }
        let layout = ScrollLockLayout<Int>(options: .init(padding: 0, gap: 10, centreMode: .always))
        let padded = CGRect(x: 38, y: 38, width: 1652, height: 1008)
        let whole = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        // Column 1 has just left the usable area on the right but is still inside the screen.
        let frame = layout.layout(strip, in: padded, previousScroll: 0, parkingBounds: whole, fixedScroll: -1660, parksBeyondScreen: true)
        XCTAssertEqual(frame.frames[0]?.minX, 1698, "Still gliding through the padding, not parked")
        XCTAssertEqual(frame.frames[1]?.minX, 1727, "Off the screen: parked")
    }

    func testNeighboursOfAFullWidthColumnPeekThroughThePadding() {
        var strip = ScrollLockStrip<Int>()
        for index in 0..<5 { strip.append(index, width: .full) }
        strip.focus(2)
        let layout = ScrollLockLayout<Int>(options: .init(padding: 0, gap: 10, centreMode: .always))
        let padded = CGRect(x: 38, y: 38, width: 1652, height: 1008)
        let whole = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let result = layout.layout(strip, in: padded, previousScroll: 0, parkingBounds: whole, parksBeyondScreen: true)
        XCTAssertEqual(result.frames[3]?.minX, 1700, "The next column shows in the right padding")
        XCTAssertEqual(result.frames[1]?.maxX, 28, "The previous one in the left padding")
        XCTAssertEqual(result.frames[4]?.minX, 1727, "Further ones stay parked")
        XCTAssertEqual(result.frames[0]?.minX, 1727)
    }

    func testStackedWindowsShareTheColumnHeight() {
        var strip = ScrollLockStrip<Int>()
        strip.append(1, width: .half)
        strip.append(2, width: .half)
        strip.toggleStack(2, height: .third)
        let layout = ScrollLockLayout<Int>(options: .init(padding: 0, gap: 10, centreMode: .never))
        let result = layout.layout(strip, in: CGRect(x: 0, y: 0, width: 1000, height: 590), previousScroll: 0)
        XCTAssertEqual(result.frames[1]?.height, 390)
        XCTAssertEqual(result.frames[2]?.height, 190)
        XCTAssertEqual(result.frames[2]?.minY, 400)
    }

    func testManualScrollKeepsItsPositionWithinLimits() {
        var strip = ScrollLockStrip<Int>()
        for index in 0..<4 { strip.append(index, width: .half) }
        strip.focus(0)
        let layout = ScrollLockLayout<Int>(options: .init(padding: 20, gap: 10, centreMode: .whenOverflowing))
        let scrolled = layout.layout(strip, in: screen, previousScroll: 500, followsFocus: false)
        XCTAssertEqual(scrolled.scroll, 500)
        XCTAssertEqual(scrolled.frames[0]!.minX, 20 - 500, accuracy: 1)
        let pastTheEnd = layout.layout(strip, in: screen, previousScroll: 99_999, followsFocus: false)
        XCTAssertEqual(pastTheEnd.scroll, pastTheEnd.stripWidth - 1200, accuracy: 1, "Stops at the last column")
        let beforeTheStart = layout.layout(strip, in: screen, previousScroll: -300, followsFocus: false)
        XCTAssertEqual(beforeTheStart.scroll, 0, "Stops at the first column")
        XCTAssertEqual(scrolled.columnSpans.count, 4)
        XCTAssertEqual(scrolled.viewWidth, 1200)
    }

    func testHandScrollSettlesOnTheColumnNearestTheCentre() {
        var strip = ScrollLockStrip<Int>()
        for index in 0..<4 { strip.append(index, width: .half) }
        strip.focus(2)
        let layout = ScrollLockLayout<Int>(options: .init(padding: 20, gap: 10, centreMode: .whenOverflowing))
        let scrolledBack = layout.layout(strip, in: screen, previousScroll: 300, followsFocus: false)
        XCTAssertEqual(ScrollLockLayout<Int>.columnNearestToCentre(of: scrolledBack), 1)
        let atStart = layout.layout(strip, in: screen, previousScroll: 0, followsFocus: false)
        XCTAssertEqual(ScrollLockLayout<Int>.columnNearestToCentre(of: atStart), 0)
    }

    func testDraggedWidthSnapsToTheNearestPreset() {
        let fraction = ScrollLockLayout<Int>.fraction(ofWidth: 590, usableWidth: 1200, gap: 10)
        XCTAssertEqual(ColumnWidth.nearest(to: fraction), .half)
    }
}
