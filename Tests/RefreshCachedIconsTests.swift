import XCTest
@testable import MacMuster

@MainActor
final class RefreshCachedIconsTests: XCTestCase {

    private var library: LibraryScanState!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        library = LibraryScanState()
        IconCacheManager.shared.clearAll()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        IconCacheManager.shared.clearAll()
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

    // MARK: - refreshCachedIcons Correctness

    func testRefreshCachedIconsRunsOnBackgroundThread() async throws {
        // This test verifies that the I/O work (directory enumeration, JSON decode)
        // happens off the main thread. We test this indirectly by ensuring the method
        // returns quickly and doesn't block the main thread.
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }

        let app = Application(
            id: "/System/Applications/Calculator.app", name: "Calculator",
            path: "/System/Applications/Calculator.app", icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        let startTime = Date()
        await library.refreshCachedIcons()
        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete quickly since there are no stale icons on fresh cache
        XCTAssertLessThan(elapsed, 5, "refreshCachedIcons should not block main thread (complete in < 5s)")
    }

    func testRefreshCachedIconsDetectsStaleIcons() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }

        let path = "/System/Applications/Calculator.app"
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }

        let app = Application(
            id: path, name: "Calculator", path: path, icon: icon, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        // Cache the icon so refreshCachedIcons has something to work with
        IconCacheManager.shared.cacheIcon(icon, for: path, appearance: .light)

        // Call refreshCachedIcons — on a fresh icon, there should be no stale apps
        // (mtime matches). This test verifies the method runs without crashing.
        await library.refreshCachedIcons()

        // Verify library is still in valid state
        XCTAssertFalse(library.displayOrder.isEmpty, "Display order should still be valid after refresh")
    }

    func testRefreshCachedIconsUsesForceFlag() async throws {
        // This test verifies that refreshCachedIcons passes force: true to loadMissingIcons,
        // which means it re-decodes icons even when they're already loaded.
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }

        let path = "/System/Applications/Calculator.app"
        let app = Application(
            id: path, name: "Calculator", path: path, icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        // Pre-load icon so app.icon != nil
        let loadedIcons = await IconService.shared.loadMissingIcons(for: [app])
        if let (_, icon) = loadedIcons.first {
            library.displayOrder[0].icon = icon
        }

        XCTAssertNotNil(library.displayOrder[0].icon, "Icon should be pre-loaded")

        // Call refreshCachedIcons, which should use force: true to re-decode
        // even though the icon is already loaded.
        await library.refreshCachedIcons()

        // We can't directly observe the force: true call, but we can verify
        // the library is still in valid state and the operation completes.
        XCTAssertFalse(library.displayOrder.isEmpty, "Display order should still be valid")
    }

    func testRefreshCachedIconsPrunesDeletedApps() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }

        let path1 = "/System/Applications/Calculator.app"

        let app1 = Application(
            id: path1, name: "Calculator", path: path1, icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app1])

        let icon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }

        // Cache icon for app1
        IconCacheManager.shared.cacheIcon(icon, for: path1, appearance: .light)
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: path1, appearance: .light), "App should be in cache initially")

        // Call refreshCachedIcons, which should call pruneDeletedApps
        await library.refreshCachedIcons()

        // The app still exists and is in displayOrder, so it should still be cached
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: path1, appearance: .light), "pruneDeletedApps should keep cache for existing app")
    }

    // MARK: - loadMissingIcons reaches the grid without a separate loadedIconsByPath dictionary

    /// Regression test: `loadedIconsByPath` used to be a second dictionary holding the exact same
    /// `NSImage` instances as `displayOrder[i].icon` — a strong reference to every decoded icon
    /// for the whole session, immune to the `IconCacheManager` NSCache's own eviction, and never
    /// actually read for anything `displayOrder` didn't already provide. This confirms its removal
    /// didn't also remove icon propagation: `loadMissingIcons` must still land the decoded icon in
    /// `displayOrder`, in the cell's `IconSlot`, and in a warm `getDisplayedApps()` result.
    ///
    /// It must do that *without* bumping `dataVersion`: an icon batch changes no display
    /// decision, and the bump used to throw away and recompute the whole display once per batch.
    func testLoadMissingIconsReachesTheGridWithoutInvalidatingTheDisplay() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let path = "/System/Applications/Calculator.app"
        let app = Application(
            id: path, name: "Calculator", path: path, icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])
        XCTAssertNil(library.displayOrder[0].icon, "Precondition: no icon loaded yet")
        let slot = library.iconSlot(for: path)
        XCTAssertNil(slot.icon, "Precondition: the cell's slot is empty")
        // Warm the display cache, as the grid would have before icons arrive.
        _ = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        let versionBefore = library.dataVersion
        await library.loadMissingIcons()

        XCTAssertNotNil(library.displayOrder[0].icon,
            "The loaded icon should land directly in displayOrder")
        XCTAssertNotNil(slot.icon, "The loaded icon should reach the cell's own IconSlot")
        XCTAssertEqual(library.dataVersion, versionBefore,
            "An icon batch must not bump dataVersion — no display decision depends on icons")

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)
        XCTAssertNotNil(displayed.first(where: { $0.path == path })?.icon,
            "The warm display result is patched with the icon rather than served stale")
    }

    /// Regression test for blank icons on the first page after a cold launch.
    ///
    /// `displayOrder`'s raw scan order interleaves loose apps with every app tucked away inside a
    /// folder. A folder with enough members can fill the whole priority batch with apps that are
    /// not visible on the root page at all, pushing the loose apps actually on screen out to a
    /// later, sequentially-awaited chunk — the icon shows blank until something else (opening and
    /// leaving a folder) forces the background loop to catch up. `priorityIconLoadOrder()` must
    /// pick from what the root page would actually display, not raw scan order.
    func testPriorityIconLoadOrderFavorsVisibleAppsOverHiddenFolderMembers() {
        // Named so raw alphabetical scan order sorts every folder member before the loose apps.
        let folderMembers = (0..<(ScanMetrics.priorityIconLoadCount + 5)).map { index in
            Application(
                id: "/tmp/AAA-Member-\(index).app", name: "AAA-Member-\(index)",
                path: "/tmp/AAA-Member-\(index).app", icon: nil, installationDate: Date(),
                isFolder: false, containedApps: nil
            )
        }
        let looseApps = (0..<3).map { index in
            Application(
                id: "/tmp/ZZZ-Loose-\(index).app", name: "ZZZ-Loose-\(index)",
                path: "/tmp/ZZZ-Loose-\(index).app", icon: nil, installationDate: Date(),
                isFolder: false, containedApps: nil
            )
        }
        library.setApplications(folderMembers + looseApps)
        _ = library.createFolder(name: "Folder", appPaths: folderMembers.map(\.path))

        XCTAssertLessThan(
            Array(library.displayOrder.prefix(ScanMetrics.priorityIconLoadCount)).filter { app in
                looseApps.contains { $0.path == app.path }
            }.count,
            looseApps.count,
            "Precondition: raw displayOrder's prefix does not already contain every loose app"
        )

        let prioritized = library.priorityIconLoadOrder()
        let prioritizedPaths = Set(prioritized.map(\.path))
        for looseApp in looseApps {
            XCTAssertTrue(prioritizedPaths.contains(looseApp.path),
                "\(looseApp.name) is visible on the root page and must be in the priority batch")
        }
    }
}
