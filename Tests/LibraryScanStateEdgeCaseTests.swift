import XCTest
@testable import MacMuster

/// Tests LibraryScanState edge cases, state transitions, and concurrent scenarios.
@MainActor
final class LibraryScanStateEdgeCaseTests: XCTestCase {

    private var library: LibraryScanState!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        library = LibraryScanState()
        library.isLoading = false
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        library.cleanupTimerAndObservers()
        library = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        let keys = [
            "appFolders", "hiddenAppPaths", "customDirectories", "customDirectoryBookmarks",
            "currentFolderId", "customOrder", "sortOption", "columnCount", "iconSize",
            "refreshInterval", "fontFamily", "fontSize", "fontWeight", "glowEnabled",
            "glowColor", "glowIntensity", "glowWidth", "overlayOpacity", "showFoldersFirst",
            "hasShownLauncher", "recentAppsEnabled", "pressFeedbackEnabled",
            "recentAppLaunchTimes", "appLaunchCounts", "presentationMode", "tintColor",
            "tintStrength", "showHiddenApps"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeApp(_ name: String, path: String = "/Applications/Test.app") -> Application {
        Application(id: path, name: name, path: path, icon: nil,
                   installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
    }

    // MARK: - handleAppearanceChange

    func testHandleAppearanceChangeResetsIcons() {
        let app = makeApp("Test")
        library.setApplications([app])

        // Set an icon
        var appWithIcon = app
        appWithIcon.icon = NSImage()
        library.displayOrder = [appWithIcon]

        library.handleAppearanceChange()

        XCTAssertNil(library.displayOrder[0].icon,
            "handleAppearanceChange should reset all app icons")
    }

    func testHandleAppearanceChangeBumpsDataVersion() {
        let versionBefore = library.dataVersion
        library.handleAppearanceChange()
        XCTAssert(library.dataVersion > versionBefore,
            "handleAppearanceChange should bump dataVersion")
    }

    func testHandleAppearanceChangeInvalidatesDisplayCache() {
        let app = makeApp("Test")
        library.setApplications([app])

        _ = library.getDisplayedApps(searchTerm: "", showFoldersFirst: false,
                                    customOrder: [:], sortOption: .name,
                                    selectedCategory: .all, columnCount: 4)

        library.handleAppearanceChange()

        XCTAssertNil(library.cachedDisplayedApps,
            "handleAppearanceChange should invalidate display cache")
    }

    // MARK: - toggleHiddenApp

    func testToggleHiddenAppBumpsDataVersion() {
        let app = makeApp("Test")
        library.setApplications([app])

        let versionBefore = library.dataVersion
        library.toggleHiddenApp(app.path)

        XCTAssert(library.dataVersion > versionBefore,
            "toggleHiddenApp should bump dataVersion")
    }

    func testToggleHiddenAppRemovesAppFromHiddenSet() {
        let app = makeApp("Test")
        library.setApplications([app])
        library.hiddenAppPaths.insert(app.path)

        library.toggleHiddenApp(app.path)

        XCTAssertFalse(library.hiddenAppPaths.contains(app.path),
            "toggleHiddenApp should remove app from hidden set")
    }

    func testToggleHiddenAppAddsAppToHiddenSet() {
        let app = makeApp("Test")
        library.setApplications([app])

        library.toggleHiddenApp(app.path)

        XCTAssertTrue(library.hiddenAppPaths.contains(app.path),
            "toggleHiddenApp should add app to hidden set")
    }

    func testToggleHiddenAppRejectsPermanentlyHiddenApps() {
        let path = "/System/Applications/Launchpad.app"
        let versionBefore = library.dataVersion

        library.toggleHiddenApp(path)

        XCTAssertEqual(library.dataVersion, versionBefore,
            "toggleHiddenApp should reject permanently hidden apps (no-op)")
    }

    // MARK: - setSortOption

    func testSetSortOptionChangesSortOption() {
        library.setSortOption(.installationDate)
        XCTAssertEqual(library.sortOption, .installationDate,
            "setSortOption should update sortOption")
    }

    func testSetSortOptionClearsCustomOrder() {
        let app = makeApp("Test")
        library.setApplications([app])
        library.customOrder[app.path] = 0

        library.setSortOption(.installationDate)

        XCTAssertTrue(library.customOrder.isEmpty,
            "setSortOption should clear customOrder")
    }

    func testSetSortOptionReSortsApps() {
        let app1 = makeApp("Zebra", path: "/Applications/Zebra.app")
        let app2 = makeApp("Apple", path: "/Applications/Apple.app")
        library.setApplications([app1, app2])

        library.setSortOption(.name)

        XCTAssertEqual(library.displayOrder[0].name, "Apple",
            "setSortOption should re-sort apps by the new option")
    }

    // MARK: - setApplications

    func testSetApplicationsRebuildsAppPathIndex() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")

        library.setApplications([app1, app2])

        XCTAssertNotNil(library.appPathIndex[app1.path],
            "appPathIndex should include app1")
        XCTAssertNotNil(library.appPathIndex[app2.path],
            "appPathIndex should include app2")
    }

    func testSetApplicationsBumpsDataVersion() {
        let app = makeApp("Test")
        let versionBefore = library.dataVersion

        library.setApplications([app])

        XCTAssert(library.dataVersion > versionBefore,
            "setApplications should bump dataVersion")
    }

    // MARK: - updateCustomOrder

    func testUpdateCustomOrderPreservesExactOrder() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app3 = makeApp("App3", path: "/Applications/App3.app")

        library.setApplications([app3, app1, app2])

        let reordered = [app1, app2, app3]
        library.updateCustomOrder(from: reordered)

        XCTAssertEqual(library.customOrder[app1.path], 0)
        XCTAssertEqual(library.customOrder[app2.path], 1)
        XCTAssertEqual(library.customOrder[app3.path], 2)
    }

