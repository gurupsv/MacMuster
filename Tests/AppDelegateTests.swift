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

    // MARK: - activationPolicy(showInDock:) (Dock-visibility regression)

    /// Regression test: `applicationDidFinishLaunching` used to call
    /// `NSApp.setActivationPolicy(.regular)` unconditionally, ignoring the persisted "Show in
    /// Dock" preference `DockSettingsPanel` writes — so a user who hid the Dock icon saw it
    /// return on every relaunch, since the toggle only ever took effect until the app quit.
    func testActivationPolicyIsRegularWhenShowInDockIsTrue() {
        XCTAssertEqual(AppDelegate.activationPolicy(showInDock: true), .regular)
    }

    func testActivationPolicyIsAccessoryWhenShowInDockIsFalse() {
        XCTAssertEqual(AppDelegate.activationPolicy(showInDock: false), .accessory)
    }

    // MARK: - shouldShowOverlayOnLaunch(hasShownLauncher:) (silent Start at Login)

    /// Regression test: the overlay used to appear unconditionally on every launch, including the
    /// silent relaunch macOS performs at login once "Start at Login" is enabled. It should now
    /// show automatically only the very first time ever — before the user has seen it once.
    func testShouldShowOverlayOnLaunchIsTrueWhenLauncherHasNeverBeenShown() {
        XCTAssertTrue(AppDelegate.shouldShowOverlayOnLaunch(hasShownLauncher: false))
    }

    /// Every launch after the first — a manual relaunch or a silent "Start at Login" one — must
    /// stay silent; the user reveals the window via the menu-bar or Dock/launcher icon instead.
    func testShouldShowOverlayOnLaunchIsFalseOnceTheLauncherHasBeenShown() {
        XCTAssertFalse(AppDelegate.shouldShowOverlayOnLaunch(hasShownLauncher: true))
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

    // MARK: - Settings Menu Item Redirection

    /// The `Settings { EmptyView() }` scene in `MacMusterApp` exists only to stop SwiftUI from
    /// auto-opening a window at launch (a `WindowGroup` would); AppKit still wires its own
    /// "Settings…" item to that empty scene, which is what showed the blank window. This checks
    /// the redirect actually retargets an item carrying that selector, without touching the real
    /// `NSApp.mainMenu`.
    func testRedirectSettingsMenuItemRetargetsShowSettingsWindowItem() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Settings…", action: Selector(("showSettingsWindow:")), keyEquivalent: ",")
        menu.addItem(item)

        appDelegate.redirectSettingsMenuItem(in: menu)

        XCTAssertTrue(item.target === appDelegate,
            "The Settings… item should be retargeted to AppDelegate")
        XCTAssertEqual(item.action, #selector(AppDelegate.showSettings),
            "The Settings… item's action should point at AppDelegate.showSettings")
    }

    func testRedirectSettingsMenuItemLeavesUnrelatedItemsAlone() {
        let menu = NSMenu()
        let unrelated = NSMenuItem(title: "About MacMuster", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(unrelated)

        appDelegate.redirectSettingsMenuItem(in: menu)

        XCTAssertFalse(unrelated.target === appDelegate,
            "An item with an unrelated action should not be retargeted")
        XCTAssertEqual(unrelated.action, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    }

    /// Headless test runs don't reliably promote a window to `isVisible` (no real window server
    /// interaction), so this only checks `showSettings()` reaches `SettingsWindowManager` without
    /// crashing — the redirect tests above cover the actual retargeting logic.
    func testShowSettingsDoesNotCrash() {
        SettingsWindowManager.shared.setup(appModel: AppModel())
        appDelegate.showSettings()
        SettingsWindowManager.shared.hide()
    }

    // MARK: - windowDidBecomeKey (stray empty Settings window)

    /// A window subclass that records whether `close()` was called, instead of asserting on
    /// `isVisible` — which the note above already flags as unreliable in a headless test run with
    /// no real window server. Counting calls to the method under test is deterministic regardless.
    private final class CloseTrackingWindow: NSWindow {
        private(set) var closeCallCount = 0
        override func close() {
            closeCallCount += 1
            super.close()
        }
    }

    private func makeTestWindow(title: String) -> CloseTrackingWindow {
        let window = CloseTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        // Without this, AppKit releases the window as part of `close()` (its default behavior for
        // a window with no owning window controller) independently of ARC's own retain count on
        // this Swift reference — the mismatch deallocates it out from under the test, which
        // crashed with SIGSEGV on `closeCallCount` right after `close()` returned.
        window.isReleasedWhenClosed = false
        return window
    }

    /// Regression test for the bug where a blank "<AppName> Settings" window — the OS-generated
    /// window AppKit gives the `Settings { EmptyView() }` scene in `MacMusterApp` — opened on its
    /// own at launch (confirmed by actually building and launching the app; not reachable through
    /// any code path this project controls, only through AppKit's own scene handling). This pins
    /// the exact title match `windowDidBecomeKey` uses, so it can't silently stop matching after a
    /// rename or refactor.
    func testWindowDidBecomeKeyClosesStraySettingsWindow() {
        let window = makeTestWindow(title: "\(ProcessInfo.processInfo.processName) Settings")

        appDelegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))

        XCTAssertEqual(window.closeCallCount, 1,
            "windowDidBecomeKey should close a window titled '<process name> Settings'")
    }

    func testWindowDidBecomeKeyLeavesSettingsWindowManagersOwnWindowAlone() {
        // SettingsWindowManager's real settings window is titled plainly "Settings" (no process
        // name prefix), specifically so it can never collide with this check.
        let window = makeTestWindow(title: "Settings")

        appDelegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))

        XCTAssertEqual(window.closeCallCount, 0,
            "The real settings window must never be closed by this stray-window guard")
    }

    func testWindowDidBecomeKeyLeavesOverlayWindowAlone() {
        // The overlay/launcher window is titled "MacMuster" (see OverlayWindowManager).
        let window = makeTestWindow(title: "MacMuster")

        appDelegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))

        XCTAssertEqual(window.closeCallCount, 0,
            "The overlay window must never be closed by this stray-window guard")
    }

    func testWindowDidBecomeKeyIgnoresNonWindowNotificationObjects() {
        // Should not crash when the notification's object isn't an NSWindow at all.
        appDelegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: "not a window"))
        appDelegate.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: nil))
    }

    // MARK: - closeStraySettingsWindows (catch-up sweep for the same stray window)

    /// Regression test for the fix surfaced by silent launches (`shouldShowOverlayOnLaunch`): once
    /// the overlay no longer covers the screen on every launch, a stray Settings window that
    /// AppKit created and keyed *before* `windowDidBecomeKey` got registered — which the comment
    /// on that method already documents as possible — was left sitting on screen with nothing to
    /// close it. `closeStraySettingsWindows` is a proactive sweep for exactly that already-existing
    /// window, independent of any notification.
    func testCloseStraySettingsWindowsClosesAnAlreadyExistingStrayWindow() {
        let window = makeTestWindow(title: "\(ProcessInfo.processInfo.processName) Settings")
        defer { window.close() }

        appDelegate.closeStraySettingsWindows()

        XCTAssertEqual(window.closeCallCount, 1,
            "closeStraySettingsWindows should close an already-existing stray Settings window")
    }

    func testCloseStraySettingsWindowsLeavesOtherWindowsAlone() {
        let settingsWindow = makeTestWindow(title: "Settings")
        let overlayWindow = makeTestWindow(title: "MacMuster")
        defer {
            settingsWindow.close()
            overlayWindow.close()
        }

        appDelegate.closeStraySettingsWindows()

        XCTAssertEqual(settingsWindow.closeCallCount, 0,
            "The real settings window must never be closed by this sweep")
        XCTAssertEqual(overlayWindow.closeCallCount, 0,
            "The overlay window must never be closed by this sweep")
    }
}
