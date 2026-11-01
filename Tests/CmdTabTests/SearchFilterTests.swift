import XCTest
@testable import CmdTab

final class SearchFilterTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SearchFilter.matches("", fields: ["Safari"]))
        XCTAssertTrue(SearchFilter.matches("   ", fields: ["Safari"]))
    }

    func testIgnoresCaseAndAccents() {
        XCTAssertTrue(SearchFilter.matches("SAFARI", fields: ["Safari"]))
        XCTAssertTrue(SearchFilter.matches("pagina", fields: ["Página inicial"]))
    }

    func testEveryWordMustMatchAnyField() {
        let fields = ["Code", "SwitcherController.swift — cmdtab"]
        XCTAssertTrue(SearchFilter.matches("code switcher", fields: fields))
        XCTAssertTrue(SearchFilter.matches("ctrl cmdtab", fields: ["Code", "SwitcherCtrl cmdtab"]))
        XCTAssertFalse(SearchFilter.matches("code safari", fields: fields))
    }

    func testHighlightRangesFindEachWordIgnoringCase() {
        let title = "SwitcherController.swift — cmdtab"
        let ranges = SearchFilter.highlightRanges("swi CMD", in: title)
        XCTAssertEqual(ranges.map { (title as NSString).substring(with: $0) }, ["Swi", "cmd"])
    }

    func testHighlightRangesSkipWordsNotInText() {
        XCTAssertEqual(SearchFilter.highlightRanges("safari", in: "Code"), [])
    }

    func testFilterMatchesTitlesInsideGroups() {
        let windows = [
            SwitcherWindow(windowID: 1, pid: 1, appKey: "code", element: nil, title: "README.md", appName: "Code",
                           icon: nil, isMinimized: false, isAppHidden: false),
            SwitcherWindow(windowID: 2, pid: 1, appKey: "code", element: nil, title: "Package.swift", appName: "Code",
                           icon: nil, isMinimized: false, isAppHidden: false),
            SwitcherWindow(windowID: 3, pid: 2, appKey: "safari", element: nil, title: "Apple", appName: "Safari",
                           icon: nil, isMinimized: false, isAppHidden: false),
        ]
        let grouped = SwitcherItem.items(from: windows, groupedByApp: true)
        XCTAssertEqual(SearchFilter.filter(grouped, query: "package").map(\.primary.appName), ["Code"])
        XCTAssertEqual(SearchFilter.filter(grouped, query: "safari").map(\.primary.appName), ["Safari"])
    }
}
