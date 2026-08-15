import XCTest
@testable import MacMuster

/// Tests keyboard navigation, search debouncing, and selection state management.
@MainActor
final class NavigationSelectionTests: XCTestCase {

    private var navigation: NavigationSelection!
    private var library: LibraryScanState!
    private var settings: SettingsAppearance!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        library = LibraryScanState()
        settings = SettingsAppearance()
        navigation = NavigationSelection()
        navigation.library = library
        navigation.settings = settings
        library.settings = settings
        library.navigation = navigation
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        library.cleanupTimerAndObservers()
        library = nil
        settings = nil
        navigation = nil
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

    // MARK: - Navigation with Empty Apps

    func testSelectAppUpWithEmptyAppsIsNoop() {
        navigation.selectedAppIndex = 5
        navigation.selectAppUp()
        XCTAssertEqual(navigation.selectedAppIndex, 5,
            "selectAppUp with no apps should leave selection unchanged")
    }

    func testSelectAppDownWithEmptyAppsIsNoop() {
        navigation.selectedAppIndex = 5
        navigation.selectAppDown()
        XCTAssertEqual(navigation.selectedAppIndex, 5,
            "selectAppDown with no apps should leave selection unchanged")
    }

    func testSelectAppLeftWithEmptyAppsIsNoop() {
        navigation.selectedAppIndex = 5
        navigation.selectAppLeft()
        XCTAssertEqual(navigation.selectedAppIndex, 5,
            "selectAppLeft with no apps should leave selection unchanged")
    }

    func testSelectAppRightWithEmptyAppsIsNoop() {
        navigation.selectedAppIndex = 5
        navigation.selectAppRight()
        XCTAssertEqual(navigation.selectedAppIndex, 5,
            "selectAppRight with no apps should leave selection unchanged")
    }

    // MARK: - Navigation with Single App

    func testSelectAppUpWithSingleAppSelectsIt() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        library.setApplications([app])
        settings.columnCount = 4

