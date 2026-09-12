import XCTest
@testable import MacMuster

/// Covers **UX-4** and **UX-5**: settings that persisted correctly but had no effect on the
/// running app until it was relaunched.
///
/// Both had the same shape — a value read once when something was built, and never re-read —
/// so both are tested the same way: change the setting, then assert against the *live* object
/// rather than against what was written to `UserDefaults`.
@MainActor
final class LiveSettingsTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "presentationMode")
        appModel = AppModel()
    }

    override func tearDown() async throws {
        appModel.library.cleanupTimerAndObservers()
        appModel = nil
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "presentationMode")
    }

    // MARK: - UX-4: the scan timer must be rebuilt when the interval changes

    func testChangingTheRefreshIntervalReschedulesTheLiveTimer() {
        appModel.library.rescheduleRefreshTimer()
        XCTAssertEqual(appModel.library.activeRefreshTimerInterval, ScanMetrics.refreshIntervalDefault,
            "Precondition: the timer should start at the default interval")

        appModel.settings.refreshInterval = 60

        XCTAssertEqual(appModel.library.activeRefreshTimerInterval, 60,
            "Changing the interval must rebuild the live timer, not just persist the value — this is UX-4")
    }

    func testTheRefreshIntervalHookIsWiredByAppModel() {
        XCTAssertNotNil(appModel.settings.onRefreshIntervalChange,
            "AppModel must connect the setting to the library — the setting cannot reach a non-singleton itself")
    }

    func testReschedulingDoesNotDisturbTheIconCacheTimer() {
        // The two timers used to be built together, so rescheduling the scan interval would also
        // restart the six-hourly icon-cache job and push it out by another six hours each time.
        appModel.library.rescheduleRefreshTimer()
        let before = appModel.library.activeCacheRefreshTimerFireDate

        appModel.settings.refreshInterval = 120

        XCTAssertEqual(appModel.library.activeCacheRefreshTimerFireDate, before,
            "Changing the scan interval must leave the icon-cache timer's schedule alone")
    }

    func testIntervalSurvivesAsAPersistedValueToo() {
        appModel.settings.refreshInterval = 45
        XCTAssertEqual(PreferencesStore.shared.loadRefreshInterval(), 45,
            "The interval should still be persisted as well as applied")
    }

    // MARK: - UX-5: the overlay must repaint when appearance settings change

    func testRefreshAppearanceIsSafeBeforeTheWindowExists() {
        // Settings can be driven before the launcher has ever been shown, so the repaint entry
        // point must be a no-op rather than a trap when there is no window yet.
        OverlayWindowManager.shared.refreshAppearance()
    }

    func testAppearanceSettersReachTheOverlayWithoutCrashing() {
        // These setters now call into OverlayWindowManager. Before the window exists that must be
        // a no-op rather than a trap, since Settings can be driven before the launcher is shown.
        appModel.settings.overlayOpacity = 0.5
        appModel.settings.presentationMode = .sheet
        appModel.settings.tintStrength = 0.4
        appModel.settings.tintColor = .red

        XCTAssertEqual(appModel.settings.overlayOpacity, 0.5, "Opacity should still be applied to the model")
        XCTAssertEqual(appModel.settings.presentationMode, .sheet, "Presentation mode should still be applied to the model")
    }

    func testSheetModeBackgroundTracksTintSettings() {
        // The Sheet background is derived from tint colour and strength, so those have to be part
        // of what triggers a repaint — not just the opacity slider.
        appModel.settings.presentationMode = .sheet
        appModel.settings.tintStrength = 0.0
        let untinted = appModel.settings.tintedBackgroundColor()

        appModel.settings.tintStrength = 0.8
        let tinted = appModel.settings.tintedBackgroundColor()

        XCTAssertNotEqual(untinted, tinted, "Tint strength should change the colour the overlay paints")
    }
}
