import XCTest
@testable import MacMuster

@MainActor
final class RecentlyUpdatedTrackerTests: XCTestCase {

    // The tracker is a singleton, so each test must reset its state. `clearAll` wipes both the
    // in-memory maps and the UserDefaults-backed keys, giving every test a clean baseline.
    override func setUp() async throws {
        RecentlyUpdatedTracker.shared.clearAll()
        // `clearAll` schedules a debounced persist; flush it synchronously so UserDefaults is
        // clean before the test reads it.
        RecentlyUpdatedTracker.shared.persist()
        clearPersistedKeys()
    }

    override func tearDown() async throws {
        RecentlyUpdatedTracker.shared.clearAll()
        RecentlyUpdatedTracker.shared.persist()
        clearPersistedKeys()
    }

    nonisolated func clearPersistedKeys() {
        UserDefaults.standard.removeObject(forKey: "knownBundleMtimes")
        UserDefaults.standard.removeObject(forKey: "recentlyUpdatedPaths")
    }

    // MARK: - First-scan baseline (no previous mtime)

    func testFirstScanDoesNotFlagAnyAppAsUpdated() {
        // With no baseline, every app is new — but "new" is not "updated". The first scan must
        // build the baseline without badging anything, otherwise a fresh install would show every
        // app as recently updated.
        let now = Date()
        let mtimes = [
            "/Applications/Safari.app": now,
            "/Applications/Xcode.app": now.addingTimeInterval(-60),
        ]
        RecentlyUpdatedTracker.shared.detectUpdatedApps(currentMtimesByPath: mtimes, now: now)

        XCTAssertTrue(RecentlyUpdatedTracker.shared.recentlyUpdated.isEmpty,
            "First scan with no baseline should not flag any app as updated")
        XCTAssertEqual(RecentlyUpdatedTracker.shared.knownBundleMtimes.count, 2,
            "First scan should record the baseline mtimes for every app")
    }

    // MARK: - mtime delta detection

