import XCTest
@testable import MacMuster

/// Regression coverage for a real bug found on a live machine: vendor installers routinely create
/// plain Finder folders (no `Contents` directory of their own) that wrap one or more `.app`
/// bundles — e.g. "MacCleaner 3 Pro/Memory Cleaner 5.app" or "Canon Utilities/Inkjet Extended
/// Survey Program/Inkjet Extended Survey Program.app". `scanDirectories` used to require a
/// directory to have its own `Contents` subfolder before it would even look inside for nested
/// apps, which silently hid every app shipped this way.
final class ApplicationScannerTests: XCTestCase {

    private var tempRoot: String!

    override func setUpWithError() throws {
        let base = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        tempRoot = (base as NSString).appendingPathComponent("MacMusterScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tempRoot)
        tempRoot = nil
    }

    /// Creates `<tempRoot>/<relativeBundlePath>/Contents` so the path looks like a minimal,
    /// valid `.app` bundle to the scanner (it only checks for a `Contents` subdirectory).
    private func makeFakeApp(at relativeBundlePath: String) -> String {
        let bundlePath = (tempRoot as NSString).appendingPathComponent(relativeBundlePath)
        let contentsPath = (bundlePath as NSString).appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(atPath: contentsPath, withIntermediateDirectories: true)
        return bundlePath
    }

    func testAppNestedInPlainWrapperFolderIsDiscovered() {
        let appPath = makeFakeApp(at: "MacCleaner 3 Pro/Memory Cleaner 5.app")

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        XCTAssertTrue(result.apps.contains { $0.path == appPath },
                      "App nested inside a plain wrapper folder (no Contents dir of its own) should still be discovered")
    }

    func testAppNestedTwoLevelsDeepInPlainFoldersIsDiscovered() {
        let appPath = makeFakeApp(at: "Canon Utilities/Inkjet Extended Survey Program/Inkjet Extended Survey Program.app")

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        XCTAssertTrue(result.apps.contains { $0.path == appPath },
                      "Apps nested multiple levels deep inside plain folders should still be discovered")
    }

    func testWrapperFolderWithSingleAppIsNotItselfShownAsAnEntry() {
        let appPath = makeFakeApp(at: "MacCleaner 3 Pro/Memory Cleaner 5.app")
        let wrapperPath = (tempRoot as NSString).appendingPathComponent("MacCleaner 3 Pro")

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        XCTAssertFalse(result.apps.contains { $0.path == wrapperPath },
                       "A wrapper folder containing exactly one app isn't launchable itself — only the real app should appear")
        XCTAssertTrue(result.apps.contains { $0.path == appPath && !$0.isFolder })
    }

    func testWrapperFolderWithMultipleAppsBecomesASyntheticFolder() {
        let app1 = makeFakeApp(at: "Office Suite/Writer.app")
        let app2 = makeFakeApp(at: "Office Suite/Spreadsheet.app")
        let wrapperPath = (tempRoot as NSString).appendingPathComponent("Office Suite")

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        guard let folderEntry = result.apps.first(where: { $0.path == wrapperPath }) else {
            return XCTFail("Folder containing 2+ apps should be surfaced as a synthetic in-launcher folder")
        }
        XCTAssertTrue(folderEntry.isFolder)
        XCTAssertEqual(Set(folderEntry.containedApps ?? []), Set([app1, app2]))
    }

    func testEmptyWrapperFolderProducesNoEntry() {
        let emptyFolder = (tempRoot as NSString).appendingPathComponent("Empty Folder")
        try? FileManager.default.createDirectory(atPath: emptyFolder, withIntermediateDirectories: true)

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        XCTAssertFalse(result.apps.contains { $0.path == emptyFolder })
    }

    func testFolderThatIsItselfAConfiguredScanDirectoryIsNotAlsoWrappedAsAFolder() {
        // Mirrors "/Applications/Utilities" being both a plain child of "/Applications" and its
        // own configured scan directory — its apps should appear once each, not once individually
        // and once more bundled inside a synthetic "Utilities" folder.
        let utilitiesDir = (tempRoot as NSString).appendingPathComponent("Utilities")
        let app1 = makeFakeApp(at: "Utilities/Terminal.app")
        let app2 = makeFakeApp(at: "Utilities/Activity Monitor.app")

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot, utilitiesDir])

        XCTAssertFalse(result.apps.contains { $0.path == utilitiesDir },
                       "A directory that's itself a configured scan root shouldn't also be synthesized as a wrapper folder")
        XCTAssertEqual(result.apps.filter { $0.path == app1 }.count, 1)
        XCTAssertEqual(result.apps.filter { $0.path == app2 }.count, 1)
    }

    func testRegularAppBundleStillRequiresItsOwnContentsDirectory() {
        // A directory named "Broken.app" with no Contents inside is not a valid bundle — should
        // be skipped, not surfaced as a launchable app.
        let brokenAppPath = (tempRoot as NSString).appendingPathComponent("Broken.app")
        try? FileManager.default.createDirectory(atPath: brokenAppPath, withIntermediateDirectories: true)

        let result = ApplicationScanner.shared.scanDirectories(directories: [tempRoot])

        XCTAssertFalse(result.apps.contains { $0.path == brokenAppPath })
    }
}
