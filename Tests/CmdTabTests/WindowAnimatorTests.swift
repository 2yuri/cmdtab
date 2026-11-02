import XCTest
@testable import CmdTab

@MainActor
final class WindowAnimatorTests: XCTestCase {
    private func move(_ kind: WindowAnimator.Move.Kind) -> WindowAnimator.Move {
        WindowAnimator.Move(
            id: 1, pid: 1, element: AXUIElementCreateApplication(1), width: 500,
            from: CGPoint(x: 100, y: 40), to: CGPoint(x: 700, y: 40), kind: kind
        )
    }

    func testSlideEasesInAndOutAndLandsExactly() {
        let slide = move(.slide)
        XCTAssertEqual(slide.position(at: 0), CGPoint(x: 100, y: 40))
        XCTAssertEqual(slide.position(at: 0.5).x, 400, "Halfway in time is halfway in distance")
        XCTAssertLessThan(slide.position(at: 0.2).x, 130, "Starts gently")
        XCTAssertEqual(slide.position(at: 1), CGPoint(x: 700, y: 40))
    }

    func testBounceNudgesAndComesBack() {
        let bounce = move(.bounce(dx: 28))
        XCTAssertEqual(bounce.position(at: 0).x, 100)
        XCTAssertEqual(bounce.position(at: 0.5).x, 128)
        XCTAssertEqual(bounce.position(at: 1).x, 100)
    }

    func testLongerScrollsTakeLonger() {
        let short = WindowAnimator.scrollDuration(distance: 600, viewWidth: 1600)
        let long = WindowAnimator.scrollDuration(distance: 6000, viewWidth: 1600)
        XCTAssertLessThan(short, long)
        XCTAssertLessThanOrEqual(long, 0.8)
    }
}
