import XCTest
@testable import MacMuster

/// Covers **UX-6** and **UX-7**, which shared one comparator and one root cause.
///
/// The comparator returned `false` for every pair of apps with no custom position — reporting them
/// as equal — and short-circuited the whole sort the moment any custom order existed. So a single
/// drag switched the Sort menu off and discarded "Show Folders First", while apps the user had
/// never touched were left to an unstable sort and shuffled between scans.
final class OrderingStabilityTests: XCTestCase {

    private func app(_ name: String, date: Date = Date(timeIntervalSince1970: 1_600_000_000), isFolder: Bool = false) -> Application {
        Application(id: "/Applications/\(name).app", name: name, path: "/Applications/\(name).app",
                    installationDate: date, isFolder: isFolder)
    }

    private func names(_ apps: [Application]) -> [String] { apps.map(\.name) }

    // MARK: - UX-6: a drag must not switch the sort option off

    func testSortOptionStillOrdersAppsWithNoCustomPosition() {
        let apps = [app("Charlie"), app("Alpha"), app("Bravo")]
        // One app dragged to the front; the other two were never touched.
        let custom = ["/Applications/Charlie.app": 0]

        let sorted = ApplicationSorter.sort(apps, by: .name, customOrder: custom)

        XCTAssertEqual(names(sorted), ["Charlie", "Alpha", "Bravo"],
            "The dragged app keeps its position and the rest still follow the chosen sort — this is UX-6")
    }

    func testChangingTheSortOptionIsVisibleDespiteACustomOrder() {
        // Names chosen so alphabetical and date order genuinely disagree: the newest app sorts
        // last by name. Otherwise the two orders coincide and the assertion proves nothing.
        let alphaOld = app("Alpha", date: Date(timeIntervalSince1970: 1_000_000_000))
        let zuluNew = app("Zulu", date: Date(timeIntervalSince1970: 1_700_000_000))
        let pinned = app("Pinned")
        let custom = ["/Applications/Pinned.app": 0]

        let byName = ApplicationSorter.sort([alphaOld, zuluNew, pinned], by: .name, customOrder: custom)
        let byDate = ApplicationSorter.sort([alphaOld, zuluNew, pinned], by: .installationDate, customOrder: custom)

        XCTAssertEqual(names(byName), ["Pinned", "Alpha", "Zulu"], "Name order applies to the untouched apps")
        XCTAssertEqual(names(byDate), ["Pinned", "Zulu", "Alpha"], "Date order puts the newer app first")
        XCTAssertNotEqual(names(byName), names(byDate),
            "With a custom order present, the sort option must still change the result")
    }

    func testDraggedAppsKeepTheirRelativeOrder() {
        let apps = [app("A"), app("B"), app("C")]
        let custom = ["/Applications/C.app": 0, "/Applications/A.app": 1, "/Applications/B.app": 2]

        XCTAssertEqual(names(ApplicationSorter.sort(apps, by: .name, customOrder: custom)), ["C", "A", "B"],
            "An explicit drag order must be honoured exactly")
    }

    func testFoldersFirstSurvivesACustomOrder() {
        let items = [app("Zeta"), app("Docs", isFolder: true), app("Alpha"), app("Work", isFolder: true)]
        let custom = ["/Applications/Zeta.app": 0]

        let sorted = ApplicationSorter.sort(items, by: .name, customOrder: custom, foldersFirst: true)

        XCTAssertEqual(names(sorted), ["Docs", "Work", "Zeta", "Alpha"],
            "Folders stay ahead of apps even with a custom order present — this is the other half of UX-6")
    }

    func testFoldersFirstOffLeavesFoldersInline() {
        let items = [app("Zeta"), app("Docs", isFolder: true), app("Alpha")]
        XCTAssertEqual(names(ApplicationSorter.sort(items, by: .name, customOrder: [:], foldersFirst: false)),
                       ["Alpha", "Docs", "Zeta"],
                       "With the setting off, folders sort among the apps")
    }

    // MARK: - UX-7: ordering must be deterministic

    func testAppsWithNoCustomPositionDoNotShuffleBetweenRuns() {
        // The defect: every such pair compared equal, and Swift's sort is not stable, so repeated
        // scans could return different orders for identical input.
        let apps = (0..<40).map { app("App\($0)") }
        let custom = ["/Applications/App7.app": 0]

        let first = ApplicationSorter.sort(apps, by: .name, customOrder: custom)
        let second = ApplicationSorter.sort(apps.shuffled(), by: .name, customOrder: custom)
        let third = ApplicationSorter.sort(apps.reversed(), by: .name, customOrder: custom)

        XCTAssertEqual(names(first), names(second), "The same set must order identically regardless of input order")
        XCTAssertEqual(names(first), names(third), "Reversing the input must not change the result")
    }

    func testAppsSharingAnInstallDateStillOrderDeterministically() {
        // Ties are common now that an unreadable mtime resolves to .distantPast.
        let same = Date.distantPast
        let apps = [app("Delta", date: same), app("Alpha", date: same), app("Charlie", date: same)]

        let a = ApplicationSorter.sort(apps, by: .installationDate, customOrder: [:])
        let b = ApplicationSorter.sort(apps.reversed(), by: .installationDate, customOrder: [:])

        XCTAssertEqual(names(a), names(b), "Equal install dates must still produce one stable order")
        XCTAssertEqual(names(a), ["Alpha", "Charlie", "Delta"], "The tiebreak should be deterministic, by path")
    }

    func testComparatorIsAStrictWeakOrdering() {
        // Irreflexive and asymmetric — the properties `sorted` relies on. The old comparator
        // reported both directions as false for un-dragged pairs, which is "equal", and left
        // ordering to chance.
        let apps = [app("A"), app("B"), app("C", isFolder: true)]
        for lhs in apps {
            XCTAssertFalse(ApplicationSorter.isOrderedBefore(lhs, lhs, by: .name), "\(lhs.name) must not precede itself")
            for rhs in apps where lhs.path != rhs.path {
                let forward = ApplicationSorter.isOrderedBefore(lhs, rhs, by: .name)
                let backward = ApplicationSorter.isOrderedBefore(rhs, lhs, by: .name)
                XCTAssertNotEqual(forward, backward,
                    "Exactly one of \(lhs.name)/\(rhs.name) must come first, never both or neither")
            }
        }
    }

    func testEmptyCustomOrderFallsBackCleanly() {
        let apps = [app("Beta"), app("Alpha")]
        XCTAssertEqual(names(ApplicationSorter.sort(apps, by: .name, customOrder: [:])), ["Alpha", "Beta"],
            "With no custom order the plain sort applies")
    }

    func testCustomOrderForAppsNotPresentIsIgnored() {
        // A stale order dictionary refers to apps that have since been uninstalled.
        let apps = [app("Beta"), app("Alpha")]
        let stale = ["/Applications/Gone.app": 0, "/Applications/AlsoGone.app": 1]

        XCTAssertEqual(names(ApplicationSorter.sort(apps, by: .name, customOrder: stale)), ["Alpha", "Beta"],
            "Entries for uninstalled apps must not disturb the surviving ones")
    }

    func testDuplicatePositionsInCustomOrderStillOrderDeterministically() {
        let apps = [app("Beta"), app("Alpha")]
        let corrupt = ["/Applications/Beta.app": 3, "/Applications/Alpha.app": 3]

        let a = ApplicationSorter.sort(apps, by: .name, customOrder: corrupt)
        let b = ApplicationSorter.sort(apps.reversed(), by: .name, customOrder: corrupt)
        XCTAssertEqual(names(a), names(b), "Two apps sharing a position must still order deterministically")
    }
}
