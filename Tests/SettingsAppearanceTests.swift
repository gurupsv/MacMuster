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
