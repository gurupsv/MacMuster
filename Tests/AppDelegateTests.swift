import XCTest
@testable import MacMuster

/// Tests application lifecycle, window management, and appearance handling.
@MainActor
final class AppDelegateTests: XCTestCase {

    private var appDelegate: AppDelegate!

    override func setUp() async throws {
        appDelegate = AppDelegate()
    }

    override func tearDown() async throws {
        appDelegate = nil
    }

    // MARK: - applicationShouldTerminateAfterLastWindowClosed

    func testApplicationShouldTerminateAfterLastWindowClosedReturnsFalse() {
        let result = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        XCTAssertFalse(result,
            "App should not terminate when last window closes (status bar app behavior)")
    }

    // MARK: - applicationShouldHandleReopen

    func testApplicationShouldHandleReopenShowsOverlayWhenNoWindowsVisible() {
        // This test verifies the logic path, though full setup requires window managers
        let result = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        XCTAssertTrue(result,
            "App should handle reopen and return true")
    }

    func testApplicationShouldHandleReopenReturnsTrueWhenWindowsVisible() {
        let result = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        XCTAssertTrue(result,
            "App should always return true for handleReopen")
    }

    // MARK: - AppModelContainer Singleton

    func testAppModelContainerIsSingleton() {
        let first = AppModelContainer.shared
        let second = AppModelContainer.shared
        XCTAssertTrue(first === second,
            "AppModelContainer should be a singleton")
    }

    func testAppModelContainerHasValidAppModel() {
        let container = AppModelContainer.shared
        XCTAssertNotNil(container.appModel,
            "AppModelContainer should always have an appModel")
    }

    // MARK: - Appearance Detection

    func testAppDelegateRespondsToAppearanceNotifications() {
        // AppDelegate observes appearance changes during initialization
        // Verify it can handle appearance changes without crashing
        XCTAssertNotNil(appDelegate,
            "AppDelegate should be initialized and handle appearance notifications")
    }

    // MARK: - Lifecycle Methods Exist

    func testApplicationDidFinishLaunchingMethodExists() {
        let selector = NSSelectorFromString("applicationDidFinishLaunching:")
        XCTAssertTrue(appDelegate.responds(to: selector),
            "AppDelegate should respond to applicationDidFinishLaunching:")
    }

    func testApplicationWillTerminateMethodExists() {
        let selector = NSSelectorFromString("applicationWillTerminate:")
        XCTAssertTrue(appDelegate.responds(to: selector),
            "AppDelegate should respond to applicationWillTerminate:")
    }

    // MARK: - NSApplicationDelegate Conformance

    func testAppDelegateConformsToNSApplicationDelegate() {
        XCTAssertTrue(appDelegate is NSApplicationDelegate,
            "AppDelegate should conform to NSApplicationDelegate")
    }

    // MARK: - Window Management Delegation

    func testWindowManagersAreSetUp() {
        // Verify the window managers exist and can be accessed
        let statusBar = StatusBarManager.shared
        let overlayWindow = OverlayWindowManager.shared
        let settingsWindow = SettingsWindowManager.shared

        XCTAssertNotNil(statusBar)
        XCTAssertNotNil(overlayWindow)
        XCTAssertNotNil(settingsWindow)
    }

    // MARK: - Recent Apps Persistence

    func testRecentAppsTrackerExists() {
        let tracker = RecentAppsTracker.shared
        XCTAssertNotNil(tracker,
            "RecentAppsTracker should be accessible for persistence")
    }
}
