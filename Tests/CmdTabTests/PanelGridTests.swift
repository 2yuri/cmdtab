import XCTest
@testable import CmdTab

@MainActor
final class PanelGridTests: XCTestCase {
    private let screen = CGSize(width: 1728, height: 1084)

    func testTitlesFormOneColumnWhenTheyFit() {
        let grid = SwitcherPanel.grid(count: 12, itemSize: CGSize(width: 540, height: 36), available: screen, style: .titles)
        XCTAssertEqual(grid, .init(columns: 1, rows: 12))
    }

    func testTitlesAddColumnsWhenTooTall() {
        let grid = SwitcherPanel.grid(count: 60, itemSize: CGSize(width: 540, height: 36), available: screen, style: .titles)
        XCTAssertGreaterThan(grid.columns, 1)
        XCTAssertLessThanOrEqual(CGFloat(grid.rows) * 42, screen.height)
    }

    func testIconsFillRowsAcrossTheScreen() {
        let grid = SwitcherPanel.grid(count: 5, itemSize: CGSize(width: 116, height: 112), available: screen, style: .icons)
        XCTAssertEqual(grid, .init(columns: 5, rows: 1))
    }
}
