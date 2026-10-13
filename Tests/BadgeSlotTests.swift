import XCTest
import Observation
@testable import MacMuster

/// Covers the per-path badge flags on `IconSlot` (`isRunning`, `isRecentlyUpdated`).
///
/// Regression: cells used to ask `runningAppPaths.contains(path)` / `recentlyUpdatedPaths.contains(path)`,
/// which depends on the whole observed `Set` — so any app launching or quitting anywhere on the
/// system re-evaluated every materialized cell (20 cell bodies per launch or quit, measured; 0
/// after). A flag per path invalidates only the cell whose app changed.
@MainActor
final class BadgeSlotTests: XCTestCase {

    private var appModel: AppModel!
    private var library: LibraryScanState { appModel.library }

    private let a = "/Applications/AlphaBadge.app"
    private let b = "/Applications/BetaBadge.app"

    override func setUp() async throws {
        appModel = AppModel()
        library.setApplications([makeApp(a, "AlphaBadge"), makeApp(b, "BetaBadge")])
    }

    override func tearDown() async throws { appModel = nil }

    private func makeApp(_ path: String, _ name: String) -> Application {
        Application(id: path, name: name, path: path, icon: nil, installationDate: Date(), isFolder: false)
    }

    /// `onChange` is `@Sendable`; a reference box lets it report back without a captured `var`.
    private final class Flag: @unchecked Sendable { var fired = false }

    /// True if `body` reads something that `mutate` then changes.
    private func isInvalidated(reading body: () -> Void, by mutate: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking(body, onChange: { flag.fired = true })
        mutate()
        return flag.fired
    }

    // MARK: - Flags follow the sets

    func testRunningFlagFollowsTheSet() {
        let slot = library.iconSlot(for: a)
        XCTAssertFalse(slot.isRunning)

        library.runningAppPaths = [a]
        XCTAssertTrue(slot.isRunning)

        library.runningAppPaths = []
        XCTAssertFalse(slot.isRunning)
    }

    func testRecentlyUpdatedFlagFollowsTheSet() {
        let slot = library.iconSlot(for: a)
        library.recentlyUpdatedPaths = [a]
        XCTAssertTrue(slot.isRecentlyUpdated)
        library.recentlyUpdatedPaths = []
        XCTAssertFalse(slot.isRecentlyUpdated)
    }

    func testFlagsOnlyChangeForThePathsThatChanged() {
        library.runningAppPaths = [a]
        library.runningAppPaths = [a, b]
        XCTAssertTrue(library.iconSlot(for: a).isRunning)
        XCTAssertTrue(library.iconSlot(for: b).isRunning)
        library.runningAppPaths = [b]
        XCTAssertFalse(library.iconSlot(for: a).isRunning)
        XCTAssertTrue(library.iconSlot(for: b).isRunning)
    }

    func testSlotCreatedAfterTheSetsChangedStartsWithTheRightFlags() {
        let late = "/Applications/LateBadge.app"
        library.runningAppPaths = [late]
        library.recentlyUpdatedPaths = [late]

        let slot = library.iconSlot(for: late)   // first request, after the sets already changed

        XCTAssertTrue(slot.isRunning)
        XCTAssertTrue(slot.isRecentlyUpdated)
    }

    func testRebuiltIndexStartsSlotsWithTheRightFlags() {
        library.runningAppPaths = ["/Applications/NewBadge.app"]
        library.setApplications([makeApp("/Applications/NewBadge.app", "NewBadge")])
        XCTAssertTrue(library.iconSlot(for: "/Applications/NewBadge.app").isRunning)
    }

    // MARK: - Observation granularity (the point of the change)

    func testRunningChangeForAnotherAppDoesNotInvalidateThisCell() {
        let slot = library.iconSlot(for: a)
        let invalidated = isInvalidated(reading: { _ = slot.isRunning }, by: { library.runningAppPaths = [b] })
        XCTAssertFalse(invalidated, "App B launching must not re-evaluate app A's cell")
    }

    func testRunningChangeForThisAppInvalidatesThisCell() {
        let slot = library.iconSlot(for: a)
        let invalidated = isInvalidated(reading: { _ = slot.isRunning }, by: { library.runningAppPaths = [a] })
        XCTAssertTrue(invalidated)
    }

    func testRecentlyUpdatedChangeForAnotherAppDoesNotInvalidateThisCell() {
        let slot = library.iconSlot(for: a)
        let invalidated = isInvalidated(reading: { _ = slot.isRecentlyUpdated }, by: { library.recentlyUpdatedPaths = [b] })
        XCTAssertFalse(invalidated)
    }

    /// `iconSlot(for:)` is called from view bodies, so creating a slot must not make the caller
    /// depend on the sets it reads to initialise the flags.
    func testCreatingASlotDoesNotDependOnTheWholeSets() {
        let invalidated = isInvalidated(
            reading: { _ = library.iconSlot(for: "/Applications/FreshBadge.app") },
            by: { library.runningAppPaths = [a]; library.recentlyUpdatedPaths = [b] })
        XCTAssertFalse(invalidated, "A cell must not depend on the whole running/updated sets")
    }

    // MARK: - The spoken label still carries the status

    func testAccessibilityLabelStillReportsRunningAndRecentlyUpdated() {
        let view = ContentView(appModel: appModel)
        let app = makeApp(a, "AlphaBadge")
        let plain = view.accessibilityLabel(for: app)
        XCTAssertFalse(plain.contains(String(localized: ", running")))

        library.runningAppPaths = [a]
        library.recentlyUpdatedPaths = [a]
        let described = view.accessibilityLabel(for: app)

        XCTAssertTrue(described.contains(String(localized: ", running")))
        XCTAssertTrue(described.contains(String(localized: ", recently updated")))
    }

    // MARK: - hasVisibleApplications (ContentView.body no longer copies the catalog to test isEmpty)

    func testHasVisibleApplicationsMatchesVisibleApplications() {
        XCTAssertEqual(library.hasVisibleApplications, !library.visibleApplications.isEmpty)
        XCTAssertTrue(library.hasVisibleApplications)

        library.hiddenAppPaths = [a, b]
        appModel.settings.showHiddenApps = false
        XCTAssertFalse(library.hasVisibleApplications)
        XCTAssertEqual(library.hasVisibleApplications, !library.visibleApplications.isEmpty)

        appModel.settings.showHiddenApps = true
        XCTAssertTrue(library.hasVisibleApplications)
        XCTAssertEqual(library.hasVisibleApplications, !library.visibleApplications.isEmpty)
    }

    func testHasVisibleApplicationsIsFalseForAnEmptyOrPermanentlyHiddenCatalog() {
        library.setApplications([])
        XCTAssertFalse(library.hasVisibleApplications)

        library.setApplications([makeApp("/Applications/MacMuster.app", "MacMuster")])   // permanently hidden
        XCTAssertFalse(library.hasVisibleApplications)
    }
}
