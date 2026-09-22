import XCTest
@testable import MacMuster

@MainActor
final class SettingsAppearanceTests: XCTestCase {

    override func setUp() async throws {
        clearAllUserDefaultsState()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "launchMode")
        UserDefaults.standard.removeObject(forKey: "recentAppLaunchTimes")
        UserDefaults.standard.removeObject(forKey: "appLaunchCounts")
        UserDefaults.standard.removeObject(forKey: "showHiddenApps")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
    }

    // MARK: - Refresh Interval Clamping (security regression)

    /// The Settings picker only ever offers 300/900/1800/3600s. A value outside that range —
    /// from a crafted backup, or a direct `PreferencesStore` write — must not reach the live scan
    /// scheduler: an interval like 0.001s reschedules the rescan timer to fire ~1000×/second.
    func testLoadRefreshIntervalBelowRangeClampsToMinimum() {
        UserDefaults.standard.set(0.001, forKey: "refreshInterval")
        let settings = SettingsAppearance()
        XCTAssertEqual(settings.refreshInterval, ScanMetrics.refreshIntervalMin)
    }

    func testLoadRefreshIntervalAboveRangeClampsToMaximum() {
        UserDefaults.standard.set(999_999.0, forKey: "refreshInterval")
        let settings = SettingsAppearance()
        XCTAssertEqual(settings.refreshInterval, ScanMetrics.refreshIntervalMax)
    }

    func testLoadRefreshIntervalWithinRangeIsUnchanged() {
        UserDefaults.standard.set(900.0, forKey: "refreshInterval")
        let settings = SettingsAppearance()
        XCTAssertEqual(settings.refreshInterval, 900)
    }

    func testSetRefreshIntervalClampsBelowRange() {
        let settings = SettingsAppearance()
        settings.setRefreshInterval(0.001)
        XCTAssertEqual(settings.refreshInterval, ScanMetrics.refreshIntervalMin)
    }

    func testSetRefreshIntervalClampsAboveRange() {
        let settings = SettingsAppearance()
        settings.setRefreshInterval(999_999)
        XCTAssertEqual(settings.refreshInterval, ScanMetrics.refreshIntervalMax)
    }

    func testLaunchModeDefaultIsWindow() {
        let settings = SettingsAppearance()
        XCTAssertEqual(settings.launchMode, .window)
    }

    func testLaunchModeAllCases() {
        let cases = LaunchMode.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.window))
        XCTAssertTrue(cases.contains(.fullscreen))
        XCTAssertTrue(cases.contains(.maximized))
    }

    func testLaunchModeRawValues() {
        XCTAssertEqual(LaunchMode.window.rawValue, "Window")
        XCTAssertEqual(LaunchMode.fullscreen.rawValue, "Full Screen")
        XCTAssertEqual(LaunchMode.maximized.rawValue, "Maximized")
    }

    func testLaunchModeIdentifiable() {
        let mode = LaunchMode.fullscreen
        XCTAssertEqual(mode.id, "Full Screen")
    }

    func testSetLaunchModePersistsToUserDefaults() {
        let settings = SettingsAppearance()
        settings.launchMode = .fullscreen

        let stored = UserDefaults.standard.string(forKey: "launchMode")
        XCTAssertEqual(stored, "Full Screen")
    }

    func testLoadLaunchModeFromUserDefaults() {
        UserDefaults.standard.set("Maximized", forKey: "launchMode")

        let settings = SettingsAppearance()
        XCTAssertEqual(settings.launchMode, .maximized)
    }

    func testLoadLaunchModeWithNoDataDefaultsToWindow() {
        UserDefaults.standard.removeObject(forKey: "launchMode")

        let settings = SettingsAppearance()
        XCTAssertEqual(settings.launchMode, .window)
    }

    func testLoadLaunchModeWithInvalidRawValueDefaultsToWindow() {
        UserDefaults.standard.set("InvalidMode", forKey: "launchMode")

        let settings = SettingsAppearance()
        XCTAssertEqual(settings.launchMode, .window)
    }

    func testAppModelLaunchModeDelegation() {
        let appModel = AppModel()
        appModel.launchMode = .fullscreen
        XCTAssertEqual(appModel.settings.launchMode, .fullscreen)
    }

    func testAppModelSetLaunchModeMethod() {
        let appModel = AppModel()
        appModel.setLaunchMode(.maximized)
        XCTAssertEqual(appModel.launchMode, .maximized)
    }

    func testLaunchModeRoundTrip() {
        let settings = SettingsAppearance()
        settings.launchMode = .maximized

        let settings2 = SettingsAppearance()
        XCTAssertEqual(settings2.launchMode, .maximized)
    }

    // MARK: - Show Hidden Apps Tests

    func testShowHiddenAppsDefaultIsFalse() {
        let settings = SettingsAppearance()
        XCTAssertFalse(settings.showHiddenApps)
    }

    func testSetShowHiddenAppsPersistsToUserDefaults() {
        let settings = SettingsAppearance()
        settings.showHiddenApps = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showHiddenApps"))
    }

    func testLoadShowHiddenAppsFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: "showHiddenApps")
        let settings = SettingsAppearance()
        XCTAssertTrue(settings.showHiddenApps)
    }

    func testShowHiddenAppsRoundTrip() {
        let settings = SettingsAppearance()
        settings.showHiddenApps = true

        let settings2 = SettingsAppearance()
        XCTAssertTrue(settings2.showHiddenApps)
    }

    func testAppModelShowHiddenAppsDelegation() {
        let appModel = AppModel()
        appModel.showHiddenApps = true
        XCTAssertTrue(appModel.settings.showHiddenApps)
    }
}
