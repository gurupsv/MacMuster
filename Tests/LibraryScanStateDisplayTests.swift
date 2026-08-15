import XCTest
@testable import MacMuster

/// Tests category filtering, search filtering, display ordering, and the integrated display pipeline.
@MainActor
final class LibraryScanStateDisplayTests: XCTestCase {

    private var library: LibraryScanState!
    private var navigation: NavigationSelection!
    private var settings: SettingsAppearance!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()

        library = LibraryScanState()
        navigation = NavigationSelection()
        settings = SettingsAppearance()

        // Wire together the three observable objects
        library.settings = settings
        library.navigation = navigation
        navigation.library = library
        navigation.settings = settings

        library.isLoading = false
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        library.cleanupTimerAndObservers()
        library = nil
        navigation = nil
        settings = nil
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

    // MARK: - Category Filtering

    func testGetCategoryForSystemApp() {
        let app = makeApp("System", path: "/System/Applications/Test.app")
        XCTAssertEqual(library.getCategory(for: app), .system,
            "Apps in /System should be categorized as .system")
    }

    func testGetCategoryForUserApp() {
        let app = makeApp("User", path: "/Applications/Test.app")
        XCTAssertEqual(library.getCategory(for: app), .user,
            "Apps in /Applications should be categorized as .user")
    }

    func testMatchesCategoryAll() {
        let app = makeApp("Test")
        XCTAssertTrue(library.matchesSelectedCategory(app, selectedCategory: .all),
            ".all category should match any app")
    }

    func testMatchesCategorySystem() {
        let systemApp = makeApp("System", path: "/System/Applications/Test.app")
        let userApp = makeApp("User", path: "/Applications/Test.app")

        XCTAssertTrue(library.matchesSelectedCategory(systemApp, selectedCategory: .system),
            ".system should match /System apps")
        XCTAssertFalse(library.matchesSelectedCategory(userApp, selectedCategory: .system),
            ".system should not match /Applications apps")
    }

    func testMatchesCategoryUser() {
        let systemApp = makeApp("System", path: "/System/Applications/Test.app")
        let userApp = makeApp("User", path: "/Applications/Test.app")

        XCTAssertFalse(library.matchesSelectedCategory(systemApp, selectedCategory: .user),
            ".user should not match /System apps")
        XCTAssertTrue(library.matchesSelectedCategory(userApp, selectedCategory: .user),
            ".user should match /Applications apps")
    }

    func testMatchesCategoryMostUsed() {
        let app = makeApp("Test")
        library.setApplications([app])
        library.recordAppLaunch(at: app.path)

        XCTAssertTrue(library.matchesSelectedCategory(app, selectedCategory: .mostUsed),
            ".mostUsed should match apps in _mostUsedApps")
    }

    func testMatchesCategoryRecentlyLaunched() {
        let app = makeApp("Test")
        library.setApplications([app])
        library.recordAppLaunch(at: app.path)

        XCTAssertTrue(library.matchesSelectedCategory(app, selectedCategory: .recentlyLaunched),
            ".recentlyLaunched should match apps in _recentApps")
    }

    func testMatchesCategoryNewlyInstalled() {
        let recentDate = Date()
        let app = Application(id: "/Applications/New.app", name: "New", path: "/Applications/New.app",
                             icon: nil, installationDate: recentDate, isFolder: false,
                             containedApps: nil, bundleDescription: nil)

        XCTAssertTrue(library.matchesSelectedCategory(app, selectedCategory: .newlyInstalled),
            ".newlyInstalled should match recently-installed apps")
    }

    func testIsNewlyInstalledUsesScanMetricsWindow() {
        let oldDate = Date().addingTimeInterval(-(ScanMetrics.newlyInstalledWindowSeconds + 1))
        let app = Application(id: "/Applications/Old.app", name: "Old", path: "/Applications/Old.app",
                             icon: nil, installationDate: oldDate, isFolder: false,
                             containedApps: nil, bundleDescription: nil)

        XCTAssertFalse(library.isNewlyInstalled(app),
            "Apps older than newlyInstalledWindow should not be newly installed")
    }

    // MARK: - Category Counts

    func testUpdateFilteredAppsComputesCounts() {
        let userApp = makeApp("User", path: "/Applications/User.app")
        let systemApp = makeApp("System", path: "/System/Applications/System.app")
        library.setApplications([userApp, systemApp])

        library.updateFilteredApps()

        XCTAssert((library.navigation?.categoryCounts[.user] ?? 0) > 0,
            ".user count should reflect visible user apps")
        XCTAssert((library.navigation?.categoryCounts[.system] ?? 0) > 0,
            ".system count should reflect visible system apps")
    }

