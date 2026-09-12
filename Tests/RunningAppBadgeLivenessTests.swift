import XCTest
@testable import MacMuster

/// Covers **UX-1**: the running dot was frozen at app launch.
///
/// `AppDelegate` used to seed the badge with a single assignment:
///
/// ```swift
/// appModel.library.runningAppPaths = RunningAppTracker.shared.runningAppPaths
/// ```
///
/// `Set` is a value type, so that copied a snapshot. The tracker's launch/terminate observers
/// then updated only *its own* copy, and the copy the UI reads never moved again — apps started
/// or quit after launch never gained or lost their dot.
///
/// The fix is an `onChange` hook the tracker publishes through. These tests pin the two things
/// that matter: that a change after the initial seed actually reaches the library, and that the
/// hook stays quiet when nothing really changed.
@MainActor
final class RunningAppBadgeLivenessTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        RunningAppTracker.shared.stop()
        RunningAppTracker.shared.onChange = nil
        RunningAppTracker.shared.runningAppPaths = []
        appModel = AppModel()
    }

    override func tearDown() async throws {
        RunningAppTracker.shared.stop()
        // The tracker is a singleton, so a hook left installed would fire into a dead AppModel
        // during a later test.
        RunningAppTracker.shared.onChange = nil
        RunningAppTracker.shared.runningAppPaths = []
        appModel = nil
    }

    /// Wires the tracker to the library exactly as `AppDelegate.applicationDidFinishLaunching` does.
    private func installProductionHook() {
        RunningAppTracker.shared.onChange = { [weak appModel] paths in
            appModel?.library.runningAppPaths = paths
        }
    }

    // MARK: - The regression

    func testChangesAfterTheInitialSeedReachTheLibrary() {
        installProductionHook()
        RunningAppTracker.shared.runningAppPaths = ["/Applications/Seeded.app"]
        XCTAssertEqual(appModel.runningAppPaths, ["/Applications/Seeded.app"], "Precondition: the initial seed should propagate")

        // The regression: a *subsequent* change must also land. Under the old one-time copy the
        // library kept the seeded value forever.
        RunningAppTracker.shared.runningAppPaths = ["/Applications/LaunchedLater.app"]

        XCTAssertEqual(appModel.runningAppPaths, ["/Applications/LaunchedLater.app"],
            "A change after the initial seed must reach library.runningAppPaths — this is UX-1")
        XCTAssertFalse(appModel.runningAppPaths.contains("/Applications/Seeded.app"),
            "The library must not still be holding the frozen launch-time snapshot")
    }

    func testAppLaunchingAddsItsBadgeAndQuittingRemovesIt() {
        installProductionHook()
        RunningAppTracker.shared.runningAppPaths = ["/Applications/Safari.app"]

        // Launch
        RunningAppTracker.shared.runningAppPaths.insert("/Applications/Mail.app")
        XCTAssertTrue(appModel.runningAppPaths.contains("/Applications/Mail.app"),
            "An app launching after startup should gain its badge")
        XCTAssertTrue(appModel.runningAppPaths.contains("/Applications/Safari.app"),
            "Already-running apps should keep their badge")

        // Quit
        RunningAppTracker.shared.runningAppPaths.remove("/Applications/Mail.app")
        XCTAssertFalse(appModel.runningAppPaths.contains("/Applications/Mail.app"),
            "An app quitting should lose its badge")
        XCTAssertTrue(appModel.runningAppPaths.contains("/Applications/Safari.app"),
            "Quitting one app should not disturb the others")
    }

    func testRefreshSnapshotPropagatesThroughTheHook() {
        installProductionHook()
        RunningAppTracker.shared.runningAppPaths = ["/Applications/Stale.app"]

        RunningAppTracker.shared.refreshSnapshot()

        XCTAssertEqual(appModel.runningAppPaths, RunningAppTracker.shared.runningAppPaths,
            "refreshSnapshot should push the real snapshot through to the library")
        XCTAssertFalse(appModel.runningAppPaths.contains("/Applications/Stale.app"),
            "A stale entry should be cleared by a real snapshot")
    }

    // MARK: - onChange semantics

    func testHookFiresOnlyOnRealChanges() {
        var fireCount = 0
        var lastValue: Set<String>?
        RunningAppTracker.shared.onChange = { paths in
            fireCount += 1
            lastValue = paths
        }

        RunningAppTracker.shared.runningAppPaths = ["/Applications/A.app"]
        XCTAssertEqual(fireCount, 1, "A real change should fire the hook")
        XCTAssertEqual(lastValue, ["/Applications/A.app"], "The hook should carry the new value")

        // Re-inserting a path that is already present is not a change — an app relaunching into
        // a path already in the set must not churn the UI.
        RunningAppTracker.shared.runningAppPaths.insert("/Applications/A.app")
        XCTAssertEqual(fireCount, 1, "Inserting an already-present path should not fire the hook")

        // Nor is removing something that was never there.
        RunningAppTracker.shared.runningAppPaths.remove("/Applications/Absent.app")
        XCTAssertEqual(fireCount, 1, "Removing an absent path should not fire the hook")

        // Assigning an equal set is not a change either.
        RunningAppTracker.shared.runningAppPaths = ["/Applications/A.app"]
        XCTAssertEqual(fireCount, 1, "Assigning an equal set should not fire the hook")

        RunningAppTracker.shared.runningAppPaths.insert("/Applications/B.app")
        XCTAssertEqual(fireCount, 2, "A genuine addition should fire the hook again")
    }

    func testStartDoesNotClearAnAlreadyInstalledHook() {
        // AppDelegate installs the hook *before* calling start(), and start() begins with stop().
        // If stop() ever cleared onChange, the initial snapshot — and everything after it —
        // would silently stop reaching the UI.
        installProductionHook()

        RunningAppTracker.shared.start()

        XCTAssertNotNil(RunningAppTracker.shared.onChange, "start()/stop() must not clear the hook")
        XCTAssertEqual(appModel.runningAppPaths, RunningAppTracker.shared.runningAppPaths,
            "start() should seed the library through the hook installed beforehand")
    }

    // MARK: - Cost of liveness

    func testBadgeUpdatesDoNotInvalidateTheDisplayCache() {
        // Now that the badge updates on every system-wide launch and quit, bumping dataVersion
        // here would recompute the entire grid each time. No display decision reads this set, so
        // the counter must stay put; @Observable re-renders the affected cells on its own.
        installProductionHook()
        let before = appModel.library.dataVersion

        RunningAppTracker.shared.runningAppPaths = ["/Applications/Whatever.app"]

        XCTAssertEqual(appModel.runningAppPaths, ["/Applications/Whatever.app"], "Precondition: the update should land")
        XCTAssertEqual(appModel.library.dataVersion, before,
            "Running-app changes must not bump dataVersion — that would rebuild the whole display list")
    }
}