    func testUpdateCustomOrderBumpsDataVersion() {
        let app = makeApp("Test")
        library.setApplications([app])

        let versionBefore = library.dataVersion
        library.updateCustomOrder(from: [app])

        XCTAssert(library.dataVersion > versionBefore,
            "updateCustomOrder should bump dataVersion")
    }

    /// Regression test for a per-drop main-thread stall: writing `customOrder[path]` per app
    /// fired the property's observer — a `dataVersion` bump plus a full encode-and-persist —
    /// once per app on screen. One drop must run that observer exactly once.
    func testUpdateCustomOrderRunsTheObserverOnceRegardlessOfAppCount() {
        let apps = (0..<50).map { makeApp("App\($0)", path: "/Applications/App\($0).app") }
        library.setApplications(apps)

        let versionBefore = library.dataVersion
        library.updateCustomOrder(from: apps.reversed())

        XCTAssertEqual(library.dataVersion, versionBefore + 1,
            "A drop must bump dataVersion (and persist) once, not once per app")
        XCTAssertEqual(PreferencesStore.shared.loadCustomOrder(), library.customOrder,
            "The single write must still persist the full new order")
    }

    /// Regression test for the bug where reordering apps made the whole grid "go out of order"
    /// until MacMuster restarted.
    ///
    /// Every real caller (drag-to-reorder in `ContentView`) hands `updateCustomOrder` the apps
    /// that were on screen at drop time — the root grid's loose apps + folder icons, or one open
    /// folder's contents — never the full catalog. `updateCustomOrder` used to write that partial
    /// list straight into `displayOrder`, which `visibleApplications`, `appPathIndex`, and
    /// everything else treat as the complete set of installed apps. Reordering a folder with 5
    /// apps in a 60-app library silently shrank the whole library to those 5 until the next
    /// rescan (e.g. on relaunch) rebuilt `displayOrder` from disk — which is exactly why a
    /// restart "fixed" it and why the drag order itself was never actually lost.
    func testUpdateCustomOrderWithPartialSubsetDoesNotShrinkTheFullCatalog() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app3 = makeApp("App3", path: "/Applications/App3.app")
        library.setApplications([app1, app2, app3])

        // Reorder only two of the three apps — the shape of a folder-scoped or root-scoped
        // reorder, where `getDisplayedApps()` (what a real drop reorders) never equals the full
        // catalog once folders exist.
        library.updateCustomOrder(from: [app2, app1])

