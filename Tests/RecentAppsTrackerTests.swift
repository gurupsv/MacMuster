import XCTest
@testable import MacMuster

final class RecentAppsTrackerTests: XCTestCase {

    override func setUpWithError() throws {
        RecentAppsTracker.shared.clearHistory()
        RecentAppsTracker.shared.isEnabled = true
    }

    override func tearDownWithError() throws {
        RecentAppsTracker.shared.clearHistory()
    }

    // MARK: - F-3: retention pruning

    func testPruneRemovesEntriesOlderThanRetentionWindow() {
        let tracker = RecentAppsTracker.shared
        let staleDate = Date().addingTimeInterval(-(kRecentAppsRetentionSeconds + 60))
        tracker.recentAppLaunchTimes["/Applications/Stale.app"] = staleDate
        tracker.appLaunchCounts["/Applications/Stale.app"] = 5

        tracker.pruneRecentLaunchTimes()

        XCTAssertNil(tracker.recentAppLaunchTimes["/Applications/Stale.app"])
        XCTAssertNil(tracker.appLaunchCounts["/Applications/Stale.app"])
    }

    func testPruneKeepsEntriesWithinRetentionWindow() {
        let tracker = RecentAppsTracker.shared
        let recentDate = Date().addingTimeInterval(-60)
        tracker.recentAppLaunchTimes["/Applications/Fresh.app"] = recentDate

        tracker.pruneRecentLaunchTimes()

        XCTAssertNotNil(tracker.recentAppLaunchTimes["/Applications/Fresh.app"])
    }

    func testPruneCapsStoredEntriesToMaxStoredRecentApps() {
        let tracker = RecentAppsTracker.shared
        for i in 0..<(kMaxStoredRecentApps + 20) {
            tracker.recentAppLaunchTimes["/Applications/App\(i).app"] = Date().addingTimeInterval(-Double(i))
        }

        tracker.pruneRecentLaunchTimes()

        XCTAssertLessThanOrEqual(tracker.recentAppLaunchTimes.count, kMaxStoredRecentApps)
        // The most recently launched entry (smallest offset) must survive the cap.
        XCTAssertNotNil(tracker.recentAppLaunchTimes["/Applications/App0.app"])
    }

    func testPruneDropsLaunchCountsForEvictedPaths() {
        let tracker = RecentAppsTracker.shared
        for i in 0..<(kMaxStoredRecentApps + 20) {
            tracker.recentAppLaunchTimes["/Applications/App\(i).app"] = Date().addingTimeInterval(-Double(i))
            tracker.appLaunchCounts["/Applications/App\(i).app"] = 1
        }

        tracker.pruneRecentLaunchTimes()

        XCTAssertEqual(tracker.appLaunchCounts.count, tracker.recentAppLaunchTimes.count)
        // An evicted (oldest) path should have its count dropped too, in lockstep.
        XCTAssertNil(tracker.appLaunchCounts["/Applications/App\(kMaxStoredRecentApps + 19).app"])
    }
}