        navigation.selectedAppIndex = -1
        navigation.selectAppUp()
        XCTAssertEqual(navigation.selectedAppIndex, 0,
            "selectAppUp with no selection should select the first (only) app")
    }

    func testSelectAppDownWithSingleAppSelectsIt() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        library.setApplications([app])
        settings.columnCount = 4

        navigation.selectedAppIndex = -1
        navigation.selectAppDown()
        XCTAssertEqual(navigation.selectedAppIndex, 0,
            "selectAppDown with no selection should select the first (only) app")
    }

    // MARK: - Navigation with Partial Final Row

    func testSelectAppUpWithPartialFinalRowWrapsCorrectly() {
        let apps = (0..<9).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)
        settings.columnCount = 4

        // Index 5 is row 1, col 1. Up should go to row 0, col 1 = index 1.
        navigation.selectedAppIndex = 5
        navigation.selectAppUp()
        XCTAssertEqual(navigation.selectedAppIndex, 1,
            "selectAppUp in partial row should move up a row")
    }

    func testSelectAppUpFromTopRowWrapsToBottomPartialRow() {
        let apps = (0..<9).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)
        settings.columnCount = 4

        // 9 apps with 4 columns = 3 rows (0-3, 4-7, 8). Index 1 is row 0, col 1.
        // Up should wrap to the last row (8), but clamp to actual max (8).
        navigation.selectedAppIndex = 1
        navigation.selectAppUp()
        XCTAssertEqual(navigation.selectedAppIndex, 8,
            "selectAppUp from top row should wrap to last row, clamped to max index")
    }

    // MARK: - Search Debouncing

    func testSearchTermChangeBumpsDataVersion() async {
        library.isLoading = false
        let versionBefore = library.dataVersion
        navigation.searchTerm = "test"
        try? await Task.sleep(nanoseconds: 200_000_000) // Wait for debounce
        XCTAssert(library.dataVersion > versionBefore,
            "Setting search term should bump dataVersion after debounce")
    }

    func testClearingSearchTermBumpsDataVersionImmediately() {
        library.isLoading = false
        navigation.searchTerm = "test"
        let versionWithSearch = library.dataVersion
        navigation.searchTerm = ""
        XCTAssert(library.dataVersion > versionWithSearch,
            "Clearing search should bump dataVersion immediately")
    }

    func testRapidSuccessiveSearchTermsDebounce() async {
        library.isLoading = false
        let versionBefore = library.dataVersion

        // Set search term, then immediately change it several times.
        navigation.searchTerm = "a"
        navigation.searchTerm = "ab"
        navigation.searchTerm = "abc"

        // Only the immediate clear bumps (empty string). Non-empty debounces.
        let versionAfterRapidChanges = library.dataVersion

        // Wait for the debounce to complete (150ms).
        try? await Task.sleep(nanoseconds: 200_000_000)

        let versionAfterDebounce = library.dataVersion
        XCTAssert(versionAfterDebounce > versionAfterRapidChanges,
            "Debounced search should eventually bump dataVersion")
    }

    func testSearchTermChangeInvalidatesCachedDisplayedApps() async {
        library.isLoading = false
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        library.setApplications([app])

        // Prime the cache with empty search term.
        _ = library.getDisplayedApps(searchTerm: "", showFoldersFirst: false,
                                    customOrder: [:], sortOption: .name,
                                    selectedCategory: .all, columnCount: 4)

        let oldVersion = library.dataVersion
        navigation.searchTerm = "T"
        try? await Task.sleep(nanoseconds: 250_000_000) // Wait for debounce (150ms + margin)

        // dataVersion should have bumped, making the old cache key invalid.
        XCTAssert(library.dataVersion > oldVersion,
            "Changing search term should bump dataVersion")
    }

    // MARK: - Selected App Index Reset

    func testSelectedAppIndexResetWhenSelectedCategoryChanges() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        library.setApplications([app])

        navigation.selectedAppIndex = 0
        navigation.selectedCategory = .system
        XCTAssertEqual(navigation.selectedAppIndex, -1,
            "Changing category should reset selected app index")
    }

    // MARK: - Launch Selected App

    func testLaunchSelectedAppWithNoSelectionReturnsFalse() {
        navigation.selectedAppIndex = -1
        let result = navigation.launchSelectedApp()
        XCTAssertFalse(result,
            "launchSelectedApp with no selection should return false")
    }

    func testLaunchSelectedAppReturnsTrue() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        library.setApplications([app])

        navigation.selectedAppIndex = 0
        let result = navigation.launchSelectedApp()

        XCTAssertTrue(result,
            "launchSelectedApp should return true for valid selection")
    }

    // MARK: - Clear Search State

    func testClearSearchStateResetsSearchAndIndex() {
        navigation.searchTerm = "query"
        navigation.selectedAppIndex = 5

        navigation.clearSearchState()

        XCTAssertEqual(navigation.searchTerm, "",
            "clearSearchState should clear search term")
        XCTAssertEqual(navigation.selectedAppIndex, -1,
            "clearSearchState should reset selected index")
    }

    // MARK: - Scroll Target Management

    func testClearScrollTargetNilsBothFields() {
        navigation.scrollTargetIndex = 5
        navigation.scrollTargetAnchor = .center

        navigation.clearScrollTarget()

        XCTAssertNil(navigation.scrollTargetIndex,
            "clearScrollTarget should nil scrollTargetIndex")
        XCTAssertNil(navigation.scrollTargetAnchor,
            "clearScrollTarget should nil scrollTargetAnchor")
    }

    func testSelectAppUpSetsScrollAnchor() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)
        settings.columnCount = 4

        // From middle of grid, should have center anchor.
        navigation.selectedAppIndex = 8
        navigation.selectAppUp()
        XCTAssertEqual(navigation.scrollTargetAnchor, .center,
            "selectAppUp from middle row should use center anchor")

        // From top row up, should use bottom anchor.
        navigation.selectedAppIndex = 1
        navigation.selectAppUp()
        XCTAssertEqual(navigation.scrollTargetAnchor, .bottom,
            "selectAppUp wrapping to bottom should use bottom anchor")
    }

    func testSelectAppDownSetsScrollAnchor() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)
        settings.columnCount = 4

        // From middle of grid, should have center anchor.
        navigation.selectedAppIndex = 5
        navigation.selectAppDown()
        XCTAssertEqual(navigation.scrollTargetAnchor, .center,
            "selectAppDown from middle row should use center anchor")

        // From bottom row down, should use top anchor.
        navigation.selectedAppIndex = 12
        navigation.selectAppDown()
        XCTAssertEqual(navigation.scrollTargetAnchor, .top,
            "selectAppDown wrapping to top should use top anchor")
    }

    // MARK: - First/Last App Selection

    func testSelectFirstAppMovesToIndex0() {
        let apps = (0..<5).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)

        navigation.selectedAppIndex = 3
        navigation.selectFirstApp()

        XCTAssertEqual(navigation.selectedAppIndex, 0,
            "selectFirstApp should move to index 0")
    }

    func testSelectLastAppMovesToLastIndex() {
        let apps = (0..<5).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)

        navigation.selectedAppIndex = 0
        navigation.selectLastApp()

        XCTAssertEqual(navigation.selectedAppIndex, 4,
            "selectLastApp should move to last app index")
    }

    // MARK: - Next/Previous Navigation

    func testSelectNextAppMovesForward() {
        let apps = (0..<3).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)

        navigation.selectedAppIndex = 1
        navigation.selectNextApp()

        XCTAssertEqual(navigation.selectedAppIndex, 2,
            "selectNextApp should move forward one app")
    }

    func testSelectPreviousAppMovesBackward() {
        let apps = (0..<3).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)

        navigation.selectedAppIndex = 1
        navigation.selectPreviousApp()

        XCTAssertEqual(navigation.selectedAppIndex, 0,
            "selectPreviousApp should move backward one app")
    }

    // MARK: - Direct Selection

    func testSelectAppAtIndexSetsIndex() {
        let apps = (0..<3).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app",
                       icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        library.setApplications(apps)

        navigation.selectApp(at: 2)

        XCTAssertEqual(navigation.selectedAppIndex, 2,
            "selectApp(at:) should set the exact index")
    }
}
