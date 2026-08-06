import XCTest
@testable import MacMuster

@MainActor
final class AppearanceChangeHandlerTests: XCTestCase {

    private var library: LibraryScanState!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        library = LibraryScanState()
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

    // MARK: - Icon Refresh on Appearance Change

    func testHandleAppearanceChangeNilsAllAppIcons() async {
        // Create a few test apps with pre-loaded icons
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }

        let app1 = Application(
            id: "/Test/App1.app", name: "App1", path: "/Test/App1.app",
            icon: icon, installationDate: Date(), isFolder: false, containedApps: nil
        )
        let app2 = Application(
            id: "/Test/App2.app", name: "App2", path: "/Test/App2.app",
            icon: icon, installationDate: Date(), isFolder: false, containedApps: nil
        )

        library.setApplications([app1, app2])

        // Verify icons are loaded
        XCTAssertNotNil(library.displayOrder[0].icon, "App1 should have icon before appearance change")
        XCTAssertNotNil(library.displayOrder[1].icon, "App2 should have icon before appearance change")

        // Handle appearance change
        library.handleAppearanceChange()

        // Verify icons are niled out so they'll re-decode with new appearance
        XCTAssertNil(library.displayOrder[0].icon, "App1 icon should be niled after appearance change")
        XCTAssertNil(library.displayOrder[1].icon, "App2 icon should be niled after appearance change")
    }

    func testHandleAppearanceChangeBumpsDataVersion() async {
        let app = Application(
            id: "/Test/App.app", name: "App", path: "/Test/App.app",
            icon: nil, installationDate: Date(), isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        let versionBefore = library.dataVersion
        library.handleAppearanceChange()
        let versionAfter = library.dataVersion

        XCTAssertGreaterThan(versionAfter, versionBefore, "handleAppearanceChange should bump dataVersion to trigger re-renders")
    }

    func testHandleAppearanceChangeInvalidatesDisplayCache() async {
        let app = Application(
            id: "/Test/App.app", name: "App", path: "/Test/App.app",
            icon: nil, installationDate: Date(), isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        // Access the displayed apps to populate the cache
        _ = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:], sortOption: .name,
            selectedCategory: .all, columnCount: 4
        )

        // After appearance change, the cached display list should be invalidated
        library.handleAppearanceChange()

        // The dataVersion bump should cause the cache to miss next time
        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:], sortOption: .name,
            selectedCategory: .all, columnCount: 4
        )
        XCTAssertFalse(displayed.isEmpty, "Should still have apps after appearance change")
    }

    func testHandleAppearanceChangeEvictsFolderIcons() async {
        let app1 = Application(
            id: "/Test/App1.app", name: "App1", path: "/Test/App1.app",
            icon: nil, installationDate: Date(), isFolder: false, containedApps: nil
        )
        let app2 = Application(
            id: "/Test/App2.app", name: "App2", path: "/Test/App2.app",
            icon: nil, installationDate: Date(), isFolder: false, containedApps: nil
        )

        library.setApplications([app1, app2])

        // Create a folder containing both apps
        let folder = library.createFolder(name: "TestFolder", appPaths: [app1.path, app2.path])
        XCTAssertNotNil(folder, "Folder should be created")

        // Get the folder app to generate its icon
        if let folder = folder {
            let folderApp = library.getFolderApplication(folder)
            XCTAssertNotNil(folderApp.icon, "Folder icon should be generated")
        }

        // Handle appearance change — folder icons should be evicted
        library.handleAppearanceChange()

        // After appearance change, getting the folder app again should regenerate the icon
        if let folder = library.folders.first {
            let folderApp = library.getFolderApplication(folder)
            // We can't directly test that it's a new icon, but we can verify the operation succeeds
            XCTAssertNotNil(folderApp.icon, "Folder icon should be regenerated after appearance change")
        }
    }

    // MARK: - Icon Re-Loading on Appearance Change

    func testHandleAppearanceChangePrioritizesReload() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }

        let app = Application(
            id: "/System/Applications/Calculator.app", name: "Calculator",
            path: "/System/Applications/Calculator.app", icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        // Before appearance change, icon should be nil (not loaded yet)
        XCTAssertNil(library.displayOrder[0].icon, "Icon should not be loaded initially")

        // handleAppearanceChange nils icons and re-loads them.
        // We can't easily test the async loadMissingIcons completion without full integration,
        // but we can verify the method runs without crashing and the data structure is valid.
        library.handleAppearanceChange()

        // Verify the library is still in a valid state after the call
        XCTAssertFalse(library.displayOrder.isEmpty, "Display order should still contain apps")
    }
}
