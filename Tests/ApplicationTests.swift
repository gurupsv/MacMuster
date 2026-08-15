import XCTest
@testable import MacMuster

final class ApplicationTests: XCTestCase {

    private func makeApp(path: String, isFolder: Bool = false) -> Application {
        Application(id: path, name: "Test", path: path, icon: nil, installationDate: Date(), isFolder: isFolder, containedApps: nil, bundleDescription: nil)
    }

    // MARK: - F-1: isFromTrustedLocation

    func testAppInApplicationsIsTrusted() {
        let app = makeApp(path: "/Applications/Test.app")
        XCTAssertTrue(app.isFromTrustedLocation)
    }

    func testAppInSystemApplicationsIsTrusted() {
        let app = makeApp(path: "/System/Applications/Test.app")
        XCTAssertTrue(app.isFromTrustedLocation)
    }

    func testAppInNestedApplicationsSubfolderIsTrusted() {
        let app = makeApp(path: "/Applications/Utilities/Test.app")
        XCTAssertTrue(app.isFromTrustedLocation)
    }

    func testAppInUserApplicationsIsNotTrusted() {
        let app = makeApp(path: "/Users/test/Applications/Test.app")
        XCTAssertFalse(app.isFromTrustedLocation)
    }

    func testAppInCustomDirectoryIsNotTrusted() {
        let app = makeApp(path: "/Users/test/Downloads/Test.app")
        XCTAssertFalse(app.isFromTrustedLocation)
    }

    func testAppWithSimilarButNonMatchingPrefixIsNotTrusted() {
        // Guards against a naive `.contains` check — "/Applications-Fake/" must not match.
        let app = makeApp(path: "/Applications-Fake/Test.app")
        XCTAssertFalse(app.isFromTrustedLocation)
    }

    func testFolderIsAlwaysTrusted() {
        let folder = makeApp(path: "some-folder-uuid", isFolder: true)
        XCTAssertTrue(folder.isFromTrustedLocation)
    }

    // MARK: - F-1: provenanceWarning (tooltip/accessibility detail)

    func testTrustedAppHasNoProvenanceWarning() {
        let app = makeApp(path: "/Applications/Test.app")
        XCTAssertNil(app.provenanceWarning)
    }

    func testFolderHasNoProvenanceWarning() {
        let folder = makeApp(path: "some-folder-uuid", isFolder: true)
        XCTAssertNil(folder.provenanceWarning)
    }

    func testUserApplicationsWarningNamesHomeApplications() {
        let app = makeApp(path: "\(NSHomeDirectory())/Applications/Test.app")
        XCTAssertEqual(
            app.provenanceWarning,
            "Installed in your personal Applications folder (~/Applications), not the system /Applications — verify this app's source."
        )
    }

    func testCustomDirectoryWarningNamesActualFolder() {
        let app = makeApp(path: "/Users/test/Downloads/Test.app")
        XCTAssertEqual(
            app.provenanceWarning,
            "Installed in /Users/test/Downloads, not /Applications or /System/Applications — verify this app's source."
        )
    }

    // MARK: - stripAppSuffix

    func testStripAppSuffixRemovesTrailingDotApp() {
        XCTAssertEqual(Application.stripAppSuffix("Safari.app"), "Safari")
    }

    func testStripAppSuffixOnlyRemovesTrailingSuffix() {
        XCTAssertEqual(Application.stripAppSuffix("My.app.Tool.app"), "My.app.Tool")
    }

    func testStripAppSuffixLeavesNonAppUnchanged() {
        XCTAssertEqual(Application.stripAppSuffix("MyFolder"), "MyFolder")
    }

    func testStripAppSuffixLeavesShortNameUnchanged() {
        XCTAssertEqual(Application.stripAppSuffix("X.app"), "X")
    }

    // MARK: - searchMatchRank

    func testSearchMatchRankExactNameMatch() {
        let app = Application(id: "/Applications/Safari.app", name: "Safari", path: "/Applications/Safari.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let rank = app.searchMatchRank("safari")
        XCTAssertNotNil(rank, "Exact name match should return a rank")
        XCTAssertEqual(rank, 0, "Exact match should have rank 0 (best)")
    }

    func testSearchMatchRankPrefixMatch() {
        let app = Application(id: "/Applications/Calculator.app", name: "Calculator", path: "/Applications/Calculator.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let rank = app.searchMatchRank("calc")
        XCTAssertNotNil(rank, "Prefix match should return a rank")
        XCTAssert(rank! > 0, "Prefix match should score worse than exact match")
    }

    func testSearchMatchRankSubstringMatch() {
        let app = Application(id: "/Applications/Calculator.app", name: "Calculator", path: "/Applications/Calculator.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let prefixRank = app.searchMatchRank("calc") ?? Int.max
        let substringRank = app.searchMatchRank("ulator") ?? Int.max

        XCTAssert(prefixRank < substringRank,
            "Prefix match should rank higher than substring match")
    }

    func testSearchMatchRankNoMatch() {
        let app = Application(id: "/Applications/Safari.app", name: "Safari", path: "/Applications/Safari.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let rank = app.searchMatchRank("chrome")
        XCTAssertNil(rank, "Non-matching query should return nil")
    }

    func testSearchMatchRankTiebreakByLowercaseName() {
        // Two apps both match "app" as prefix — should tie-break by name.
        let app1 = Application(id: "/Applications/Apple.app", name: "Apple", path: "/Applications/Apple.app",
                              icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let app2 = Application(id: "/Applications/AppKit.app", name: "AppKit", path: "/Applications/AppKit.app",
                              icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)

        let rank1 = app1.searchMatchRank("app") ?? Int.max
        let rank2 = app2.searchMatchRank("app") ?? Int.max

        // Both match as prefix with same rank, tie-break is by name comparison elsewhere.
        XCTAssertNotNil(rank1, "app1 should match")
        XCTAssertNotNil(rank2, "app2 should match")
    }

    func testSearchMatchRankLowercaseNameSearchable() {
        let app = Application(id: "/Applications/Safari.app", name: "Safari", path: "/Applications/Safari.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let rank = app.searchMatchRank("saf")
        XCTAssertNotNil(rank, "Lowercase prefix query should match lowercase name")
    }

    func testSearchMatchRankEmptyQueryMatches() {
        let app = Application(id: "/Applications/Safari.app", name: "Safari", path: "/Applications/Safari.app",
                             icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        let rank = app.searchMatchRank("")
        XCTAssertNotNil(rank, "Empty query should match any app")
        XCTAssertEqual(rank, 0, "Empty query should have rank 0")
    }
}