    func testUpdateFilteredAppsAllCountEqualsTotal() {
        let apps = (0..<5).map { makeApp("App\($0)") }
        library.setApplications(apps)

        library.updateFilteredApps()

        XCTAssertEqual(library.navigation?.categoryCounts[.all], 5,
            ".all count should equal total filtered count")
    }

    func testUpdateFilteredAppsUtilitiesCountAlwaysZero() {
        let apps = (0..<5).map { makeApp("App\($0)") }
        library.setApplications(apps)

        library.updateFilteredApps()

        XCTAssertEqual(library.navigation?.categoryCounts[.utilities], 0,
            ".utilities count should always be 0")
    }

    func testUpdateFilteredAppsExcludesHiddenApps() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        library.setApplications([app1, app2])
        library.hiddenAppPaths.insert(app1.path)

        library.updateFilteredApps()

        XCTAssertEqual(library.navigation?.categoryCounts[.all], 1,
            "Hidden apps should not be counted in .all")
    }

    func testUpdateFilteredAppsIncludesSearchResults() {
        let userApp = makeApp("UserApp", path: "/Applications/UserApp.app")
        library.setApplications([userApp])
        library.navigation?.searchTerm = "User"

        library.updateFilteredApps()

        XCTAssertEqual(library.navigation?.categoryCounts[.all], 1,
            "Search-matched apps should be counted")
    }

    // MARK: - Search Filtering & Ranking

    func testGetDisplayedAppsWithEmptySearchReturnsAllVisible() {
        let apps = (0..<3).map { makeApp("App\($0)") }
        library.setApplications(apps)

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 3,
            "Empty search should return all visible apps")
    }

    func testGetDisplayedAppsSearchFiltersApps() {
        let app1 = makeApp("Calculator", path: "/Applications/Calculator.app")
        let app2 = makeApp("Safari", path: "/Applications/Safari.app")
        library.setApplications([app1, app2])

        let displayed = library.getDisplayedApps(
            searchTerm: "Calc", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 1,
            "Search for 'Calc' should match only Calculator")
        XCTAssertEqual(displayed[0].name, "Calculator")
    }

    func testGetDisplayedAppsSearchIsCaseInsensitive() {
        let app = makeApp("Calculator", path: "/Applications/Calculator.app")
        library.setApplications([app])

        let lowercase = library.getDisplayedApps(
            searchTerm: "calc", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)
        let uppercase = library.getDisplayedApps(
            searchTerm: "CALC", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(lowercase.count, 1)
        XCTAssertEqual(uppercase.count, 1)
    }

    func testGetDisplayedAppsRanksExactMatchFirst() {
        let exact = makeApp("Safari", path: "/Applications/Safari.app")
        let substring = makeApp("Safari Bookmarks Extension", path: "/Applications/SafariBookmarks.app")
        library.setApplications([substring, exact])

        let displayed = library.getDisplayedApps(
            searchTerm: "Safari", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 2)
        XCTAssertEqual(displayed[0].name, "Safari",
            "Exact match should rank higher than substring match")
    }

    func testGetDisplayedAppsRanksPrefixHigherThanSubstring() {
        let prefix = makeApp("Calculator", path: "/Applications/Calculator.app")
        let substring = makeApp("Windows Calculator Emulator", path: "/Applications/WinCalc.app")
        library.setApplications([substring, prefix])

        let displayed = library.getDisplayedApps(
            searchTerm: "Calc", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 2)
        XCTAssertEqual(displayed[0].name, "Calculator",
            "Prefix match should rank higher than substring match")
    }

    // MARK: - Display Ordering

    func testGetDisplayedAppsSearchesByName() {
        let app1 = makeApp("Zebra", path: "/Applications/Zebra.app")
        let app2 = makeApp("Apple", path: "/Applications/Apple.app")
        library.setApplications([app1, app2])

        let displayed = library.getDisplayedApps(
            searchTerm: "zebr", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        // "zebr" only matches Zebra (as a substring in name)
        XCTAssert(displayed.contains { $0.name == "Zebra" },
            "Search for 'zebr' should include Zebra")
        XCTAssertFalse(displayed.contains { $0.name == "Apple" },
            "Search for 'zebr' should not include Apple")
    }

    func testGetDisplayedAppsShowFolderFirstPlacesFoldersFirst() {
        let folder = Application(id: "/Applications/Folder", name: "Folder", path: "/Applications/Folder",
                                icon: nil, installationDate: Date(), isFolder: true,
                                containedApps: ["app1"], bundleDescription: nil)
        let app = makeApp("App")
        library.folders = [AppFolder(id: "folder1", name: "Folder", appPaths: [])]
        library.setApplications([app, folder])

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: true, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssert(displayed.count > 0)
        if displayed.count >= 2 {
            XCTAssertTrue(displayed[0].isFolder,
                "showFoldersFirst should place folders first")
        }
    }

    func testGetDisplayedAppsCustomOrderOverridesSort() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app3 = makeApp("App3", path: "/Applications/App3.app")
        library.setApplications([app1, app2, app3])

        // Set custom order via updateCustomOrder which also updates displayOrder
        let reordered = [app3, app1, app2]
        library.updateCustomOrder(from: reordered)

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: library.customOrder,
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 3)
        XCTAssertEqual(displayed[0].name, "App3")
        XCTAssertEqual(displayed[1].name, "App1")
        XCTAssertEqual(displayed[2].name, "App2")
    }

    func testGetDisplayedAppsRecentlyLaunchedSortsByTimestamp() async {
        let app1 = makeApp("Old", path: "/Applications/Old.app")
        let app2 = makeApp("New", path: "/Applications/New.app")
        library.setApplications([app1, app2])

        library.recordAppLaunch(at: app1.path)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        library.recordAppLaunch(at: app2.path)

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .recentlyLaunched, columnCount: 4)

        XCTAssertEqual(displayed.count, 2)
        if displayed.count >= 2 {
            XCTAssertEqual(displayed[0].name, "New",
                "Recently launched should sort by timestamp, most recent first")
        }
    }

    func testGetDisplayedAppsMostUsedSortsByCount() {
        let app1 = makeApp("LittleUsed", path: "/Applications/LittleUsed.app")
        let app2 = makeApp("MostUsed", path: "/Applications/MostUsed.app")
        library.setApplications([app1, app2])

        library.recordAppLaunch(at: app1.path)
        library.recordAppLaunch(at: app2.path)
        library.recordAppLaunch(at: app2.path)
        library.recordAppLaunch(at: app2.path)

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .mostUsed, columnCount: 4)

        XCTAssertEqual(displayed.count, 2)
        if displayed.count >= 1 {
            XCTAssertEqual(displayed[0].name, "MostUsed",
                "Most used should sort by launch count, highest first")
        }
    }

    // MARK: - Cache Validation

    func testGetDisplayedAppsCacheHitOnIdenticalQuery() {
        let app = makeApp("Test")
        library.setApplications([app])

        let first = library.getDisplayedApps(
            searchTerm: "test", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        let cachedQuery = library.cachedDisplayedApps?.query
        XCTAssertNotNil(cachedQuery,
            "First query should populate the cache")

        let second = library.getDisplayedApps(
            searchTerm: "test", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(first.count, second.count)
        let cachedQueryAfter = library.cachedDisplayedApps?.query
        XCTAssertEqual(cachedQuery, cachedQueryAfter,
            "Identical queries should use the same cached query")
    }

    func testGetDisplayedAppsCacheMissOnDifferentSearchTerm() {
        let app = makeApp("Test")
        library.setApplications([app])

        let first = library.getDisplayedApps(
            searchTerm: "test", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        let second = library.getDisplayedApps(
            searchTerm: "other", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertNotEqual(first.count, second.count,
            "Different search terms should produce different results")
    }

    func testGetDisplayedAppsCacheInvalidatedByDataVersionChange() {
        let app = makeApp("Test")
        library.setApplications([app])

        _ = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        let versionBefore = library.cachedDisplayedApps?.query.version
        library.dataVersion += 1

        _ = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        let versionAfter = library.cachedDisplayedApps?.query.version
        XCTAssertNotEqual(versionBefore, versionAfter,
            "Cache should be rebuilt when dataVersion changes")
    }

    // MARK: - Empty/Edge Cases

    func testGetDisplayedAppsWithNoCategoryMatchesReturnsEmpty() {
        let app = makeApp("Test", path: "/Applications/Test.app")
        library.setApplications([app])

        let displayed = library.getDisplayedApps(
            searchTerm: "", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .system, columnCount: 4)

        XCTAssertEqual(displayed.count, 0,
            "Category filter with no matches should return empty")
    }

    func testGetDisplayedAppsWithNoSearchMatchesReturnsEmpty() {
        let app = makeApp("Calculator", path: "/Applications/Calculator.app")
        library.setApplications([app])

        let displayed = library.getDisplayedApps(
            searchTerm: "NotFound", showFoldersFirst: false, customOrder: [:],
            sortOption: .name, selectedCategory: .all, columnCount: 4)

        XCTAssertEqual(displayed.count, 0,
            "Search with no matches should return empty")
    }
}