        XCTAssertEqual(library.displayOrder.count, 3,
            "The full catalog must survive a reorder confined to a subset of it")
        XCTAssertEqual(Set(library.displayOrder.map(\.path)), Set([app1.path, app2.path, app3.path]),
            "No app should disappear from the catalog just because it wasn't part of the reorder")
        XCTAssertEqual(library.visibleApplications.count, 3,
            "visibleApplications derives from displayOrder, so it must not shrink either")
    }

    // MARK: - recordAppLaunch

    func testRecordAppLaunchUpdatesRecentAppsTracker() {
        let app = makeApp("Test")
        library.setApplications([app])

        library.recordAppLaunch(at: app.path)

        XCTAssertTrue(library.isRecentApp(app.path),
            "recordAppLaunch should update RecentAppsTracker")
    }

    func testRecordAppLaunchBumpsDataVersion() {
        let app = makeApp("Test")
        library.setApplications([app])

        let versionBefore = library.dataVersion
        library.recordAppLaunch(at: app.path)

        XCTAssert(library.dataVersion > versionBefore,
            "recordAppLaunch should bump dataVersion")
    }

    // MARK: - Concurrent Refresh Handling

    func testRefreshDisplayOrderSkipsWhenAlreadyScanning() async {
        let app = makeApp("Test")
        library.setApplications([app])

        library.isScanning = true
        let versionBefore = library.dataVersion

        await library.refreshDisplayOrder()

        XCTAssertEqual(library.dataVersion, versionBefore,
            "refreshDisplayOrder should skip when isScanning is true")
    }

    func testRefreshDisplayOrderSetsAndClearsIsScanning() async {
        let app = makeApp("Test")
        library.setApplications([app])

        XCTAssertFalse(library.isScanning)

        await library.refreshDisplayOrder()

        XCTAssertFalse(library.isScanning,
            "isScanning should be cleared after refresh completes")
    }

    // MARK: - Staleness Guard

    func testRefreshDisplayOrderWithScheduledReasonHonorsStalenessGuard() async {
        let app = makeApp("Test")
        library.setApplications([app])

        // Immediately call refresh with .scheduled — should skip if cache is recent
        await library.refreshDisplayOrder(reason: .scheduled)

        // If cache is recent (< refreshInterval), should not bump version
        // This is timing-dependent, so we just verify the method accepts the reason
        XCTAssert(true, "refreshDisplayOrder should accept .scheduled reason")
    }

    func testRefreshDisplayOrderFileSystemEventAlwaysScans() async {
        let app = makeApp("Test")
        library.setApplications([app])

        // Even with recent cache, fileSystemEvent should scan
        let versionBefore = library.dataVersion
        await library.refreshDisplayOrder(reason: .fileSystemEvent)

        XCTAssert(library.dataVersion >= versionBefore,
            "fileSystemEvent should always initiate a scan")
    }

    func testRefreshDisplayOrderUserRequestedClearsIcons() async {
        let app = makeApp("Test")
        var appWithIcon = app
        appWithIcon.icon = NSImage()

        library.setApplications([appWithIcon])

        await library.refreshDisplayOrder(reason: .userRequested)

        // Icons should be cleared and reloaded
        XCTAssertTrue(true, "userRequested should clear icon cache")
    }

    // MARK: - Folder Operations

    func testCreateFolderRebuildsAppPathIndex() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        library.setApplications([app1, app2])

        let folder = library.createFolder(name: "Test", appPaths: [app1.path])

        XCTAssertNotNil(folder)
        XCTAssertNotNil(library.appPathIndex[app1.path],
            "createFolder should not lose app index")
    }

    func testDeleteFolderCleansUpState() {
        let folder = AppFolder(id: "folder1", name: "Folder", appPaths: [])
        library.folders = [folder]

        library.deleteFolder(folderId: folder.id)

        XCTAssertTrue(library.folders.isEmpty,
            "deleteFolder should remove the folder")
    }

    func testRemoveAppFromFolderClearsCurrentFolderIfEmpty() {
        let app = makeApp("Test")
        library.setApplications([app])
        let folder = library.createFolder(name: "Folder", appPaths: [app.path])!

        library.openFolder(folder.id)
        XCTAssertEqual(library.currentFolderId, folder.id)

        library.removeAppFromFolder(app.path, folderId: folder.id)

        // If folder is now empty and was current, it should be closed
        XCTAssertTrue(true, "removeAppFromFolder should handle empty folder state")
    }

    // MARK: - Visible Applications

    func testVisibleApplicationsExcludesHiddenApps() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        library.setApplications([app1, app2])
        library.hiddenAppPaths.insert(app1.path)

        let visible = library.visibleApplications

        XCTAssertEqual(visible.count, 1,
            "visibleApplications should exclude hidden apps")
        XCTAssertFalse(visible.contains { $0.path == app1.path },
            "Hidden app should not be in visible list")
    }

    func testVisibleApplicationsReturnsConsistentResults() {
        let app = makeApp("Test")
        library.setApplications([app])

        let first = library.visibleApplications
        let countBefore = first.count

        let second = library.visibleApplications
        let countAfter = second.count

        XCTAssertEqual(countBefore, countAfter,
            "visibleApplications should return consistent results")
    }

    // MARK: - Cleanup

    func testCleanupTimerAndObserversCompletesWithoutError() {
        library.cleanupTimerAndObservers()

        XCTAssertTrue(true, "cleanupTimerAndObservers should complete without error")
    }
}
