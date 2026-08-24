import XCTest
@testable import MacMuster

@MainActor
final class AppModelTests: XCTestCase {
    
    private var appModel: AppModel!
    
    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
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
        // Schema v2 keys — clear so recently-updated badge state doesn't leak between tests.
        UserDefaults.standard.removeObject(forKey: "knownBundleMtimes")
        UserDefaults.standard.removeObject(forKey: "recentlyUpdatedPaths")
    }
    
    // MARK: - Application Identity Tests
    
    func testApplicationUsesPathAsId() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertEqual(app.id, "/Applications/Test.app")
    }
    
    func testApplicationEqualityBasedOnPath() {
        let app1 = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/Test.app", name: "Test (2)", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertTrue(app1 == app2)
    }
    
    func testApplicationDifferentPathsAreNotEqual() {
        let app1 = Application(id: "/Applications/Test1.app", name: "Test1", path: "/Applications/Test1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/Test2.app", name: "Test2", path: "/Applications/Test2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertNotEqual(app1, app2)
    }
    
    // MARK: - Sorting Tests
    
    func testDefaultSortOptionIsName() {
        XCTAssertEqual(appModel.sortOption, .name)
    }
    
    func testSetSortOptionChangesSortOrder() {
        let apps = [
            Application(id: "/Applications/Zulu.app", name: "Zulu", path: "/Applications/Zulu.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Alpha.app", name: "Alpha", path: "/Applications/Alpha.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        XCTAssertEqual(appModel.displayOrder.map { $0.name }, ["Alpha", "Zulu"])
    }
    
    func testSetSortOptionClearsCustomOrder() {
        let app1 = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2])
        appModel.customOrder[app1.path] = 0
        appModel.customOrder[app2.path] = 1
        
        appModel.setSortOption(.name)
        XCTAssertTrue(appModel.customOrder.isEmpty)
    }
    
    // MARK: - Search Filter Tests
    
    func testSearchFilterCaseInsensitive() {
        appModel.searchTerm = "test"
        let apps = [
            Application(id: "/Applications/TestApp.app", name: "TestApp", path: "/Applications/TestApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/other.app", name: "other", path: "/Applications/other.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        
        let filtered = appModel.getDisplayedApps()
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].name, "TestApp")
    }
    
    func testSearchFilterEmptyReturnsAllApps() {
        let apps = [
            Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        appModel.searchTerm = ""
        
        XCTAssertEqual(appModel.getDisplayedApps().count, 2)
    }
    
    func testSearchFilterNoResults() {
        appModel.searchTerm = "nonexistent"
        let apps = [
            Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        
        XCTAssertTrue(appModel.getDisplayedApps().isEmpty)
    }
    
    func testClearSearchStateResetsSearchOnly() {
        let app1 = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2])
        appModel.searchTerm = "test"
        appModel.customOrder[app1.path] = 0
        
        appModel.clearSearchState()
        
        XCTAssertTrue(appModel.searchTerm.isEmpty)
        XCTAssertEqual(appModel.customOrder[app1.path], 0)
    }
    
    // MARK: - Recent Apps Tests
    
    
    
    func testGetRecentAppsReturnsEmptyWhenNoneRecorded() {
        let recent = appModel.getRecentApps()
        XCTAssertTrue(recent.isEmpty)
    }
    
    // MARK: - Custom Order Tests
    
    func testUpdateCustomOrder() {
        let app1 = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app3 = Application(id: "/Applications/App3.app", name: "App3", path: "/Applications/App3.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2, app3])
        
        // Reverse the order
        let reversedApps = [app3, app2, app1]
        appModel.updateCustomOrder(from: reversedApps)
        
        XCTAssertEqual(appModel.displayOrder.map { $0.path }, [app3.path, app2.path, app1.path])
    }
    
    // MARK: - Sorted Applications Tests
    
    func testSortedApplicationsByName() {
        let apps = [
            Application(id: "/Applications/Charlie.app", name: "Charlie", path: "/Applications/Charlie.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Alice.app", name: "Alice", path: "/Applications/Alice.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Bob.app", name: "Bob", path: "/Applications/Bob.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        
        let sorted = appModel.sortedApplications(apps)
        XCTAssertEqual(sorted.map { $0.name }, ["Alice", "Bob", "Charlie"])
    }
    
    func testSortedApplicationsByDate() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)
        
        let apps = [
            Application(id: "/Applications/Old.app", name: "Old", path: "/Applications/Old.app", icon: nil, installationDate: date1, isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/New.app", name: "New", path: "/Applications/New.app", icon: nil, installationDate: date3, isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Middle.app", name: "Middle", path: "/Applications/Middle.app", icon: nil, installationDate: date2, isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        
        appModel.sortOption = .installationDate
        let sorted = appModel.sortedApplications(apps)
        XCTAssertEqual(sorted.map { $0.name }, ["New", "Middle", "Old"])
    }
    
    func testSortedApplicationsWithCustomOrder() {
        let app1 = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app3 = Application(id: "/Applications/App3.app", name: "App3", path: "/Applications/App3.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        
        appModel.customOrder[app3.path] = 0
        appModel.customOrder[app1.path] = 1
        appModel.customOrder[app2.path] = 2
        
        let apps = [app1, app2, app3]
        let sorted = appModel.sortedApplications(apps)
        XCTAssertEqual(sorted.map { $0.path }, [app3.path, app1.path, app2.path])
    }
    
    // MARK: - AppCategory Tests
    
    func testSystemCategoryForSystemApps() {
        let app = Application(id: "/System/Applications/Safari.app", name: "Safari", path: "/System/Applications/Safari.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertEqual(appModel.getCategory(for: app), .system)
    }
    
    func testUtilitiesCategoryForUtilityAppsReturnsUser() {
        let app = Application(id: "/Applications/Utilities/Terminal.app", name: "Terminal", path: "/Applications/Utilities/Terminal.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertEqual(appModel.getCategory(for: app), .user)
    }
    
    func testUserCategoryForUserApps() {
        let app = Application(id: "/Applications/MyApp.app", name: "MyApp", path: "/Applications/MyApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertEqual(appModel.getCategory(for: app), .user)
    }
    
    func testAllCategoriesExist() {
        let categories = AppCategory.allCases
        // all, mostUsed, recentlyLaunched, newlyInstalled, system, utilities, user
        XCTAssertEqual(categories.count, 7)
        XCTAssertTrue(categories.contains(where: { $0 == .system }))
        XCTAssertTrue(categories.contains(where: { $0 == .utilities }))
        XCTAssertTrue(categories.contains(where: { $0 == .user }))
    }
    
    // MARK: - Icon Loading & Caching Tests

    func testSelectedAppIndexResetToNegativeOneWhenDisplayedListEmpty() {
        let app1 = Application(id: "/Applications/SearchMe.app", name: "SearchMe", path: "/Applications/SearchMe.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/Other.app", name: "Other", path: "/Applications/Other.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2])

        // Navigate to first app
        appModel.selectFirstApp()
        XCTAssertEqual(appModel.selectedAppIndex, 0)

        // Search that matches nothing
        appModel.searchTerm = "nomatch"
        appModel.updateFilteredApps()

        // selectedAppIndex should reset to -1, not stay at 0
        XCTAssertEqual(appModel.selectedAppIndex, -1)
        XCTAssertTrue(appModel.getDisplayedApps().isEmpty)
    }

    func testLaunchSelectedAppReturnsFalseWhenNoSelection() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        // No selection (selectedAppIndex = -1)
        appModel.searchTerm = "nomatch"
        appModel.updateFilteredApps()

        let launched = appModel.launchSelectedApp()
        XCTAssertFalse(launched)
    }

    // MARK: - Category Counts Tests

    func testCategoryCountsReflectSearchFilter() {
        let app1 = Application(id: "/System/Applications/Safari.app", name: "Safari", path: "/System/Applications/Safari.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/System/Applications/Finder.app", name: "Finder", path: "/System/Applications/Finder.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app3 = Application(id: "/Applications/Xcode.app", name: "Xcode", path: "/Applications/Xcode.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2, app3])

        // Before search: counts show all apps per category
        XCTAssertEqual(appModel.categoryCounts[.system] ?? 0, 2)
        XCTAssertEqual(appModel.categoryCounts[.user] ?? 0, 1)
        XCTAssertEqual(appModel.categoryCounts[.utilities] ?? 0, 0)

        // Search for "Safari" — only matches app1 in System category
        appModel.searchTerm = "Safari"
        appModel.updateFilteredApps()

        // After search: counts should reflect only matching apps
        XCTAssertEqual(appModel.categoryCounts[.system] ?? 0, 1)
        XCTAssertEqual(appModel.categoryCounts[.user] ?? 0, 0)
        XCTAssertEqual(appModel.categoryCounts[.utilities] ?? 0, 0)
    }

    func testCategoryCountsBecomesZeroWhenSearchYieldsNoResults() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])
        XCTAssertEqual(appModel.categoryCounts[.user] ?? 0, 1)

        appModel.searchTerm = "nomatch"
        appModel.updateFilteredApps()

        // All category counts should be zero
        for category in AppCategory.allCases {
            XCTAssertEqual(appModel.categoryCounts[category] ?? 0, 0)
        }
    }

    // MARK: - Refresh Interval Validation Tests

    func testRefreshIntervalDirectSetBypassesValidation() {
        appModel.refreshInterval = 0.001
        XCTAssertEqual(appModel.refreshInterval, 0.001)
    }

    func testRefreshIntervalDefaultIs300Seconds() {
        XCTAssertEqual(appModel.refreshInterval, 300)
    }

    // MARK: - Hidden Apps Tests

    func testToggleHiddenAppRemovesFromVisibleList() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertEqual(appModel.visibleApplications.count, 1)

        appModel.toggleHiddenApp(app.path)

        XCTAssertEqual(appModel.visibleApplications.count, 0)
    }

    func testToggleHiddenAppTwiceRestoresVisibility() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        appModel.toggleHiddenApp(app.path)
        appModel.toggleHiddenApp(app.path)

        XCTAssertEqual(appModel.visibleApplications.count, 1)
        XCTAssertFalse(appModel.isAppHidden(app.path))
    }

    func testShowHiddenAppsDefaultIsFalse() {
        XCTAssertFalse(appModel.showHiddenApps)
    }

    func testShowHiddenAppsTrueRevealsHiddenAppsInVisibleList() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)

        appModel.showHiddenApps = true

        XCTAssertEqual(appModel.visibleApplications.count, 1)
    }

    func testShowHiddenAppsFalseStillHidesApps() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)

        appModel.showHiddenApps = false

        XCTAssertEqual(appModel.visibleApplications.count, 0)
    }

    func testShowHiddenAppsTogglingUpdatesVisibility() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)

        appModel.showHiddenApps = true
        XCTAssertEqual(appModel.visibleApplications.count, 1)

        appModel.showHiddenApps = false
        XCTAssertEqual(appModel.visibleApplications.count, 0)

        appModel.showHiddenApps = true
        XCTAssertEqual(appModel.visibleApplications.count, 1)
    }

    func testShowHiddenAppsDoesNotRevealPermanentlyHiddenApps() {
        let app = Application(id: "/System/Applications/Launchpad.app", name: "Launchpad", path: "/System/Applications/Launchpad.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        appModel.showHiddenApps = true

        XCTAssertEqual(appModel.visibleApplications.count, 0)
    }

    func testShowHiddenAppsDelegatesToSettings() {
        appModel.showHiddenApps = true
        XCTAssertTrue(appModel.settings.showHiddenApps)

        appModel.showHiddenApps = false
        XCTAssertFalse(appModel.settings.showHiddenApps)
    }

    // MARK: - Search & Navigation Tests

    func testNavigationWrapsAroundInCircularFashion() {
        let app1 = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app1, app2])

        // Navigate forward from -1 → 0 → 1 → 0 (wrap)
        appModel.selectNextApp()
        XCTAssertEqual(appModel.selectedAppIndex, 0)
        appModel.selectNextApp()
        XCTAssertEqual(appModel.selectedAppIndex, 1)
        appModel.selectNextApp()
        XCTAssertEqual(appModel.selectedAppIndex, 0)

        // Navigate backward from 0 → 1 (wrap to end)
        appModel.selectPreviousApp()
        XCTAssertEqual(appModel.selectedAppIndex, 1)
        appModel.selectPreviousApp()
        XCTAssertEqual(appModel.selectedAppIndex, 0)
    }

    func testSelectFirstAppAndSelectLastApp() {
        let apps = [
            Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/App3.app", name: "App3", path: "/Applications/App3.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)

        appModel.selectFirstApp()
        XCTAssertEqual(appModel.selectedAppIndex, 0)

        appModel.selectLastApp()
        XCTAssertEqual(appModel.selectedAppIndex, 2)
    }

    func testSelectAppAtIndexGuardsAgainstOutOfBounds() {
        let app = Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        appModel.selectApp(at: 100)
        XCTAssertEqual(appModel.selectedAppIndex, -1)  // Should remain unchanged
    }

    // MARK: - Recent Apps Tests

    func testRecordAppLaunchAddsToRecent() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))
        appModel.recordAppLaunch(at: app.path)
        XCTAssertTrue(appModel.isRecentApp(app.path))
    }

    func testRecentAppsLimitedToEightMostRecent() {
        let apps = (1...15).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)

        // Record 15 launches
        for i in 0..<15 {
            appModel.recordAppLaunch(at: apps[i].path)
            usleep(10)  // Small delay to ensure different timestamps
        }

        // Most recent 8 should be in recent apps
        let recentApps = appModel.getRecentApps()
        XCTAssertLessThanOrEqual(recentApps.count, 8)
        XCTAssertTrue(appModel.isRecentApp(apps[14].path))  // Last one should be there
        XCTAssertFalse(appModel.isRecentApp(apps[0].path))  // First one should be evicted
    }

    // MARK: - Sorting Tests (Name Comparison)

    func testSortByNameUsesLocalizedCaseInsensitiveComparison() {
        let apps = [
            Application(id: "/Applications/Zebra.app", name: "Zebra", path: "/Applications/Zebra.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/apple.app", name: "apple", path: "/Applications/apple.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Banana.app", name: "Banana", path: "/Applications/Banana.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        appModel.setSortOption(.name)

        let names = appModel.displayOrder.map { $0.name }
        XCTAssertEqual(names, ["apple", "Banana", "Zebra"])
    }

    func testSortByInstallationDateNewest() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        let apps = [
            Application(id: "/Applications/Old.app", name: "Old", path: "/Applications/Old.app", icon: nil, installationDate: twoDaysAgo, isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/New.app", name: "New", path: "/Applications/New.app", icon: nil, installationDate: now, isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Middle.app", name: "Middle", path: "/Applications/Middle.app", icon: nil, installationDate: yesterday, isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        appModel.setSortOption(.installationDate)

        let names = appModel.displayOrder.map { $0.name }
        XCTAssertEqual(names, ["New", "Middle", "Old"])
    }

    // MARK: - Grid Navigation Tests

    func testSelectAppUpMovesUpByColumnCount() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 9 (row 1, col 1)
        appModel.selectedAppIndex = 9
        appModel.selectAppUp()

        // Should move to index 1 (row 0, col 1)
        XCTAssertEqual(appModel.selectedAppIndex, 1)
    }

    func testSelectAppDownMovesDownByColumnCount() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 1 (row 0, col 1)
        appModel.selectedAppIndex = 1
        appModel.selectAppDown()

        // Should move to index 9 (row 1, col 1)
        XCTAssertEqual(appModel.selectedAppIndex, 9)
    }

    func testSelectAppLeftMovesLeft() {
        let apps = (0..<8).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        appModel.selectedAppIndex = 3
        appModel.selectAppLeft()

        XCTAssertEqual(appModel.selectedAppIndex, 2)
    }

    func testSelectAppRightMovesRight() {
        let apps = (0..<8).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        appModel.selectedAppIndex = 2
        appModel.selectAppRight()

        XCTAssertEqual(appModel.selectedAppIndex, 3)
    }

    func testSelectAppUpWrapsToBottomRow() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 1 (row 0, col 1)
        appModel.selectedAppIndex = 1
        appModel.selectAppUp()

        // Should wrap to bottom row, same column (index 9)
        XCTAssertEqual(appModel.selectedAppIndex, 9)
    }

    func testSelectAppDownWrapsToTopRow() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 9 (row 1, col 1)
        appModel.selectedAppIndex = 9
        appModel.selectAppDown()

        // Should wrap to top row, same column (index 1)
        XCTAssertEqual(appModel.selectedAppIndex, 1)
    }

    func testSelectAppLeftWrapsToEndOfPreviousRow() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 8 (row 1, col 0) — start of row
        appModel.selectedAppIndex = 8
        appModel.selectAppLeft()

        // Should wrap to end of previous row (index 7)
        XCTAssertEqual(appModel.selectedAppIndex, 7)
    }

    func testSelectAppRightWrapsToStartOfNextRow() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Start at index 7 (row 0, col 7) — end of row
        appModel.selectedAppIndex = 7
        appModel.selectAppRight()

        // Should wrap to start of next row (index 8)
        XCTAssertEqual(appModel.selectedAppIndex, 8)
    }

    func testGridNavigationWithDifferentColumnCounts() {
        let apps = (0..<20).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)

        // Test with 4 columns
        appModel.columnCount = 4
        appModel.selectedAppIndex = 5  // row 1, col 1
        appModel.selectAppUp()
        XCTAssertEqual(appModel.selectedAppIndex, 1)  // row 0, col 1

        // Test with 5 columns
        appModel.columnCount = 5
        appModel.selectedAppIndex = 7  // row 1, col 2
        appModel.selectAppUp()
        XCTAssertEqual(appModel.selectedAppIndex, 2)  // row 0, col 2
    }

    // MARK: - Extra Large Icon Size

    func testIconSizeExtraLargeIsCaseIterable() {
        let cases = IconSize.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.extraLarge))
    }

    func testIconSizeExtraLargeRawValue() {
        XCTAssertEqual(IconSize.extraLarge.rawValue, "Extra Large")
    }

    func testIconSizeExtraLargeConstant() {
        XCTAssertEqual(IconMetrics.iconSizeExtraLarge, 100)
    }

    // MARK: - Presentation Mode

    func testPresentationModeDefaultIsGlass() {
        XCTAssertEqual(appModel.presentationMode, .glass)
    }

    func testPresentationModeAllCases() {
        let cases = SettingsAppearance.PresentationMode.allCases
        XCTAssertEqual(cases.count, 2)
        XCTAssertTrue(cases.contains(.glass))
        XCTAssertTrue(cases.contains(.sheet))
    }

    func testSetPresentationModeUpdatesProperty() {
        appModel.presentationMode = .sheet
        XCTAssertEqual(appModel.presentationMode, .sheet)
    }

    // MARK: - Tint Color & Strength

    func testTintColorDefaultIsBlue() {
        XCTAssertEqual(appModel.tintColor, .blue)
    }

    func testTintStrengthDefaultIsZero() {
        XCTAssertEqual(appModel.tintStrength, 0.0)
    }

    func testTintStrengthClampedToZero() {
        appModel.tintStrength = -0.5
        XCTAssertEqual(appModel.tintStrength, 0.0)
    }

    func testTintStrengthClampedToOne() {
        appModel.tintStrength = 1.5
        XCTAssertEqual(appModel.tintStrength, 1.0)
    }

    func testTintedBackgroundColorReturnsBlackWhenStrengthZero() {
        let color = appModel.settings.tintedBackgroundColor()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    // MARK: - Permanently Hidden Apps

    func testLaunchpadIsAlwaysHidden() {
        XCTAssertTrue(appModel.isAppHidden("/System/Applications/Launchpad.app"))
    }

    func testLaunchpadNotInDisplayedApps() {
        let apps = [
            Application(id: "/System/Applications/Launchpad.app", name: "Launchpad", path: "/System/Applications/Launchpad.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        let displayed = appModel.getDisplayedApps()
        XCTAssertFalse(displayed.contains { $0.path == "/System/Applications/Launchpad.app" }, "Launchpad should not appear in displayed apps")
        XCTAssertTrue(displayed.contains { $0.path == "/Applications/Test.app" }, "Other apps should still appear")
    }

    func testTogglePermanentlyHiddenAppIsIgnored() {
        appModel.toggleHiddenApp("/System/Applications/App Store.app")
        XCTAssertTrue(appModel.isAppHidden("/System/Applications/App Store.app"))
    }

    func testNormalAppCanBeToggled() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])
        XCTAssertFalse(appModel.isAppHidden(app.path))
        appModel.toggleHiddenApp(app.path)
        XCTAssertTrue(appModel.isAppHidden(app.path))
        appModel.toggleHiddenApp(app.path)
        XCTAssertFalse(appModel.isAppHidden(app.path))
    }

    // MARK: - Category Filter

    func testSystemCategoryFiltersToSystemAppsOnly() {
        let systemApp = Application(id: "/System/Applications/Safari.app", name: "Safari", path: "/System/Applications/Safari.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let userApp = Application(id: "/Applications/MyApp.app", name: "MyApp", path: "/Applications/MyApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([systemApp, userApp])
        appModel.selectedCategory = .system
        let displayed = appModel.getDisplayedApps()
        XCTAssertEqual(displayed.count, 1)
        XCTAssertEqual(displayed[0].name, "Safari")
    }

    func testUserCategoryFiltersToUserAppsOnly() {
        let systemApp = Application(id: "/System/Applications/Safari.app", name: "Safari", path: "/System/Applications/Safari.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let userApp = Application(id: "/Applications/MyApp.app", name: "MyApp", path: "/Applications/MyApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([systemApp, userApp])
        appModel.selectedCategory = .user
        let displayed = appModel.getDisplayedApps()
        XCTAssertEqual(displayed.count, 1)
        XCTAssertEqual(displayed[0].name, "MyApp")
    }

    func testAllCategoryShowsAllApps() {
        let systemApp = Application(id: "/System/Applications/Safari.app", name: "Safari", path: "/System/Applications/Safari.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let userApp = Application(id: "/Applications/MyApp.app", name: "MyApp", path: "/Applications/MyApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([systemApp, userApp])
        appModel.selectedCategory = .all
        let displayed = appModel.getDisplayedApps()
        XCTAssertEqual(displayed.count, 2)
    }

    // MARK: - PresentationMode (Bug #3: bare enum removed, only SettingsAppearance.PresentationMode exists)

    func testPresentationModeIsNamespacedUnderSettingsAppearance() {
        // The bare `PresentationMode` enum was removed from Types.swift.
        // Only `SettingsAppearance.PresentationMode` should exist.
        let mode = SettingsAppearance.PresentationMode.glass
        XCTAssertEqual(mode.rawValue, "Glass")
        XCTAssertEqual(SettingsAppearance.PresentationMode.allCases.count, 2)
    }

    func testPresentationModeRoundTripsThroughRawValue() {
        for mode in SettingsAppearance.PresentationMode.allCases {
            let raw = mode.rawValue
            let restored = SettingsAppearance.PresentationMode(rawValue: raw)
            XCTAssertEqual(restored, mode, "PresentationMode '\(raw)' should round-trip")
        }
    }
}