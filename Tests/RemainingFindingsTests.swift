import XCTest
@testable import MacMuster

/// Covers the last batch of review findings: **UX-8**, **UX-9**, **PERF-3**, **PERF-6**,
/// **BUG-3**, **BUG-6** and **BUG-8**. (**BUG-5** is a threading fix with no observable
/// behaviour change; it is covered indirectly by the existing IconService tests.)
@MainActor
final class RemainingFindingsTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        for key in ["appFolders", "hiddenAppPaths", "customOrder", "currentFolderId", "sortOption"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        RunningAppTracker.shared.onChange = nil
        RunningAppTracker.shared.runningAppPaths = []
        RecentlyUpdatedTracker.shared.clearAll()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        appModel.library.cleanupTimerAndObservers()
        appModel = nil
        RunningAppTracker.shared.onChange = nil
        RunningAppTracker.shared.runningAppPaths = []
        RecentlyUpdatedTracker.shared.clearAll()
    }

    private func app(_ name: String, isFolder: Bool = false) -> Application {
        Application(id: "/Applications/\(name).app", name: name, path: "/Applications/\(name).app",
                    installationDate: Date(timeIntervalSince1970: 1_600_000_000), isFolder: isFolder)
    }

    // MARK: - UX-9: folders must be findable by name

    func testSearchFindsFoldersByName() {
        appModel.library.setApplications([app("Preview"), app("Safari")])
        _ = appModel.createFolder(name: "Graphics", appPaths: ["/Applications/Preview.app"])

        appModel.searchTerm = "graph"
        let results = appModel.getDisplayedApps()

        XCTAssertTrue(results.contains { $0.isFolder && $0.name == "Graphics" },
            "A folder must be findable by name — this is UX-9. Got: \(results.map(\.name))")
    }

    func testSearchStillFindsAppsThatLiveInsideAFolder() {
        // The behaviour the old substitution existed to preserve — it must not regress.
        appModel.library.setApplications([app("Preview"), app("Safari")])
        _ = appModel.createFolder(name: "Graphics", appPaths: ["/Applications/Preview.app"])

        appModel.searchTerm = "preview"
        let results = appModel.getDisplayedApps()

        XCTAssertTrue(results.contains { $0.name == "Preview" },
            "An app inside a folder must still be findable: \(results.map(\.name))")
    }

    func testSearchReturnsNoDuplicates() {
        appModel.library.setApplications([app("Preview"), app("Print")])
        _ = appModel.createFolder(name: "Printing", appPaths: ["/Applications/Print.app"])

        appModel.searchTerm = "pri"
        let results = appModel.getDisplayedApps()

        XCTAssertEqual(Set(results.map(\.id)).count, results.count,
            "Searching apps and folders together must not double-count: \(results.map(\.name))")
    }

    func testEmptySearchStillShowsFolderedAppsOnlyViaTheirFolder() {
        appModel.library.setApplications([app("Preview"), app("Safari")])
        _ = appModel.createFolder(name: "Graphics", appPaths: ["/Applications/Preview.app"])

        appModel.searchTerm = ""
        let results = appModel.getDisplayedApps()

        XCTAssertFalse(results.contains { $0.name == "Preview" && !$0.isFolder },
            "With no search term a foldered app is represented by its folder, not listed loose")
        XCTAssertTrue(results.contains { $0.name == "Graphics" }, "The folder itself should show")
    }

    // MARK: - UX-8: badge state must be spoken

    func testAccessibilityLabelAnnouncesRunningState() {
        let running = app("Mail")
        appModel.library.runningAppPaths = [running.path]

        let label = ContentView(appModel: appModel).accessibilityLabel(for: running)
        XCTAssertTrue(label.contains("running"),
            "A running app must say so non-visually — the badge is accessibilityHidden: \(label)")
    }

    func testAccessibilityLabelAnnouncesRecentlyUpdatedState() {
        let updated = app("Xcode")
        appModel.library.recentlyUpdatedPaths = [updated.path]

        let label = ContentView(appModel: appModel).accessibilityLabel(for: updated)
        XCTAssertTrue(label.contains("recently updated"),
            "A recently-updated app must say so non-visually: \(label)")
    }

    func testAccessibilityLabelCombinesBothStates() {
        let both = app("Slack")
        appModel.library.runningAppPaths = [both.path]
        appModel.library.recentlyUpdatedPaths = [both.path]

        let label = ContentView(appModel: appModel).accessibilityLabel(for: both)
        XCTAssertTrue(label.contains("running") && label.contains("recently updated"),
            "Both states should be announced when both apply: \(label)")
        XCTAssertTrue(label.hasPrefix("Slack"), "The app's name should still come first: \(label)")
    }

    func testAccessibilityLabelIsPlainWhenNoBadgesApply() {
        let label = ContentView(appModel: appModel).accessibilityLabel(for: app("Calculator"))
        XCTAssertFalse(label.contains("running"), "An idle app should not claim to be running: \(label)")
        XCTAssertFalse(label.contains("recently updated"), "An unchanged app should not claim an update: \(label)")
    }

    // MARK: - PERF-3: pruning must not scale quadratically

    func testPruningRemovesVanishedAppsAndKeepsTheRest() {
        let tracker = RecentlyUpdatedTracker.shared
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        tracker.detectUpdatedApps(currentMtimesByPath: [
            "/Applications/A.app": old, "/Applications/B.app": old, "/Applications/C.app": old,
        ], now: old)

        // B and C uninstalled.
        tracker.detectUpdatedApps(currentMtimesByPath: ["/Applications/A.app": old], now: old)

        XCTAssertEqual(Set(tracker.knownBundleMtimes.keys), ["/Applications/A.app"],
            "Only apps present in the latest scan should keep a baseline")
    }

    func testPruningALargeSetIsNotQuadratic() {
        // Guards the shape of the fix rather than a timing threshold: one filtered pass instead of
        // a copy-on-write of the whole dictionary per removal.
        let tracker = RecentlyUpdatedTracker.shared
        let now = Date(timeIntervalSince1970: 1_600_000_000)
        var many: [String: Date] = [:]
        for i in 0..<2000 { many["/Applications/App\(i).app"] = now }
        tracker.detectUpdatedApps(currentMtimesByPath: many, now: now)
        XCTAssertEqual(tracker.knownBundleMtimes.count, 2000, "Precondition: baseline populated")

        let started = Date()
        tracker.detectUpdatedApps(currentMtimesByPath: ["/Applications/App0.app": now], now: now)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(tracker.knownBundleMtimes.count, 1, "1999 entries should be pruned in one pass")
        XCTAssertLessThan(elapsed, 1.0, "Pruning 1999 entries should not take anywhere near a second")
    }

    func testExpiredBadgesArePruned() {
        let tracker = RecentlyUpdatedTracker.shared
        let now = Date()
        tracker.recentlyUpdated = [
            "/Applications/Fresh.app": now,
            "/Applications/Stale.app": now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds - 60),
        ]

        tracker.pruneExpired(now: now)

        XCTAssertEqual(Set(tracker.recentlyUpdated.keys), ["/Applications/Fresh.app"],
            "Only entries inside the badge window should survive")
    }

    // MARK: - PERF-6: icons must cover the largest size at 2x

    func testRasterSizeCoversTheLargestIconOnRetina() {
        XCTAssertGreaterThanOrEqual(CGFloat(IconMetrics.iconRasterPixelSizePx), IconMetrics.iconSizeExtraLarge * 2,
            "Icons must be rasterized at least 2x the largest icon size, or Extra Large renders soft")
    }

    // MARK: - BUG-6: the folder accessor says what it does

    func testAppsInFolderReturnsItsMembers() {
        appModel.library.setApplications([app("Preview"), app("Safari")])
        let folder = appModel.createFolder(name: "Graphics", appPaths: ["/Applications/Preview.app"])
        let members = appModel.appsInFolder(for: folder!.id)

        XCTAssertEqual(members.map(\.name), ["Preview"], "The folder's members should be returned")
    }

    func testAppsInFolderReturnsEmptyForAnUnknownFolder() {
        XCTAssertTrue(appModel.appsInFolder(for: "no-such-folder").isEmpty,
            "An unknown folder id yields no apps rather than trapping")
    }
}
