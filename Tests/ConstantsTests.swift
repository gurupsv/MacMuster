import XCTest
@testable import MacMuster

@MainActor
final class ConstantsTests: XCTestCase {

    func testKeyConstantsHaveExpectedValues() {
        XCTAssertEqual(ScanMetrics.maxRecentApps, 8)
        XCTAssertEqual(WindowMetrics.windowAnimationDelay, 0.1)
        XCTAssertEqual(WindowMetrics.windowMinWidth, 900)
        XCTAssertEqual(WindowMetrics.windowMinHeight, 700)
        XCTAssertEqual(LayoutMetrics.minColumnCount, 4)
        XCTAssertEqual(LayoutMetrics.maxColumnCount, 10)
        XCTAssertEqual(WindowMetrics.settingsWindowWidth, 820)
        XCTAssertEqual(WindowMetrics.settingsWindowHeight, 560)
        XCTAssertEqual(SettingsLayoutMetrics.sidebarWidth, 200)
    }

    // MARK: - UpdateMetrics (Phase 1 + 2)

    func testUpdateMetricsRecentlyUpdatedBadgeSecondsMatchesNewlyInstalledWindow() {
        // The recently-updated badge and the newly-installed badge retire on the same cadence
        // — a user who notices one expects the other to behave the same way. Locking these
        // together as a constant relationship catches a future edit that diverges them.
        XCTAssertEqual(UpdateMetrics.recentlyUpdatedBadgeSeconds, ScanMetrics.newlyInstalledWindowSeconds,
            "recentlyUpdatedBadgeSeconds should match newlyInstalledWindowSeconds")
    }

    func testUpdateMetricsMtimeEpsilonIsOneSecond() {
        // 1s matches `IconCacheManager.datesEqualIgnoringSubsecond`'s second-granularity
        // comparison — the epsilon and the icon cache both treat subsecond mtime churn as noise.
        XCTAssertEqual(UpdateMetrics.mtimeDeltaEpsilonSeconds, 1.0,
            "mtimeDeltaEpsilonSeconds should be 1.0 (second granularity)")
    }

    func testUpdateMetricsBadgeSizesArePositive() {
        XCTAssertGreaterThan(UpdateMetrics.recentlyUpdatedBadgeSymbolSize, 0,
            "Recently-updated badge symbol size must be positive")
        XCTAssertGreaterThan(UpdateMetrics.runningDotSize, 0,
            "Running dot size must be positive")
    }
}