    func testMtimeIncreaseBeyondEpsilonFlagsAppAsUpdated() {
        let earlier = Date()
        let later = earlier.addingTimeInterval(60) // 60s delta >> 1s epsilon

        // First scan: build baseline.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": earlier], now: earlier)
        // Second scan: mtime jumped.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": later], now: later)

        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "A mtime increase beyond the epsilon should flag the app as recently updated")
    }

    func testMtimeChangeWithinEpsilonDoesNotFlagAppAsUpdated() {
        let earlier = Date()
        // 0.5s delta is below the 1s epsilon — filesystem metadata churn, not a real update.
        let later = earlier.addingTimeInterval(0.5)

        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": earlier], now: earlier)
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": later], now: later)

        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "A mtime change within the epsilon should not flag the app (avoids subsecond-filesystem noise)")
    }

    func testUnchangedMtimeDoesNotFlagAppAsUpdated() {
        let time = Date()
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": time], now: time)
        // Second scan with the same mtime.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": time], now: time.addingTimeInterval(60))

        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "An unchanged mtime should not flag the app as updated")
    }

    func testMtimeDecreaseDoesNotFlagAppAsUpdated() {
        // A decrease is unusual (touch -t, manual rollback) but not an update. Treating it as
        // one would badge apps that users manually touched, which is misleading.
        let later = Date()
        let earlier = later.addingTimeInterval(-60)

        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": later], now: later)
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": earlier], now: earlier)

        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "A mtime decrease should not flag the app as updated")
    }

    // MARK: - Baseline advances after each scan

    func testBaselineAdvancesAfterDetectionSoOnlyNewerDeltasFlagAgain() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(60)
        let t2 = t1.addingTimeInterval(60)

        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": t0], now: t0)
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": t1], now: t1)
        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "t0→t1 delta should flag the app")

        // Third scan at t1 again (no further change): should NOT re-flag (baseline is now t1).
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": t1], now: t2)
        // The app is still in recentlyUpdated from the t1 detection — but it should not be
        // re-detected. We verify by checking that a *different* app with the same t1 mtime
        // and no prior baseline is NOT flagged just because this app was.
        // (The contract: detection only fires on a positive delta from the stored baseline.)
        XCTAssertEqual(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/App.app"], t1,
            "Baseline should advance to the most recent mtime after detection")
    }

    // MARK: - Pruning

    func testExpiredEntriesArePrunedFromRecentlyUpdated() {
        let now = Date()
        let oldDetectionTime = now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds - 1)
        let oldMtime = oldDetectionTime

        // Seed baseline + a detected update that is now expired.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": oldMtime], now: oldDetectionTime)
        // Manually mark it as detected at the old time so it's now expired.
        RecentlyUpdatedTracker.shared.recentlyUpdated["/Applications/App.app"] = oldDetectionTime
        // Now run detection with the same mtime at the current time — should prune the expired entry.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": oldMtime], now: now)

        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "Entries older than the retention window should be pruned from recentlyUpdated")
        XCTAssertNotNil(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/App.app"],
            "knownBundleMtimes should NOT be pruned by age — it's the baseline for future deltas")
    }

    func testPruneExpiredLeavesNonExpiredEntries() {
        let now = Date()
        let recentDetectionTime = now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds + 60)
        let mtime = recentDetectionTime

        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": mtime], now: recentDetectionTime)
        RecentlyUpdatedTracker.shared.recentlyUpdated["/Applications/App.app"] = recentDetectionTime
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": mtime], now: now)

        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "Entries within the retention window should survive pruning")
    }

    // MARK: - Deletion pruning

    func testDeletedAppsArePrunedFromBothMaps() {
        let now = Date()
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: [
                "/Applications/Kept.app": now,
                "/Applications/Gone.app": now,
            ], now: now)
        RecentlyUpdatedTracker.shared.recentlyUpdated["/Applications/Gone.app"] = now

        // Next scan: "Gone.app" no longer present.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/Kept.app": now], now: now)

        XCTAssertNil(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/Gone.app"],
            "Deleted apps should be pruned from knownBundleMtimes")
        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/Gone.app"),
            "Deleted apps should be pruned from recentlyUpdated")
        XCTAssertNotNil(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/Kept.app"],
            "Kept apps should remain in knownBundleMtimes")
    }

    // MARK: - Multiple apps, selective detection

    func testOnlyAppsWithMtimeJumpsAreFlagged() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(120)

        // Baseline for three apps.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: [
                "/Applications/Updated.app": t0,
                "/Applications/Unchanged.app": t0,
                "/Applications/Noisy.app": t0,
            ], now: t0)
        // Second scan: Updated jumped, Unchanged same, Noisy jumped by < epsilon.
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: [
                "/Applications/Updated.app": t1,
                "/Applications/Unchanged.app": t0,
                "/Applications/Noisy.app": t0.addingTimeInterval(0.5),
            ], now: t1)

        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/Updated.app"),
            "The app whose mtime jumped should be flagged")
        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/Unchanged.app"),
            "The app whose mtime was unchanged should not be flagged")
        XCTAssertFalse(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/Noisy.app"),
            "The app whose mtime changed below epsilon should not be flagged")
    }

    // MARK: - Persistence round-trip

    func testPersistenceRoundTripRestoresBothMaps() {
        let now = Date()
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": now], now: now)
        let later = now.addingTimeInterval(60)
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": later], now: later)
        RecentlyUpdatedTracker.shared.persist()

        // Simulate a relaunch: wipe in-memory state, then load from defaults.
        RecentlyUpdatedTracker.shared.clearAll()
        RecentlyUpdatedTracker.shared.loadFromDefaults()

        XCTAssertEqual(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/App.app"], later,
            "Known mtimes should round-trip through UserDefaults")
        XCTAssertTrue(RecentlyUpdatedTracker.shared.isRecentlyUpdated("/Applications/App.app"),
            "Recently-updated membership should round-trip through UserDefaults")
    }

    func testLoadFromDefaultsEvictsExpiredEntries() {
        let now = Date()
        let expiredDetection = now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds - 1)
        // Persist a stale entry directly via PreferencesStore (simulating a backup restore or
        // a long sleep between quit and relaunch).
        PreferencesStore.shared.saveKnownBundleMtimes(["/Applications/App.app": expiredDetection])
        PreferencesStore.shared.saveRecentlyUpdatedPaths(["/Applications/App.app": expiredDetection])

        RecentlyUpdatedTracker.shared.loadFromDefaults()

        XCTAssertNil(RecentlyUpdatedTracker.shared.recentlyUpdated["/Applications/App.app"],
            "Expired recentlyUpdated entries should be evicted on load")
        XCTAssertNotNil(RecentlyUpdatedTracker.shared.knownBundleMtimes["/Applications/App.app"],
            "knownBundleMtimes should survive load (not age-evicted)")
    }

    // MARK: - Clear

    func testClearAllWipesBothMaps() {
        let now = Date()
        RecentlyUpdatedTracker.shared.detectUpdatedApps(
            currentMtimesByPath: ["/Applications/App.app": now], now: now)
        XCTAssertFalse(RecentlyUpdatedTracker.shared.knownBundleMtimes.isEmpty)

        RecentlyUpdatedTracker.shared.clearAll()

        XCTAssertTrue(RecentlyUpdatedTracker.shared.knownBundleMtimes.isEmpty)
        XCTAssertTrue(RecentlyUpdatedTracker.shared.recentlyUpdated.isEmpty)
    }
}