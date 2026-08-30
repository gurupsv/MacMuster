import XCTest
@testable import MacMuster

/// Covers the scanner group: **SEC-2**, **PERF-2**, **PERF-5** and **BUG-4**.
///
/// These use real directories and real symlinks rather than fixtures, because every one of the
/// defects was about what the filesystem actually reports back — a string-level prefix test, a
/// directory read that could never succeed, a link the walk followed twice, and an mtime that was
/// silently replaced with the current time.
final class ScannerHardeningTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    private func makeBundle(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
    }

    private func app(path: String, isFolder: Bool = false) -> Application {
        Application(id: path, name: "X", path: path, installationDate: Date(), isFolder: isFolder)
    }

    // MARK: - SEC-2: the provenance badge must resist path tricks

    func testTraversalPathIsNotTreatedAsTrusted() {
        // "/Applications/../tmp/Fake.app" carries the trusted prefix as a plain string.
        let sneaky = app(path: "/Applications/../tmp/Fake.app")
        XCTAssertFalse(sneaky.isFromTrustedLocation,
            "A path that only *starts* with /Applications after traversal must not read as trusted")
    }

    func testSymlinkedBundleIsJudgedByItsRealLocation() throws {
        // A link under a trusted-looking name pointing at a bundle somewhere else entirely.
        let realBundle = root.appendingPathComponent("Impostor.app", isDirectory: true)
        try makeBundle(at: realBundle)
        let linkDir = root.appendingPathComponent("linkdir", isDirectory: true)
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realBundle)

        let linked = app(path: link.path)
        XCTAssertEqual(linked.resolvedPath, DirectoryWatcher.canonicalPath(realBundle.path),
            "resolvedPath should follow the link to where the bundle really is")
        XCTAssertFalse(linked.isFromTrustedLocation, "A symlinked bundle outside /Applications is not trusted")
    }

    func testGenuinelyTrustedPathsStillReadAsTrusted() throws {
        XCTAssertTrue(app(path: "/System/Applications/Calculator.app").isFromTrustedLocation,
            "A real system app must still be trusted — the fix must not flag everything")
    }

    func testCryptexRelocatedSystemAppsStayTrusted() throws {
        // Regression guard for the trap this fix walked into: on current macOS
        // /Applications/Safari.app resolves to
        // /System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app. Resolving paths
        // without allowing for that flags Safari as an impostor.
        guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else {
            throw XCTSkip("Safari not present on this machine")
        }
        XCTAssertTrue(app(path: "/Applications/Safari.app").isFromTrustedLocation,
            "Safari must stay trusted even though it resolves into the OS cryptex")
    }

    func testAnAppStillInPlainApplicationsStaysTrusted() throws {
        // A non-cryptex app that really does live in /Applications.
        guard let real = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications"))?
            .first(where: { $0.hasSuffix(".app") && !$0.hasPrefix("Safari") }) else {
            throw XCTSkip("No app available in /Applications")
        }
        XCTAssertTrue(app(path: "/Applications/\(real)").isFromTrustedLocation,
            "\(real) lives in /Applications and must read as trusted")
    }

    func testUserApplicationsIsStillFlagged() {
        let home = NSHomeDirectory()
        XCTAssertFalse(app(path: "\(home)/Applications/Thing.app").isFromTrustedLocation,
            "~/Applications is outside the vetted locations and should stay flagged")
    }

    func testFolderEntriesAreNeverFlagged() {
        // Folder entries carry a UUID in `path`, not a filesystem location.
        let folder = app(path: UUID().uuidString, isFolder: true)
        XCTAssertTrue(folder.isFromTrustedLocation, "Synthetic folder entries have no install location to distrust")
        XCTAssertNil(folder.provenanceWarning, "A folder should carry no provenance warning")
    }

    func testProvenanceWarningNamesTheRealLocation() throws {
        let realBundle = root.appendingPathComponent("Elsewhere.app", isDirectory: true)
        try makeBundle(at: realBundle)
        let link = root.appendingPathComponent("Innocent.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realBundle)

        let warning = try XCTUnwrap(app(path: link.path).provenanceWarning)
        XCTAssertTrue(warning.contains(DirectoryWatcher.canonicalPath(realBundle.deletingLastPathComponent().path) ?? ""),
            "The warning should name where the bundle really lives, not where the link sat: \(warning)")
    }

    // MARK: - PERF-2: nested-app discovery

    func testNestedAppsInsideBundleAreStillFound() throws {
        // The case the scan of a bundle's interior actually exists for (Xcode ships Simulator.app
        // under Contents/Developer/Applications).
        let outer = root.appendingPathComponent("Outer.app", isDirectory: true)
        let nestedDir = outer.appendingPathComponent("Contents/Developer/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let inner = nestedDir.appendingPathComponent("Inner.app", isDirectory: true)
        try makeBundle(at: inner)

        let found = ApplicationScanner.shared.findContainedApps(in: outer.path)
        XCTAssertEqual(found?.count, 1, "A nested app under Contents/Developer/Applications should be found")
        // Compared canonically: the temp directory sits behind /var -> /private/var, and the
        // enumeration reports the resolved form.
        XCTAssertEqual(found?.first.flatMap { DirectoryWatcher.canonicalPath($0) },
                       DirectoryWatcher.canonicalPath(inner.path),
                       "The nested app's path should be returned")
    }

    func testContentsApplicationsIsAlsoSearched() throws {
        let outer = root.appendingPathComponent("Outer2.app", isDirectory: true)
        let nestedDir = outer.appendingPathComponent("Contents/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try makeBundle(at: nestedDir.appendingPathComponent("Helper.app", isDirectory: true))

        XCTAssertEqual(ApplicationScanner.shared.findContainedApps(in: outer.path)?.count, 1,
            "Contents/Applications should be searched as well")
    }

    func testAnOrdinaryBundleReportsNoNestedApps() throws {
        let plain = root.appendingPathComponent("Plain.app", isDirectory: true)
        try makeBundle(at: plain)
        XCTAssertNil(ApplicationScanner.shared.findContainedApps(in: plain.path),
            "An ordinary bundle has nothing nested to report")
    }

    func testNonDirectoryEntriesAreNotReportedAsNestedApps() throws {
        // A *file* named Foo.app is not a bundle and must not be surfaced as one.
        let outer = root.appendingPathComponent("Outer3.app", isDirectory: true)
        let nestedDir = outer.appendingPathComponent("Contents/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try Data("not a bundle".utf8).write(to: nestedDir.appendingPathComponent("Fake.app"))

        XCTAssertNil(ApplicationScanner.shared.findContainedApps(in: outer.path),
            "A plain file named *.app is not a nested bundle")
    }

    // MARK: - PERF-5: the plain-folder walk must not re-traverse through links

    func testPlainFolderWalkTerminatesOnASymlinkCycle() throws {
        // A folder containing a link back to itself. Without a visited-set this re-walks the same
        // tree until the depth limit; the test would still finish, but it must not report the same
        // bundle over and over.
        let vendor = root.appendingPathComponent("Vendor", isDirectory: true)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try makeBundle(at: vendor.appendingPathComponent("Tool.app", isDirectory: true))
        try FileManager.default.createSymbolicLink(
            at: vendor.appendingPathComponent("loop"), withDestinationURL: vendor)

        // Asserted against the walk itself, not through scanDirectories: that method dedupes by
        // resolved path, so it reports one Tool.app either way and cannot tell a bounded walk from
        // one that re-traversed the tree at every depth.
        let walked = ApplicationScanner.shared.findAppsInPlainFolder(at: vendor.path)

        XCTAssertEqual(walked?.count, 1,
            "The self-referencing link must not be descended into: got \(walked ?? [])")

        // And the end-to-end result stays correct too.
        let result = ApplicationScanner.shared.scanDirectories(directories: [root.path])
        XCTAssertEqual(result.apps.filter { $0.name == "Tool" }.count, 1,
            "A symlink cycle must not surface the same app repeatedly")
    }

    func testWalkDoesNotDescendThroughSymlinkedDirectories() throws {
        // The structural reason cycles cannot happen. A link to a directory full of apps is not
        // followed — vendor folders keep their apps in real subdirectories.
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try makeBundle(at: elsewhere.appendingPathComponent("Hidden.app", isDirectory: true))

        let vendor = root.appendingPathComponent("Vendor3", isDirectory: true)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: vendor.appendingPathComponent("link"), withDestinationURL: elsewhere)

        let walked = ApplicationScanner.shared.findAppsInPlainFolder(at: vendor.path) ?? []
        XCTAssertFalse(walked.contains { $0.hasSuffix("Hidden.app") },
            "A symlinked directory must not be walked into: got \(walked)")
    }

    func testPlainFolderWalkStillFindsNestedVendorApps() throws {
        // The real case: "Vendor/Sub/Thing.app" should still be discovered.
        let sub = root.appendingPathComponent("Vendor2/Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try makeBundle(at: sub.appendingPathComponent("Deep.app", isDirectory: true))

        let result = ApplicationScanner.shared.scanDirectories(directories: [root.path])
        XCTAssertTrue(result.apps.contains { $0.name == "Deep" },
            "An app nested inside a plain vendor folder should still be found")
    }

    // MARK: - BUG-4: an unreadable mtime must not read as "just updated"

    func testScannedAppsCarryARealModificationDate() throws {
        let bundle = root.appendingPathComponent("Dated.app", isDirectory: true)
        try makeBundle(at: bundle)
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: bundle.path)

        let result = ApplicationScanner.shared.scanDirectories(directories: [root.path])
        let dated = try XCTUnwrap(result.apps.first { $0.name == "Dated" })

        XCTAssertEqual(Int(dated.installationDate.timeIntervalSince1970), Int(past.timeIntervalSince1970),
            "The bundle's real mtime should be reported")
        XCTAssertLessThan(dated.installationDate, Date().addingTimeInterval(-60),
            "A scanned app must not be stamped with the current time — that re-badges it as updated on every scan")
    }

    func testScanIsStableAcrossRepeatedRuns() throws {
        // The Date() fallback made repeated scans disagree about installationDate, which drove
        // both the spurious update badge and an unstable date sort.
        try makeBundle(at: root.appendingPathComponent("Stable.app", isDirectory: true))

        let first = ApplicationScanner.shared.scanDirectories(directories: [root.path])
        let second = ApplicationScanner.shared.scanDirectories(directories: [root.path])

        let a = try XCTUnwrap(first.apps.first { $0.name == "Stable" }).installationDate
        let b = try XCTUnwrap(second.apps.first { $0.name == "Stable" }).installationDate
        XCTAssertEqual(a, b, "Two scans of an unchanged bundle must report the same installation date")
    }
}
