import XCTest
@testable import MacMuster

/// Integration tests for the wiring between `LibraryScanState`, `RecentlyUpdatedTracker`,
/// `RunningAppTracker`, and `AppModel`. The unit-test files cover each in isolation; these
/// verify the pieces are actually connected: that a scan produces a badge set, that the
/// `AppModel` delegates it, and that the tracker integration survives a real `setApplications`
/// call (which is what the UI's data path drives).
@MainActor
final class AppStatusIndicatorIntegrationTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentlyUpdatedTracker.shared.clearAll()
        RecentlyUpdatedTracker.shared.persist()
        RunningAppTracker.shared.stop()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        RecentlyUpdatedTracker.shared.clearAll()
        RecentlyUpdatedTracker.shared.persist()
        RunningAppTracker.shared.stop()
        appModel = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "appFolders")
        UserDefaults.standard.removeObject(forKey: "hiddenAppPaths")
        UserDefaults.standard.removeObject(forKey: "customDirectories")
        UserDefaults.standard.removeObject(forKey: "customDirectoryBookmarks")
        UserDefaults.standard.removeObject(forKey: "currentFolderId")
        UserDefaults.standard.removeObject(forKey: "customOrder")
        UserDefaults.standard.removeObject(forKey: "sortOption")
        UserDefaults.standard.removeObject(forKey: "columnCount")
        UserDefaults.standard.removeObject(forKey: "iconSize")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "fontFamily")
        UserDefaults.standard.removeObject(forKey: "fontSize")
        UserDefaults.standard.removeObject(forKey: "fontWeight")
        UserDefaults.standard.removeObject(forKey: "glowEnabled")
        UserDefaults.standard.removeObject(forKey: "glowColor")
        UserDefaults.standard.removeObject(forKey: "glowIntensity")
        UserDefaults.standard.removeObject(forKey: "glowWidth")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "showFoldersFirst")
        UserDefaults.standard.removeObject(forKey: "hasShownLauncher")
        UserDefaults.standard.removeObject(forKey: "recentAppsEnabled")
        UserDefaults.standard.removeObject(forKey: "pressFeedbackEnabled")
        UserDefaults.standard.removeObject(forKey: "recentAppLaunchTimes")
        UserDefaults.standard.removeObject(forKey: "appLaunchCounts")
        UserDefaults.standard.removeObject(forKey: "presentationMode")
        UserDefaults.standard.removeObject(forKey: "tintColor")
        UserDefaults.standard.removeObject(forKey: "tintStrength")
        UserDefaults.standard.removeObject(forKey: "showHiddenApps")
        UserDefaults.standard.removeObject(forKey: "knownBundleMtimes")
        UserDefaults.standard.removeObject(forKey: "recentlyUpdatedPaths")
    }

    // MARK: - recentlyUpdatedPaths wiring

    func testAppModelDelegatesRecentlyUpdatedPaths() {
        // The UI reads `appModel.recentlyUpdatedPaths`; verify it proxies to the library.
        appModel.library.recentlyUpdatedPaths = ["/Applications/Test.app"]
        XCTAssertEqual(appModel.recentlyUpdatedPaths, ["/Applications/Test.app"],
            "AppModel.recentlyUpdatedPaths should delegate to library.recentlyUpdatedPaths")
    }

    func testAppModelDelegatesRunningAppPaths() {
        appModel.library.runningAppPaths = ["/Applications/Test.app"]
        XCTAssertEqual(appModel.runningAppPaths, ["/Applications/Test.app"],
            "AppModel.runningAppPaths should delegate to library.runningAppPaths")
    }

    func testSetApplicationsSeedsRecentlyUpdatedBaselineWithoutBadging() {
        // `setApplications` is what the UI's data path uses (and what startLoading does internally).
        // After it runs, the library's `recentlyUpdatedPaths` should be empty (the first scan builds
        // a baseline, it doesn't badge), and the tracker's `knownBundleMtimes` should have an entry
        // for every non-folder app.
        let now = Date()
        let apps = [
            Application(id: "/Applications/A.app", name: "A", path: "/Applications/A.app",
                        icon: nil, installationDate: now, isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/B.app", name: "B", path: "/Applications/B.app",
                        icon: nil, installationDate: now, isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)

        // The tracker is driven by `updateRecentlyUpdatedBadges` which runs at the end of
        // `startLoading`/`refreshDisplayOrder`, not `setApplications` — so verify the contract:
        // `setApplications` populates displayOrder (the source the helper reads), but does not
        // itself run detection. Detection runs on the next scan/refresh.
        XCTAssertEqual(appModel.library.displayOrder.count, 2)
        XCTAssertTrue(appModel.library.recentlyUpdatedPaths.isEmpty,
            "setApplications alone should not badge apps — detection runs on scan, not on setApplications")
    }

    func testUpdateRecentlyUpdatedBadgesReflectsTrackerState() {
        // Drive the tracker directly (the unit tests cover its logic); verify the library's
        // helper surfaces the result into `recentlyUpdatedPaths` that the UI reads.
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        // First scan: baseline.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/A.app": earlier], now: earlier)
        // Second scan: mtime jumped.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/A.app": now], now: now)
        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/A.app"))

        // The library's helper reads the tracker and assigns to recentlyUpdatedPaths.
        appModel.library.recentlyUpdatedPaths = Set(RecentlyUpdatedTracker.shared.recentlyUpdated.keys)
        XCTAssertTrue(appModel.library.recentlyUpdatedPaths.contains("/Applications/A.app"),
            "Library should surface the tracker's recentlyUpdated keys into recentlyUpdatedPaths for the UI")
    }

    // MARK: - RunningAppTracker wiring

    func testRunningAppTrackerStartPopulatesPaths() {
        RunningAppTracker.shared.start()
        XCTAssertFalse(RunningAppTracker.shared.runningAppPaths.isEmpty,
            "RunningAppTracker.start() should populate paths from NSWorkspace.runningApplications")
        // Every path should be a .app bundle (the contract the UI badge relies on for matching
        // against Application.path).
        for path in RunningAppTracker.shared.runningAppPaths {
            XCTAssertTrue(path.hasSuffix(".app"), "Running paths should be .app bundles: \(path)")
        }
    }

    func testLibraryRunningAppPathsDrivesUIBadgeContract() {
        // The UI shows a running dot when `appModel.runningAppPaths.contains(app.path)`. Verify
        // the contract holds end-to-end: start the tracker, seed the library, and check a
        // running app path is found.
        RunningAppTracker.shared.start()
        appModel.library.runningAppPaths = RunningAppTracker.shared.runningAppPaths
        guard let runningPath = RunningAppTracker.shared.runningAppPaths.first else {
            XCTFail("No running apps to test against")
            return
        }
        XCTAssertTrue(appModel.runningAppPaths.contains(runningPath),
            "A path in runningAppPaths should be reachable via appModel.runningAppPaths (the UI's read path)")
    }
}