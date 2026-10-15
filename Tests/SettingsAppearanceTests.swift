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

    // MARK: - Bulk load applies side effects once (PERF-8)

    private func persistActivationSettings(enabled: Bool) {
        let store = PreferencesStore.shared
        store.saveGlobalHotkeyEnabled(enabled)
        store.saveHotkeyKeyCode(ActivationMetrics.defaultHotkeyKeyCode)
        store.saveHotkeyModifiers(ActivationMetrics.defaultHotkeyModifiers)
        store.saveHotCornerEnabled(enabled)
        store.saveHotCorner(HotCorner.topLeft.rawValue)
    }

    func testReloadFromPersistenceConfiguresActivationOnce() {
        persistActivationSettings(enabled: true)
        defer {
            persistActivationSettings(enabled: false)
            let settings = SettingsAppearance()
            settings.reloadFromPersistence()
        }
        let settings = SettingsAppearance()
        let before = ActivationManager.shared.applyCount

        settings.reloadFromPersistence()

        XCTAssertEqual(ActivationManager.shared.applyCount - before, 1,
                       "five activation settings were each re-registering the hotkey")
        XCTAssertTrue(settings.globalHotkeyEnabled)
        XCTAssertEqual(settings.hotCorner, .topLeft)
    }

    func testSingleActivationSettingChangeStillAppliesImmediately() {
        let settings = SettingsAppearance()
        let before = ActivationManager.shared.applyCount
        settings.hotCornerEnabled = false
        settings.hotkeyKeyCode = settings.hotkeyKeyCode
        XCTAssertEqual(ActivationManager.shared.applyCount - before, 2,
                       "outside a bulk load each change must still take effect")
    }

    // MARK: - Hotkey key-code bound (SEC-16)

    func testLoadOutOfRangeHotkeyKeyCodeFallsBackToDefault() {
        defer { UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode") }
        for bad in [Int(UInt32.max) + 1, Int.max, -1, 128] {
            UserDefaults.standard.set(bad, forKey: "hotkeyKeyCode")
            let settings = SettingsAppearance()
            XCTAssertEqual(settings.hotkeyKeyCode, ActivationMetrics.defaultHotkeyKeyCode, "\(bad)")
        }
    }

    func testLoadInRangeHotkeyKeyCodeIsKept() {
        defer { UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode") }
        UserDefaults.standard.set(49, forKey: "hotkeyKeyCode")
        XCTAssertEqual(SettingsAppearance().hotkeyKeyCode, 49)
    }

    func testRegisteringOutOfRangeKeyCodeFailsSoftInsteadOfTrapping() {
        let manager = ActivationManager.shared
        manager.apply(hotkeyEnabled: true, keyCode: Int.max,
                      modifiers: ActivationMetrics.defaultHotkeyModifiers, cornerEnabled: false, corner: .topRight)
        XCTAssertTrue(manager.hotkeyRegistrationFailed)
        manager.apply(hotkeyEnabled: false, keyCode: 0, modifiers: 0, cornerEnabled: false, corner: .topRight)
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
