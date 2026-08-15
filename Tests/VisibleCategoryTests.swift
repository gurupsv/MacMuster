import XCTest
@testable import MacMuster

/// "Most Used" and "Recently Launched" are both views onto launch history, which only exists
/// while "Show Recent Apps" is on. With it off they can never be anything but empty, so they are
/// withheld rather than offered as permanently-zero tabs.
@MainActor
final class VisibleCategoryTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        appModel = AppModel()
        appModel.showRecentApps = true
    }

    override func tearDown() async throws {
        appModel = nil
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
    }

    nonisolated func clearAllUserDefaultsState() {
        for key in ["appFolders", "hiddenAppPaths", "customDirectories", "currentFolderId",
                    "customOrder", "sortOption", "showFoldersFirst", "recentAppLaunchTimes",
                    "appLaunchCounts", "showHiddenApps", "recentAppsEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Tab visibility

    func testLaunchHistoryTabsAreOfferedWhenRecentAppsIsOn() {
        appModel.showRecentApps = true
        XCTAssertEqual(appModel.visibleCategories,
                       [.all, .system, .user, .mostUsed, .recentlyLaunched, .newlyInstalled])
    }

    func testLaunchHistoryTabsAreWithheldWhenRecentAppsIsOff() {
        appModel.showRecentApps = false
        XCTAssertEqual(appModel.visibleCategories, [.all, .system, .user, .newlyInstalled],
            "Most Used and Recently Launched should not be offered without launch history")
    }

    func testUtilitiesIsNeverOffered() {
        for enabled in [true, false] {
            appModel.showRecentApps = enabled
            XCTAssertFalse(appModel.visibleCategories.contains(.utilities),
                "getCategory() folds Utilities into User, so the tab could only ever read zero")
        }
    }

    func testTogglingBackOnRestoresTheTabs() {
        appModel.showRecentApps = false
        appModel.showRecentApps = true
        XCTAssertTrue(appModel.visibleCategories.contains(.mostUsed))
        XCTAssertTrue(appModel.visibleCategories.contains(.recentlyLaunched))
    }

    // MARK: - Selection must not strand the user on a retired tab

    func testSelectionFallsBackToAllWhenTheSelectedTabIsRetired() {
        for retired in [AppCategory.mostUsed, .recentlyLaunched] {
            appModel.showRecentApps = true
            appModel.selectedCategory = retired

            appModel.showRecentApps = false

            XCTAssertEqual(appModel.selectedCategory, .all,
                "Standing on \(retired.rawValue) when it is retired must not leave the selection on a tab that no longer exists")
            XCTAssertTrue(appModel.visibleCategories.contains(appModel.selectedCategory),
                "The selected category must always be one the user can see")
        }
    }

    func testSelectionIsLeftAloneWhenItSurvives() {
        appModel.showRecentApps = true
        appModel.selectedCategory = .system

        appModel.showRecentApps = false

        XCTAssertEqual(appModel.selectedCategory, .system,
            "Retiring the launch-history tabs should not disturb an unrelated selection")
    }

    func testSelectionIsLeftAloneWhenEnabling() {
        appModel.showRecentApps = false
        appModel.selectedCategory = .newlyInstalled

        appModel.showRecentApps = true

        XCTAssertEqual(appModel.selectedCategory, .newlyInstalled)
    }

    // MARK: - Counts stay honest across the toggle

    /// Turning the setting off **erases** launch history — `RecentAppsTracker.isEnabled` clears it
    /// on the way down, by design. So the counts do not come back on re-enable, and the restored
    /// tabs correctly start from nothing. What must happen is that the snapshot tracks that
    /// immediately rather than displaying counts for history that no longer exists.
    func testDisablingClearsLaunchHistoryAndTheCountsFollowImmediately() {
        let path = "/Applications/Tracked.app"
        appModel.setApplications([
            Application(id: path, name: "Tracked", path: path, icon: nil,
                        installationDate: Date(), isFolder: false, containedApps: nil)
        ])
        appModel.recordAppLaunch(at: path)
        XCTAssertEqual(appModel.categoryCounts[.mostUsed, default: 0], 1, "Precondition: the launch was recorded")

        appModel.showRecentApps = false
        XCTAssertEqual(appModel.categoryCounts[.mostUsed, default: 0], 0,
            "Counts must drop as soon as the history is purged, not linger until the next scan")

        appModel.showRecentApps = true
        XCTAssertEqual(appModel.categoryCounts[.mostUsed, default: 0], 0,
            "History was erased on disable, so the restored tab legitimately starts empty")
    }

    /// After re-enabling, tracking must actually resume — the restored tabs are only useful if
    /// new launches start counting again.
    func testTrackingResumesAfterReEnabling() {
        let path = "/Applications/Tracked.app"
        appModel.setApplications([
            Application(id: path, name: "Tracked", path: path, icon: nil,
                        installationDate: Date(), isFolder: false, containedApps: nil)
        ])

        appModel.showRecentApps = false
        appModel.recordAppLaunch(at: path)
        XCTAssertEqual(appModel.categoryCounts[.mostUsed, default: 0], 0,
            "Launches while the setting is off must not be recorded")

        appModel.showRecentApps = true
        appModel.recordAppLaunch(at: path)
        XCTAssertEqual(appModel.categoryCounts[.mostUsed, default: 0], 1,
            "Launches after re-enabling must count again")
    }
}
