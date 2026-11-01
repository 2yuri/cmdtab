import XCTest
@testable import CmdTab

final class SwitcherSessionTests: XCTestCase {
    private func window(_ id: CGWindowID, app: String, title: String? = nil) -> SwitcherWindow {
        SwitcherWindow(
            windowID: id, pid: pid_t(app.count), appKey: app, element: nil, title: title ?? "\(app) \(id)",
            appName: app, icon: nil, isMinimized: false, isAppHidden: false
        )
    }

    private var windows: [SwitcherWindow] {
        [window(1, app: "Orca"), window(2, app: "Code"), window(3, app: "Safari"), window(4, app: "Code")]
    }

    func testClosingKeepsSelectionOnTheNextTile() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.selection.select(1)
        session.removeWindow(2)
        XCTAssertEqual(session.items.map(\.primary.windowID), [1, 3, 4])
        XCTAssertEqual(session.selectedItem?.primary.windowID, 3)
    }

    func testClosingTheLastTileSelectsTheNewLast() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.selection.select(3)
        session.removeWindow(4)
        XCTAssertEqual(session.selectedItem?.primary.windowID, 3)
    }

    func testQuittingRemovesEveryWindowOfTheApp() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.removeApp("Code")
        XCTAssertEqual(session.items.map(\.primary.windowID), [1, 3])
    }

    func testClosingOneWindowOfAGroupKeepsTheGroup() {
        var session = SwitcherSession(windows: windows, groupedByApp: true)
        XCTAssertEqual(session.items.map(\.windowCount), [1, 2, 1])
        session.removeWindow(2)
        // The group now sits where its remaining (older) window is: after Safari.
        XCTAssertEqual(session.items.map(\.primary.windowID), [1, 3, 4])
        XCTAssertEqual(session.items.map(\.windowCount), [1, 1, 1])
    }

    func testMinimizingDimsInPlace() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.selection.select(2)
        session.markMinimized(3)
        XCTAssertTrue(session.items[2].isDimmed)
        XCTAssertEqual(session.selection.index, 2)
    }

    func testSearchFiltersAndSelectsFirstMatch() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.selection.select(3)
        session.search("code")
        XCTAssertEqual(session.items.map(\.primary.windowID), [2, 4])
        XCTAssertEqual(session.selection.index, 0)
    }

    func testActionsKeepTheSearchFilter() {
        var session = SwitcherSession(windows: windows, groupedByApp: false)
        session.search("code")
        session.removeWindow(2)
        XCTAssertEqual(session.items.map(\.primary.windowID), [4])
    }
}

final class DesktopNumberingTests: XCTestCase {
    func testNumbersPerDisplaySkippingFullScreenSpaces() {
        let main: [DesktopNumbering.Space] = [
            .init(id: 1, isFullScreen: false), .init(id: 7, isFullScreen: true), .init(id: 3, isFullScreen: false),
        ]
        let external: [DesktopNumbering.Space] = [.init(id: 10, isFullScreen: false), .init(id: 11, isFullScreen: false)]
        let numbers = DesktopNumbering.numbers(spacesPerDisplay: [main, external])
        XCTAssertEqual(numbers[1], 1)
        XCTAssertEqual(numbers[3], 2)
        XCTAssertNil(numbers[7])
        XCTAssertEqual(numbers[10], 1)
        XCTAssertEqual(numbers[11], 2)
    }
}
