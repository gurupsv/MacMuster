import XCTest
@testable import MacMuster

/// Covers **SEC-4**: custom scan directories were validated only when added, and the symlink test
/// used to reject far more than symlinks.
@MainActor
final class CustomDirectoryValidationTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        // Deliberately under the system temp directory, which lives behind /var -> /private/var.
        // That symlinked *ancestor* is the false-negative case this fix is about.
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CustomDirValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    // MARK: - The false negative

    func testDirectoryBehindASymlinkedAncestorIsAccepted() throws {
        // Build a real symlinked *ancestor*: linkdir -> realdir, then validate linkdir/Apps.
        // (Not /var, despite it being a link to /private/var: resolvingSymlinksInPath deliberately
        // leaves /private prefixes alone, so that case never exercised the old check.)
        //
        // The old check compared the whole path against resolvingSymlinksInPath and rejected any
        // difference — so an ordinary directory reached through a linked parent, such as an
        // external volume linked from the home folder, could not be added and said nothing about
        // why.
        let realDir = root.appendingPathComponent("realdir", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realDir.appendingPathComponent("Apps", isDirectory: true), withIntermediateDirectories: true)
        let linkDir = root.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: realDir)

        let throughLink = linkDir.appendingPathComponent("Apps", isDirectory: true).path
        XCTAssertNotEqual((throughLink as NSString).resolvingSymlinksInPath, throughLink,
            "Precondition: this path must genuinely sit behind a symlinked ancestor")

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(throughLink),
            "A real directory must not be rejected just because an ancestor is a symlink")
    }

    // MARK: - What must still be refused

    func testSymlinkAtThePathItselfIsRejected() throws {
        let realDir = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDir)

        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(link.path),
            "A symlink at the directory itself is the case worth refusing")
    }

    func testUnnormalizedPathsAreRejected() {
        // Refused rather than silently reinterpreted.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/Applications/"), "trailing slash")
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("//Applications"), "doubled slash")
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/Applications/.."), "parent traversal")
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/Applications/./Utilities"), "current-dir component")
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("relative/path"), "not absolute")
    }

    func testWorldWritableDirectoryIsRejected() throws {
        let open = root.appendingPathComponent("open", isDirectory: true)
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: open.path)

        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(open.path),
            "A world-writable directory can be filled with bundles by anyone")
    }

    func testOrdinaryDirectoriesAreStillAccepted() {
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/Applications"),
            "The standard install location must remain valid")
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/System/Applications"),
            "The system install location must remain valid")
    }

    func testNonExistentPathIsStillAccepted() {
        // An unmounted external volume is a legitimate configuration.
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/Volumes/NotMounted/Apps"),
            "A path that does not exist yet should stay valid")
    }

    func testPlainFileIsRejected() throws {
        let file = root.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(file.path),
            "A path that exists as a file is not a scan directory")
    }

    // MARK: - Re-validation at scan time

    func testScanDirectoriesRevalidateInsteadOfTrustingTheStoredList() throws {
        let dir = root.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let library = LibraryScanState()
        library.customDirectories = [dir.path]
        XCTAssertTrue(library.currentScanDirectories.contains(dir.path),
            "Precondition: a valid custom directory should be scanned")

        // Swap it for a symlink after it was accepted — the TOCTOU window.
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createSymbolicLink(at: dir, withDestinationURL: elsewhere)

        XCTAssertFalse(library.currentScanDirectories.contains(dir.path),
            "A directory replaced by a symlink after validation must not be scanned — this is SEC-4")
        library.cleanupTimerAndObservers()
    }

    func testDefaultDirectoriesAreNeverDroppedByRevalidation() {
        let library = LibraryScanState()
        for expected in ApplicationScanner.defaultScanDirectories {
            XCTAssertTrue(library.currentScanDirectories.contains(expected),
                "Default scan directory \(expected) must always be scanned — dropping one would empty the launcher")
        }
        library.cleanupTimerAndObservers()
    }
}
