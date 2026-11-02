import XCTest
@testable import CmdTab

final class SwitcherSpacesTests: XCTestCase {
    private func display(_ id: String = "main", current: UInt64, fullScreen: [UInt64] = []) -> DisplaySpaces {
        DisplaySpaces(displayID: id, current: current, currentIsFullScreen: fullScreen.contains(current), fullScreen: fullScreen)
    }

    func testOnADesktopFullScreenAppsAreIncluded() {
        let spaces = SwitcherSpaces.visible(displays: [display(current: 1, fullScreen: [7, 8])], lastDesktop: [:])
        XCTAssertEqual(spaces, [1, 7, 8])
    }

    func testInAFullScreenAppTheDesktopYouCameFromIsIncluded() {
        let spaces = SwitcherSpaces.visible(displays: [display(current: 7, fullScreen: [7, 8])], lastDesktop: ["main": 2])
        XCTAssertEqual(spaces, [7, 8, 2])
    }

    func testInAFullScreenAppWithNoKnownDesktopShowsFullScreenApps() {
        let spaces = SwitcherSpaces.visible(displays: [display(current: 7, fullScreen: [7])], lastDesktop: [:])
        XCTAssertEqual(spaces, [7])
    }

    func testEachDisplayUsesItsOwnDesktop() {
        let spaces = SwitcherSpaces.visible(
            displays: [display("a", current: 7, fullScreen: [7]), display("b", current: 3)],
            lastDesktop: ["a": 1, "b": 4]
        )
        XCTAssertEqual(spaces, [7, 1, 3])
    }

    func testRemembersOnlyRealDesktops() {
        let desktops = SwitcherSpaces.desktops(of: [display("a", current: 7, fullScreen: [7]), display("b", current: 3)])
        XCTAssertEqual(desktops, ["b": 3])
    }
}
