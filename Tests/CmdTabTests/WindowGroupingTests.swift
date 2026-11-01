import AppKit
import XCTest
@testable import CmdTab

final class WindowGroupingTests: XCTestCase {
    private func window(_ id: CGWindowID, app: String, minimized: Bool = false) -> SwitcherWindow {
        SwitcherWindow(
            windowID: id, pid: 1, appKey: app, element: nil, title: "\(app) \(id)", appName: app,
            icon: nil, isMinimized: minimized, isAppHidden: false
        )
    }

    func testGroupsKeepFirstAppearanceOrder() {
        let groups = WindowGrouping.group(["code", "safari", "code", "notes", "safari"], by: { $0 })
        XCTAssertEqual(groups, [["code", "code"], ["safari", "safari"], ["notes"]])
    }

    func testUngroupedGivesOneItemPerWindow() {
        let items = SwitcherItem.items(from: [window(1, app: "Code"), window(2, app: "Code")], groupedByApp: false)
        XCTAssertEqual(items.map(\.windowCount), [1, 1])
        XCTAssertEqual(items.map(\.title), ["Code 1", "Code 2"])
    }

    func testGroupedMergesSameAppAtItsMostRecentPosition() {
        let windows = [window(1, app: "Code"), window(2, app: "Safari"), window(3, app: "Code")]
        let items = SwitcherItem.items(from: windows, groupedByApp: true)
        XCTAssertEqual(items.map(\.primary.windowID), [1, 2])
        XCTAssertEqual(items.map(\.windowCount), [2, 1])
        XCTAssertEqual(items[0].title, "Code", "Groups are titled by app")
        XCTAssertEqual(items[1].title, "Safari 2", "Single windows keep their own title")
    }

    func testPrimaryIsMostRecentVisibleWindow() {
        let windows = [window(1, app: "Code", minimized: true), window(2, app: "Code"), window(3, app: "Code")]
        let item = SwitcherItem.items(from: windows, groupedByApp: true)[0]
        XCTAssertEqual(item.primary.windowID, 2)
        XCTAssertEqual(item.others.map(\.windowID), [1, 3])
        XCTAssertFalse(item.isDimmed)
    }

    func testGroupOfOnlyMinimizedWindowsIsDimmed() {
        let windows = [window(1, app: "Code", minimized: true), window(2, app: "Code", minimized: true)]
        XCTAssertTrue(SwitcherItem.items(from: windows, groupedByApp: true)[0].isDimmed)
    }
}
