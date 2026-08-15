import XCTest
@testable import MacMuster

/// Category selection is a filter. It used to be applied inside the *ordering* function, behind
/// two early returns and a `switch` that covered only three of the six categories — so the tab
/// badge would read "Newly Installed 3" while the grid showed the entire library.
@MainActor
final class CategoryFilterTests: XCTestCase {

    private var library: LibraryScanState!
    private var navigation: NavigationSelection!
    private var settings: SettingsAppearance!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        // Same wiring AppModel performs — `updateFilteredApps` writes the tab counts through
        // `navigation`, so without it the counts assertion would pass vacuously.
        library = LibraryScanState()
        navigation = NavigationSelection()
        settings = SettingsAppearance()
        navigation.library = library
        navigation.settings = settings
        library.navigation = navigation
        library.settings = settings
        library.isLoading = false

        // `RecentAppsTracker` is a singleton whose `isEnabled` is in-memory state driven by
        // `SettingsAppearance.showRecentApps`, so it has to be set *after* the settings object
        // exists — constructing one reloads the stored preference and reasserts it. An earlier
        // test class leaving it off would otherwise make launches silently fail to record, and
        // the Most Used / Recently Launched cases here would pass for the wrong reason.
        RecentAppsTracker.shared.isEnabled = true
    }

    override func tearDown() async throws {
        library.cleanupTimerAndObservers()
        library = nil
        navigation = nil
        settings = nil
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
    }

    nonisolated func clearAllUserDefaultsState() {
        for key in ["appFolders", "hiddenAppPaths", "customDirectories", "customDirectoryBookmarks",
                    "currentFolderId", "customOrder", "sortOption", "showFoldersFirst",
                    "recentAppLaunchTimes", "appLaunchCounts", "showHiddenApps",
                    "recentAppsEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func app(_ name: String, path: String, installed: Date = Date()) -> Application {
        Application(id: path, name: name, path: path, icon: nil,
                    installationDate: installed, isFolder: false, containedApps: nil)
    }

    private let longAgo = Date(timeIntervalSinceNow: -365 * 24 * 60 * 60)

    /// System app, user app, an old user app, and a freshly installed user app.
    private func loadMixedLibrary() {
        library.setApplications([
            app("SystemOld", path: "/System/Applications/SystemOld.app", installed: longAgo),
            app("UserOld", path: "/Applications/UserOld.app", installed: longAgo),
            app("UserFresh", path: "/Applications/UserFresh.app", installed: Date()),
        ])
    }

    private func displayed(_ category: AppCategory, customOrder: [String: Int] = [:], showFoldersFirst: Bool = false) -> [String] {
        library.getDisplayedApps(searchTerm: "", showFoldersFirst: showFoldersFirst,
                                 customOrder: customOrder, sortOption: .name,
                                 selectedCategory: category, columnCount: 4).map(\.name)
    }

    // MARK: - Categories the old `switch` never handled

    func testNewlyInstalledShowsOnlyRecentlyInstalledApps() {
        loadMixedLibrary()
        XCTAssertEqual(displayed(.newlyInstalled), ["UserFresh"],
            "Newly Installed must exclude apps installed outside the recency window")
    }

    func testRecentlyLaunchedShowsOnlyLaunchedApps() {
        loadMixedLibrary()
        library.recordAppLaunch(at: "/Applications/UserOld.app")

        XCTAssertEqual(displayed(.recentlyLaunched), ["UserOld"],
            "Recently Launched must exclude apps that were never launched")
    }

    func testMostUsedShowsOnlyLaunchedApps() {
        loadMixedLibrary()
        library.recordAppLaunch(at: "/Applications/UserOld.app")

        XCTAssertEqual(displayed(.mostUsed), ["UserOld"],
            "Most Used must exclude apps with no launch history")
    }

    func testEmptyCategoryYieldsNoApps() {
        loadMixedLibrary()
        XCTAssertTrue(displayed(.recentlyLaunched).isEmpty,
            "With no launches recorded, Recently Launched must be empty rather than showing everything")
    }

    // MARK: - Categories the old code handled, but only sometimes

    func testSystemAndUserSplitTheLibrary() {
        loadMixedLibrary()
        XCTAssertEqual(displayed(.system), ["SystemOld"])
        XCTAssertEqual(displayed(.user).sorted(), ["UserFresh", "UserOld"])
    }

    /// Regression: a non-empty custom order returned before the category filter ran, so any
    /// drag-reorder silently disabled every category tab for good.
    func testCategoryStillFiltersAfterUserReordersApps() {
        loadMixedLibrary()
        let customOrder = [
            "/Applications/UserFresh.app": 0,
            "/System/Applications/SystemOld.app": 1,
            "/Applications/UserOld.app": 2,
        ]

        XCTAssertEqual(displayed(.system, customOrder: customOrder), ["SystemOld"],
            "A custom drag order must not disable category filtering")
        XCTAssertEqual(displayed(.newlyInstalled, customOrder: customOrder), ["UserFresh"],
            "A custom drag order must not disable category filtering")
    }

    /// Regression: "Show Folders First" returned before the category filter ran whenever the
    /// list held at least one folder and one non-folder.
    func testCategoryStillFiltersWithShowFoldersFirst() {
        loadMixedLibrary()
        library.createFolder(name: "Tools", appPaths: ["/Applications/UserOld.app"])

        let systemApps = displayed(.system, showFoldersFirst: true)
        XCTAssertFalse(systemApps.contains("UserFresh"),
            "Show Folders First must not disable category filtering")
        XCTAssertTrue(systemApps.contains("SystemOld"),
            "The matching system app should still be listed")
    }

    // MARK: - All

    func testAllCategoryFiltersNothing() {
        loadMixedLibrary()
        XCTAssertEqual(displayed(.all).sorted(), ["SystemOld", "UserFresh", "UserOld"])
    }

    // MARK: - Counts agree with the grid

    /// The tab badge and the grid are computed by different code paths. They disagreeing is the
    /// exact symptom that made this bug visible: "Newly Installed 1" over a grid of everything.
    func testTabCountsMatchWhatTheGridShows() {
        loadMixedLibrary()
        library.recordAppLaunch(at: "/Applications/UserOld.app")
        library.updateFilteredApps()

        let counts = library.navigation?.categoryCounts ?? [:]
        for category in [AppCategory.all, .system, .user, .newlyInstalled, .recentlyLaunched, .mostUsed] {
            XCTAssertEqual(counts[category, default: 0], displayed(category).count,
                "Tab badge for \(category.rawValue) disagrees with the grid")
        }
    }
}
