import CoreGraphics
import XCTest
@testable import CmdTab

final class WindowOrderingTests: XCTestCase {
    private func entry(_ id: CGWindowID, pid: pid_t = 1, layer: Int = 0, width: CGFloat = 800, height: CGFloat = 600) -> WindowServerEntry {
        WindowServerEntry(windowID: id, pid: pid, layer: layer, size: CGSize(width: width, height: height))
    }

    func testParsesWindowServerDictionary() {
        let info: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(42),
            kCGWindowOwnerPID as String: pid_t(7),
            kCGWindowLayer as String: 0,
            kCGWindowIsOnscreen as String: true,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 300, height: 200).dictionaryRepresentation,
        ]
        XCTAssertEqual(WindowServerEntry(info), entry(42, pid: 7, width: 300, height: 200))
    }

    func testRejectsIncompleteDictionary() {
        XCTAssertNil(WindowServerEntry([kCGWindowNumber as String: CGWindowID(1)]))
    }

    func testCandidatesKeepNormalWindowsOfEligibleAppsInOrder() {
        let entries = [
            entry(1),
            entry(2, layer: 25),          // menu bar / overlay
            entry(3, pid: 99),            // not a regular app
            entry(4, width: 1, height: 1),// helper window
            entry(5, width: 1728, height: 33),
            entry(6),
        ]
        let ids = WindowOrdering.candidates(from: entries, eligiblePIDs: [1]).map(\.windowID)
        XCTAssertEqual(ids, [1, 6])
    }

    func testCurrentSpaceScopeRequiresOverlap() {
        XCTAssertTrue(WindowOrdering.isVisible(windowSpaces: [1], currentSpaces: [1, 5], scope: .currentSpace))
        XCTAssertFalse(WindowOrdering.isVisible(windowSpaces: [2], currentSpaces: [1], scope: .currentSpace))
    }

    func testWindowsOnNoSpaceAreNeverVisible() {
        XCTAssertFalse(WindowOrdering.isVisible(windowSpaces: [], currentSpaces: [1], scope: .currentSpace))
        XCTAssertFalse(WindowOrdering.isVisible(windowSpaces: [], currentSpaces: [1], scope: .allSpaces))
    }

    func testAllSpacesScopeShowsOtherSpaces() {
        XCTAssertTrue(WindowOrdering.isVisible(windowSpaces: [3], currentSpaces: [1], scope: .allSpaces))
    }

    func testUnknownCurrentSpaceFallsBackToShowingWindow() {
        XCTAssertTrue(WindowOrdering.isVisible(windowSpaces: [3], currentSpaces: [], scope: .currentSpace))
    }

    func testArrangedPutsDimmedWindowsLastKeepingZOrder() {
        struct Item: Equatable { let name: String; let z: Int; let dimmed: Bool }
        let items = [
            Item(name: "minimized-front", z: 0, dimmed: true),
            Item(name: "back", z: 3, dimmed: false),
            Item(name: "front", z: 1, dimmed: false),
            Item(name: "hidden-back", z: 2, dimmed: true),
        ]
        let names = WindowOrdering.arranged(items, zIndex: \.z, isDimmed: \.dimmed).map(\.name)
        XCTAssertEqual(names, ["front", "back", "minimized-front", "hidden-back"])
    }
}

final class WindowFilterTests: XCTestCase {
    private func options(minimized: Bool, hidden: Bool) -> WindowFilterOptions {
        WindowFilterOptions(scope: .currentSpace, includesMinimized: minimized, includesHiddenApps: hidden)
    }

    func testNormalWindowsAlwaysIncluded() {
        XCTAssertTrue(WindowOrdering.isIncluded(isMinimized: false, isAppHidden: false, options: options(minimized: false, hidden: false)))
    }

    func testMinimizedWindowsFollowOption() {
        XCTAssertTrue(WindowOrdering.isIncluded(isMinimized: true, isAppHidden: false, options: options(minimized: true, hidden: false)))
        XCTAssertFalse(WindowOrdering.isIncluded(isMinimized: true, isAppHidden: false, options: options(minimized: false, hidden: true)))
    }

    func testHiddenAppWindowsFollowOption() {
        XCTAssertTrue(WindowOrdering.isIncluded(isMinimized: false, isAppHidden: true, options: options(minimized: false, hidden: true)))
        XCTAssertFalse(WindowOrdering.isIncluded(isMinimized: false, isAppHidden: true, options: options(minimized: true, hidden: false)))
    }
}

