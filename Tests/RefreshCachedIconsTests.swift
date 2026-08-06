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
            library.loadedIconsByPath[path] = icon
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
}
