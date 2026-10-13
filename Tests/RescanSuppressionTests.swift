import XCTest
import Observation
@testable import MacMuster

/// Covers skipping a rescan that found nothing new. Before, every filesystem-event rescan replaced
/// the catalog, rebuilt the index, bumped `dataVersion` (re-evaluating `ContentView.body` — 5 body
/// passes for 5 no-change rescans, measured; 0 after) and re-persisted the update baseline, even
/// when the scan matched what was on screen.
@MainActor
final class RescanSuppressionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func app(_ path: String, name: String? = nil, date: Date? = nil, isFolder: Bool = false,
                     contained: [String]? = nil, icon: NSImage? = nil) -> Application {
        Application(id: path, name: name ?? (path as NSString).lastPathComponent, path: path, icon: icon,
                    installationDate: date ?? now, isFolder: isFolder, containedApps: contained)
    }

    // MARK: - catalogsMatch

    func testIdenticalCatalogsMatch() {
        let a = [app("/Applications/A.app"), app("/Applications/B.app")]
        XCTAssertTrue(LibraryScanState.catalogsMatch(a, a))
    }

    func testOrderDoesNotMatter() {
        let fresh = [app("/Applications/B.app"), app("/Applications/A.app")]
        let current = [app("/Applications/A.app"), app("/Applications/B.app")]
        XCTAssertTrue(LibraryScanState.catalogsMatch(fresh, current), "The live catalog is sorted; a scan is not")
    }

    func testLoadedIconsDoNotMakeCatalogsDiffer() {
        let fresh = [app("/Applications/A.app")]
        let current = [app("/Applications/A.app", icon: NSImage(size: NSSize(width: 4, height: 4)))]
        XCTAssertTrue(LibraryScanState.catalogsMatch(fresh, current), "A scan carries no icons; the live apps do")
    }

    func testAChangedModificationDateIsAChange() {
        let fresh = [app("/Applications/A.app", date: now.addingTimeInterval(60))]
        XCTAssertFalse(LibraryScanState.catalogsMatch(fresh, [app("/Applications/A.app")]), "An updated app must be applied")
    }

    func testAChangedNameIsAChange() {
        XCTAssertFalse(LibraryScanState.catalogsMatch([app("/Applications/A.app", name: "A2")], [app("/Applications/A.app")]))
    }

    func testChangedContainedAppsIsAChange() {
        let fresh = [app("/Applications/Office", isFolder: true, contained: ["/x/1.app", "/x/2.app", "/x/3.app"])]
        let current = [app("/Applications/Office", isFolder: true, contained: ["/x/1.app", "/x/2.app"])]
        XCTAssertFalse(LibraryScanState.catalogsMatch(fresh, current))
    }

    func testAChangedFolderFlagIsAChange() {
        XCTAssertFalse(LibraryScanState.catalogsMatch([app("/Applications/A", isFolder: true)], [app("/Applications/A")]))
    }

    func testAnAddedAppIsAChange() {
        XCTAssertFalse(LibraryScanState.catalogsMatch([app("/Applications/A.app"), app("/Applications/B.app")], [app("/Applications/A.app")]))
    }

    func testARemovedAppIsAChange() {
        XCTAssertFalse(LibraryScanState.catalogsMatch([app("/Applications/A.app")], [app("/Applications/A.app"), app("/Applications/B.app")]))
    }

    func testAReplacedAppWithTheSameCountIsAChange() {
        XCTAssertFalse(LibraryScanState.catalogsMatch([app("/Applications/B.app")], [app("/Applications/A.app")]),
            "Equal counts must not be mistaken for equal catalogs")
    }

    func testDuplicatePathsAreTreatedAsAChange() {
        let dup = [app("/Applications/A.app"), app("/Applications/A.app")]
        XCTAssertFalse(LibraryScanState.catalogsMatch(dup, dup), "A doubtful comparison must err towards applying the scan")
    }

    func testEmptyCatalogsMatch() {
        XCTAssertTrue(LibraryScanState.catalogsMatch([], []))
    }

    // MARK: - refreshDisplayOrder

    private func seededLibrary() -> (AppModel, LibraryScanState) {
        let model = AppModel()
        let library = model.library
        library.isLoading = false
        let scanned = ApplicationScanner.shared.scanDirectories(directories: library.currentScanDirectories).apps
        library.setApplications(scanned)
        return (model, library)
    }

    func testRescanThatFindsNothingNewDoesNotBumpDataVersion() async {
        let (_, library) = seededLibrary()
        try? XCTSkipIf(library.displayOrder.isEmpty, "No apps found to scan")
        let before = library.dataVersion

        await library.refreshDisplayOrder(reason: .fileSystemEvent)

        XCTAssertEqual(library.dataVersion, before, "A no-change rescan must not invalidate the display")
    }

    func testRescanThatFindsAChangeAppliesIt() async throws {
        let (_, library) = seededLibrary()
        try XCTSkipIf(library.displayOrder.count < 2, "Need at least two apps")
        let missing = library.displayOrder[0]
        library.setApplications(Array(library.displayOrder.dropFirst()))   // the scan will "find" one more
        let before = library.dataVersion

        await library.refreshDisplayOrder(reason: .fileSystemEvent)

        XCTAssertGreaterThan(library.dataVersion, before)
        XCTAssertNotNil(library.appPathIndex[missing.path], "The newly found app must be applied")
    }

    func testUserRequestedRefreshAlwaysApplies() async {
        let (_, library) = seededLibrary()
        try? XCTSkipIf(library.displayOrder.isEmpty, "No apps found to scan")
        let before = library.dataVersion

        await library.refreshDisplayOrder(reason: .userRequested)

        XCTAssertGreaterThan(library.dataVersion, before, "Refresh Now rebuilds icons, so it never short-circuits")
    }

    // MARK: - Category counts

    /// Passes with or without the explicit comparison on a runtime whose Observation already drops
    /// equal writes (this one does), so it guards the behaviour rather than the mechanism.
    func testCategoryCountsArePublishedOnlyWhenTheyChange() {
        let model = AppModel()
        model.library.setApplications([app("/Applications/A.app"), app("/Applications/B.app")])
        model.library.refreshCategoryCounts()   // settle

        let flag = Flag()
        withObservationTracking({ _ = model.navigation.categoryCounts }, onChange: { flag.fired = true })
        model.library.refreshCategoryCounts()

        XCTAssertFalse(flag.fired, "Unchanged counts must not notify observers")
    }

    func testCategoryCountsStillUpdateWhenTheyChange() {
        let model = AppModel()
        model.library.setApplications([app("/Applications/A.app")])
        let before = model.navigation.categoryCounts[.all]

        model.library.setApplications([app("/Applications/A.app"), app("/Applications/B.app")])

        XCTAssertEqual(before, 1)
        XCTAssertEqual(model.navigation.categoryCounts[.all], 2)
    }

    private final class Flag: @unchecked Sendable { var fired = false }

    // MARK: - Update baseline persistence

    private func clearKeys() {
        UserDefaults.standard.removeObject(forKey: "knownBundleMtimes")
        UserDefaults.standard.removeObject(forKey: "recentlyUpdatedPaths")
    }

    func testUnchangedMtimesDoNotRewriteThePersistedBaseline() async throws {
        let tracker = RecentlyUpdatedTracker.shared
        tracker.clearAll(); tracker.persist(); clearKeys()
        defer { tracker.clearAll(); tracker.persist(); clearKeys() }
        let mtimes = ["/Applications/A.app": now, "/Applications/B.app": now]

        tracker.detectUpdatedApps(currentMtimesByPath: mtimes, now: now)   // first sight: baseline changes
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "knownBundleMtimes"), "A real change must still persist")

        clearKeys()
        tracker.detectUpdatedApps(currentMtimesByPath: mtimes, now: now)   // identical: nothing moved
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(UserDefaults.standard.data(forKey: "knownBundleMtimes"), "An unchanged baseline must not be rewritten")
    }

    func testAnUpdatedAppStillPersists() async throws {
        let tracker = RecentlyUpdatedTracker.shared
        tracker.clearAll(); tracker.persist(); clearKeys()
        defer { tracker.clearAll(); tracker.persist(); clearKeys() }
        tracker.detectUpdatedApps(currentMtimesByPath: ["/Applications/A.app": now], now: now)
        try await Task.sleep(nanoseconds: 800_000_000)
        clearKeys()

        tracker.detectUpdatedApps(currentMtimesByPath: ["/Applications/A.app": now.addingTimeInterval(3600)], now: now)
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNotNil(UserDefaults.standard.data(forKey: "recentlyUpdatedPaths"), "A newly updated app must be persisted")
    }
}
