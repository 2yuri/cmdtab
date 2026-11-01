import XCTest
@testable import CmdTab

@MainActor
final class PreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "CmdTabTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.spaceScope, .currentSpace)
        XCTAssertTrue(preferences.showsMinimizedWindows)
        XCTAssertTrue(preferences.showsHiddenAppWindows)
        XCTAssertEqual(preferences.switcherSize, .medium)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertTrue(preferences.quickSwitch)
        XCTAssertTrue(preferences.replacesNativeSwitcher)
        XCTAssertTrue(preferences.showsMenuBarIcon)
        XCTAssertEqual(preferences.switcherStyle, .icons, "Previews need Screen Recording, so they are opt-in")
        XCTAssertFalse(preferences.opensInSearchMode)
        XCTAssertFalse(preferences.previewsSelectedWindow)
        XCTAssertFalse(preferences.wantsScreenRecording)
    }

    func testChangesPersistAcrossInstances() {
        let preferences = Preferences(defaults: defaults)
        preferences.spaceScope = .allSpaces
        preferences.switcherSize = .large
        preferences.theme = .dark
        preferences.showsMinimizedWindows = false

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.spaceScope, .allSpaces)
        XCTAssertEqual(reloaded.switcherSize, .large)
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertFalse(reloaded.showsMinimizedWindows)
    }

    func testLegacyPreviewsSettingMigratesToPreviewsStyle() {
        defaults.set(true, forKey: "showsWindowPreviews")
        XCTAssertEqual(Preferences(defaults: defaults).switcherStyle, .previews)
    }

    func testLegacySearchReleaseActionMigratesToSearchMode() {
        defaults.set("search", forKey: "releaseAction")
        XCTAssertTrue(Preferences(defaults: defaults).opensInSearchMode)
    }

    func testNewStyleWinsOverLegacySetting() {
        defaults.set(true, forKey: "showsWindowPreviews")
        defaults.set("titles", forKey: "switcherStyle")
        XCTAssertEqual(Preferences(defaults: defaults).switcherStyle, .titles)
    }

    func testUnknownStoredValueFallsBackToDefault() {
        defaults.set("enormous", forKey: "switcherSize")
        XCTAssertEqual(Preferences(defaults: defaults).switcherSize, .medium)
    }

    func testResetRestoresDefaults() {
        let preferences = Preferences(defaults: defaults)
        preferences.quickSwitch = false
        preferences.theme = .light
        preferences.reset()
        XCTAssertTrue(preferences.quickSwitch)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertTrue(Preferences(defaults: defaults).quickSwitch)
    }

    func testExceptionsPersistAndFeedTheFilters() {
        let preferences = Preferences(defaults: defaults)
        preferences.exceptions = [
            AppException(bundleID: "com.docker.docker", name: "Docker Desktop", rule: .hide),
            AppException(bundleID: "com.parallels.desktop.console", name: "Parallels Desktop", rule: .leaveShortcut),
        ]
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.exceptions.map(\.bundleID), ["com.docker.docker", "com.parallels.desktop.console"])
        XCTAssertEqual(reloaded.windowFilter.excludedBundleIDs, ["com.docker.docker"])
        XCTAssertEqual(reloaded.bundleIDs(for: .leaveShortcut), ["com.parallels.desktop.console"])
    }

    func testWindowFilterReflectsPreferences() {
        let preferences = Preferences(defaults: defaults)
        preferences.showsHiddenAppWindows = false
        XCTAssertEqual(
            preferences.windowFilter,
            WindowFilterOptions(scope: .currentSpace, includesMinimized: true, includesHiddenApps: false)
        )
    }
}
