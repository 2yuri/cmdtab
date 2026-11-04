import XCTest
@testable import CmdTab

final class IslandEffectsTests: XCTestCase {
    func testTheSkyPicksWhatFalls() {
        XCTAssertEqual(IslandEffects.kind(code: 61, isDay: true), .rain)
        XCTAssertEqual(IslandEffects.kind(code: 53, isDay: false), .rain)
        XCTAssertEqual(IslandEffects.kind(code: 95, isDay: true), .rain)
        XCTAssertEqual(IslandEffects.kind(code: 73, isDay: true), .snow)
        XCTAssertEqual(IslandEffects.kind(code: 0, isDay: false), .fireflies)
        XCTAssertNil(IslandEffects.kind(code: 0, isDay: true))
        XCTAssertNil(IslandEffects.kind(code: 3, isDay: false))
        XCTAssertNil(IslandEffects.kind(code: 45, isDay: true))
    }

    func testTheEffectOnlyFillsAnIdleIsland() {
        var inputs = IslandContent.Inputs()
        inputs.effect = .rain
        XCTAssertEqual(IslandContent.resolve(inputs), .effect(.rain))
        inputs.musicPlaying = true
        XCTAssertEqual(IslandContent.resolve(inputs), .music)
        inputs.musicPlaying = false
        inputs.isExpanded = true
        inputs.tab = .weather
        XCTAssertEqual(IslandContent.resolve(inputs), .expanded(.weather))
    }

    func testTheEffectGetsWingsLikeMusic() {
        let notch = CGSize(width: 190, height: 32)
        XCTAssertEqual(IslandLayout.size(of: .effect(.snow), notch: notch), IslandLayout.size(of: .music, notch: notch))
        XCTAssertFalse(IslandContent.effect(.snow).isGrown)
    }

    func testThingsFallDownAndLandOnTheDockEitherWayUp() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let up = EffectGeometry(bounds: bounds, floor: 70, flipped: false)
        XCTAssertEqual(up.topY, 800)
        XCTAssertEqual(up.floorY, 70)
        XCTAssertEqual(up.downAngle, 0)
        XCTAssertEqual(up.upAngle, .pi)
        let flipped = EffectGeometry(bounds: bounds, floor: 70, flipped: true)
        XCTAssertEqual(flipped.topY, 0)
        XCTAssertEqual(flipped.floorY, 730)
        XCTAssertEqual(flipped.downAngle, .pi)
        XCTAssertEqual(up.fall, 730)
    }
}

final class IslandEffectsSlantTests: XCTestCase {
    func testASlantFallsTheSameWayOnScreenEitherWayUp() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let tilt = CGFloat(20) * .pi / 180
        let up = EffectGeometry(bounds: bounds, floor: 0, flipped: false, tilt: tilt)
        let flipped = EffectGeometry(bounds: bounds, floor: 0, flipped: true, tilt: tilt)
        XCTAssertEqual(up.fallAngle, tilt, accuracy: 0.0001)
        XCTAssertEqual(flipped.fallAngle, .pi - tilt, accuracy: 0.0001)
        XCTAssertEqual(up.drift, 800 * tan(tilt), accuracy: 0.01)
        XCTAssertEqual(EffectGeometry(bounds: bounds, floor: 0, flipped: false).fallAngle, 0)
    }

    func testOnlyRainAndSnowSlant() {
        XCTAssertTrue(IslandEffects.slants(.rain))
        XCTAssertTrue(IslandEffects.slants(.snow))
        XCTAssertTrue(IslandEffects.slants(.weather))
        XCTAssertFalse(IslandEffects.slants(.fireflies))
        XCTAssertFalse(IslandEffects.slants(.off))
    }
}

final class EffectStyleTests: XCTestCase {
    func testTheMiddleIsAsDesignedAndTheEndsReachTheirLimits() {
        XCTAssertEqual(EffectStyle.factor(0.5, low: 0.35, high: 2), 1)
        XCTAssertEqual(EffectStyle.factor(0, low: 0.35, high: 2), 0.35)
        XCTAssertEqual(EffectStyle.factor(1, low: 0.35, high: 2), 2)
        XCTAssertEqual(EffectStyle.factor(7, low: 0.35, high: 2), 2)
    }

    func testOpacityNeverGoesPastOpaque() {
        let color = CGColor(gray: 1, alpha: 0.7)
        XCTAssertEqual(EffectRecipe.strengthened(color, by: 1.8)?.alpha, 1)
        XCTAssertEqual(EffectRecipe.strengthened(color, by: 0.5)!.alpha, 0.35, accuracy: 0.001)
    }
}
