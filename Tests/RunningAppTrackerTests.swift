import XCTest
import AppKit
@testable import MacMuster

@MainActor
final class RunningAppTrackerTests: XCTestCase {

    override func tearDown() async throws {
        RunningAppTracker.shared.stop()
        RunningAppTracker.shared.runningAppPaths = []
    }

    // MARK: - Snapshot

    func testRefreshSnapshotPopulatesFromNSWorkspace() {
        RunningAppTracker.shared.refreshSnapshot()
        // On any running macOS, at least one system app is in `runningApplications`
        // (Finder, Dock, loginwindow, etc.). An empty set would mean the snapshot read
        // failed or the API contract changed — either way, a regression worth catching.
        XCTAssertFalse(RunningAppTracker.shared.runningAppPaths.isEmpty,
            "refreshSnapshot should populate runningAppPaths from NSWorkspace.runningApplications; "
                + "at least Finder/Dock are always running")
    }

    func testRefreshSnapshotContainsBundlePaths() {
        RunningAppTracker.shared.refreshSnapshot()
        // Every entry should be a path to a .app bundle (the contract the UI badge relies on
        // — it matches against `Application.path`, which is a .app bundle path).
        for path in RunningAppTracker.shared.runningAppPaths {
            XCTAssertTrue(path.hasSuffix(".app"),
                "runningAppPaths should contain .app bundle paths only; found: \(path)")
        }
    }

    // MARK: - isRunning

    func testIsRunningReturnsTrueForRunningApp() {
        RunningAppTracker.shared.refreshSnapshot()
        // Find a path that is genuinely running and verify isRunning agrees with the set.
        guard let runningPath = RunningAppTracker.shared.runningAppPaths.first else {
            XCTFail("No running apps to test against")
            return
        }
        XCTAssertTrue(RunningAppTracker.shared.isRunning(runningPath),
            "isRunning should return true for a path in runningAppPaths")
    }

    func testIsRunningReturnsFalseForNonRunningApp() {
        RunningAppTracker.shared.refreshSnapshot()
        XCTAssertFalse(RunningAppTracker.shared.isRunning("/Applications/DefinitelyNotRunning.app"),
            "isRunning should return false for a path not in runningAppPaths")
    }

    // MARK: - start/stop idempotency

    func testStartIsIdempotent() {
        // Calling start twice should not throw, double-register observers, or lose state.
        RunningAppTracker.shared.start()
        let afterFirst = RunningAppTracker.shared.runningAppPaths
        RunningAppTracker.shared.start()
        let afterSecond = RunningAppTracker.shared.runningAppPaths
        // The snapshot is refreshed on each start, so the set may differ slightly (apps
        // launched between the two calls), but both should be non-empty and the second
        // call should not wipe the first.
        XCTAssertFalse(afterFirst.isEmpty, "First start() should populate runningAppPaths")
        XCTAssertFalse(afterSecond.isEmpty, "Second start() should populate runningAppPaths")
    }

    func testStopClearsObserversWithoutCrashing() {
        RunningAppTracker.shared.start()
        RunningAppTracker.shared.stop()
        // A second stop should be a no-op (observers are already nil) — not a crash.
        RunningAppTracker.shared.stop()
    }

    func testStopDoesNotWipeRunningAppPaths() {
        // stop() removes observers but leaves runningAppPaths in place; the next start()
        // rebuilds from a fresh snapshot. This contract lets a caller stop+start without
        // the UI briefly showing zero running apps between the two calls.
        RunningAppTracker.shared.start()
        let beforeStop = RunningAppTracker.shared.runningAppPaths
        XCTAssertFalse(beforeStop.isEmpty)
        RunningAppTracker.shared.stop()
        XCTAssertEqual(RunningAppTracker.shared.runningAppPaths, beforeStop,
            "stop() should remove observers but leave runningAppPaths intact")
    }
}