final class SwitcherItemMetricsTests: XCTestCase {
    func testSizesGrowMonotonically() {
        for style in SwitcherStyle.allCases {
            let sizes = SwitcherSize.allCases.map { SwitcherItemMetrics.forSize($0, style: style) }
            XCTAssertEqual(sizes.map(\.iconSide), sizes.map(\.iconSide).sorted(), "\(style)")
            XCTAssertEqual(sizes.map(\.itemSize.width), sizes.map(\.itemSize.width).sorted(), "\(style)")
        }
    }

    func testPreviewAndTitleFitInsideTile() {
        for size in SwitcherSize.allCases {
            let metrics = SwitcherItemMetrics.forSize(size, style: .previews)
            let labelHeight = ceil(metrics.fontSize * 1.4)
            XCTAssertLessThanOrEqual(metrics.previewSize.width, metrics.itemSize.width - 2 * SwitcherTileView.inset)
            XCTAssertLessThanOrEqual(
                SwitcherTileView.inset + metrics.previewSize.height + labelHeight + 4,
                metrics.itemSize.height,
                "\(size)"
            )
        }
    }

    func testIconAndTitleFitInsideTile() {
        for size in SwitcherSize.allCases {
            let metrics = SwitcherItemMetrics.forSize(size)
            XCTAssertLessThanOrEqual(10 + metrics.iconSide + 4 + metrics.titleHeight, metrics.itemSize.height, "\(size)")
        }
    }
}

final class ThumbnailGeometryTests: XCTestCase {
    func testWideWindowIsLimitedByWidth() {
        let size = ThumbnailGeometry.fittedPixelSize(window: CGSize(width: 2000, height: 1000), box: CGSize(width: 400, height: 300))
        XCTAssertEqual(size, CGSize(width: 400, height: 200))
    }

    func testTallWindowIsLimitedByHeight() {
        let size = ThumbnailGeometry.fittedPixelSize(window: CGSize(width: 600, height: 1200), box: CGSize(width: 400, height: 300))
        XCTAssertEqual(size, CGSize(width: 150, height: 300))
    }

    func testSmallWindowIsNeverUpscaled() {
        let size = ThumbnailGeometry.fittedPixelSize(window: CGSize(width: 120, height: 80), box: CGSize(width: 400, height: 300))
        XCTAssertEqual(size, CGSize(width: 120, height: 80))
    }

    func testEmptyWindowGivesZero() {
        XCTAssertEqual(ThumbnailGeometry.fittedPixelSize(window: .zero, box: CGSize(width: 400, height: 300)), .zero)
    }
}

final class ZOrderTests: XCTestCase {
    func testOnScreenWindowsRankFirstInTheirOwnOrder() {
        // The full list puts ordered-out windows (9, 8) above the frontmost visible window (1).
        let index = WindowOrdering.zIndex(onScreenOrder: [1, 2, 3], fullOrder: [9, 8, 1, 3, 2, 7])
        XCTAssertEqual(index[1], 0)
        XCTAssertEqual(index[2], 1)
        XCTAssertEqual(index[3], 2)
        XCTAssertEqual(index[9], 3)
        XCTAssertEqual(index[8], 4)
        XCTAssertEqual(index[7], 5)
    }

    func testOrderedOutWindowIsOnlyOneThatIsInvisibleForNoReason() {
        XCTAssertTrue(WindowOrdering.isOrderedOut(isOnScreen: false, isOnCurrentSpace: true, isMinimized: false, isAppHidden: false))
        XCTAssertFalse(WindowOrdering.isOrderedOut(isOnScreen: true, isOnCurrentSpace: true, isMinimized: false, isAppHidden: false))
        XCTAssertFalse(WindowOrdering.isOrderedOut(isOnScreen: false, isOnCurrentSpace: true, isMinimized: true, isAppHidden: false))
        XCTAssertFalse(WindowOrdering.isOrderedOut(isOnScreen: false, isOnCurrentSpace: true, isMinimized: false, isAppHidden: true))
        XCTAssertFalse(WindowOrdering.isOrderedOut(isOnScreen: false, isOnCurrentSpace: false, isMinimized: false, isAppHidden: false))
    }
}
