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
}
