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
}
