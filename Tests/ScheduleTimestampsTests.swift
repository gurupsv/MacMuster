import XCTest
@testable import MacMuster

final class ScheduleTimestampsTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Next update check

    func testNeverCheckedMeansNextLaunch() {
        XCTAssertEqual(ScheduleTimestamps.nextUpdateCheck(lastCheck: nil, now: now), .nextLaunch)
    }

    func testRecentCheckIsNotDueUntilIntervalElapses() {
        let last = now.addingTimeInterval(-3600)
        XCTAssertEqual(ScheduleTimestamps.nextUpdateCheck(lastCheck: last, now: now),
                       .onLaunchAfter(last.addingTimeInterval(day)))
    }

    func testOverdueCheckMeansNextLaunch() {
        let last = now.addingTimeInterval(-day - 1)
        XCTAssertEqual(ScheduleTimestamps.nextUpdateCheck(lastCheck: last, now: now), .nextLaunch)
    }

    func testExactlyDueCountsAsDue() {
        let last = now.addingTimeInterval(-day)
        XCTAssertEqual(ScheduleTimestamps.nextUpdateCheck(lastCheck: last, now: now), .nextLaunch)
    }

    /// A clock set back must not hide a check for days; mirrors `UpdateChecker.isCheckDue`.
    func testFutureLastCheckMeansNextLaunch() {
        let last = now.addingTimeInterval(5 * day)
        XCTAssertEqual(ScheduleTimestamps.nextUpdateCheck(lastCheck: last, now: now), .nextLaunch)
    }

    /// The UI promises exactly what the checker will do.
    func testAgreesWithIsCheckDue() {
        for offset in [-2 * day, -day, -3600, 0, 3600] {
            let last = now.addingTimeInterval(offset)
            let due = UpdateChecker.isCheckDue(enabled: true, lastCheck: last, now: now)
            let next = ScheduleTimestamps.nextUpdateCheck(lastCheck: last, now: now)
            XCTAssertEqual(next == .nextLaunch, due, "offset \(offset)")
        }
    }

    // MARK: - Display

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
    private let locale = Locale(identifier: "en_US")

    func testSameDayShowsTimeOnly() {
        let text = ScheduleTimestamps.display(now.addingTimeInterval(600), now: now, calendar: utc, locale: locale)
        XCTAssertFalse(text.contains(","), "same-day text should be just a time, got \(text)")
        XCTAssertTrue(text.contains(":"))
    }

    func testOtherDayShowsDateAndTime() {
        let text = ScheduleTimestamps.display(now.addingTimeInterval(day), now: now, calendar: utc, locale: locale)
        XCTAssertTrue(text.contains(","), "other-day text should carry a date, got \(text)")
        XCTAssertTrue(text.contains(":"))
    }

    // MARK: - Observable state

    @MainActor
    func testCheckerExposesPersistedLastCheck() {
        XCTAssertEqual(UpdateChecker.shared.lastCheckDate, PreferencesStore.shared.loadLastUpdateCheck())
    }

    @MainActor
    func testRescheduleSetsNextRefreshDateOneIntervalAhead() {
        let state = LibraryScanState()
        XCTAssertNil(state.nextRefreshDate)
        state.rescheduleRefreshTimer()
        guard let next = state.nextRefreshDate else { return XCTFail("timer not scheduled") }
        XCTAssertEqual(next.timeIntervalSinceNow, ScanMetrics.refreshIntervalDefault, accuracy: 5)
        state.cleanupTimerAndObservers()
        XCTAssertNil(state.nextRefreshDate)
    }

    @MainActor
    func testRefreshRecordsLastRefreshDate() async {
        let state = LibraryScanState()
        XCTAssertNil(state.lastRefreshDate)
        let before = Date()
        await state.refreshDisplayOrder(reason: .scheduled)
        XCTAssertGreaterThanOrEqual(state.lastRefreshDate ?? .distantPast, before)
        state.cleanupTimerAndObservers()
    }
}
