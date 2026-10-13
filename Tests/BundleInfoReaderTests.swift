import XCTest
@testable import MacMuster

/// Covers `BundleInfoReader`: it must pull the two values from a real bundle, and fail soft —
/// no entry, never a crash — on a missing, oversized, or corrupt Info.plist.
final class BundleInfoReaderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleInfoReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    /// Creates `<root>/<bundleName>.app/Contents/Info.plist` with the given text, returning the
    /// bundle's path.
    private func makeBundle(_ bundleName: String, plist contents: String) throws -> String {
        let bundle = root.appendingPathComponent("\(bundleName).app", isDirectory: true)
        let contentsDir = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try contents.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        return bundle.path
    }

    // MARK: - Real bundle

    func testReadsARealBundle() throws {
        let path = "/System/Applications/Calculator.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Calculator.app not present on this machine")
        }
        let info = BundleInfoReader.readBundleInfo(forPaths: [path])
        XCTAssertEqual(info[path]?.bundleID, "com.apple.calculator",
            "The reader must pull CFBundleIdentifier from a real bundle's Info.plist")
        // Calculator ships no LSApplicationCategoryType; the field should be nil, not a bogus value.
        XCTAssertNil(info[path]?.lsCategory)
    }

    // MARK: - Happy path with controlled data

    func testReadsBothValuesFromAWellFormedPlist() throws {
        let path = try makeBundle("Sample", plist: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.sample</string>
            <key>LSApplicationCategoryType</key>
            <string>public.app-category.productivity</string>
        </dict>
        </plist>
        """)
        let info = BundleInfoReader.readBundleInfo(forPaths: [path])
        XCTAssertEqual(info[path]?.bundleID, "com.example.sample")
        XCTAssertEqual(info[path]?.lsCategory, "public.app-category.productivity")
    }

    // MARK: - Fails soft

    func testMissingPlistYieldsNoEntry() throws {
        // A bundle directory with a Contents folder but no Info.plist.
        let bundle = root.appendingPathComponent("Empty.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true)
        let info = BundleInfoReader.readBundleInfo(forPaths: [bundle.path])
        XCTAssertNil(info[bundle.path], "A bundle with no Info.plist must produce no entry")
    }

    func testOversizedPlistIsSkipped() throws {
        // Just over the cap; content is irrelevant — the size check must reject it before parsing.
        let huge = String(repeating: "a", count: WizardMetrics.maxInfoPlistReadBytes + 1)
        let path = try makeBundle("Huge", plist: huge)
        let info = BundleInfoReader.readBundleInfo(forPaths: [path])
        XCTAssertNil(info[path], "An Info.plist over the size cap must be skipped, not loaded")
    }

    /// Regression: the cap used to be a `stat` size check, which does not follow symlinks, while the
    /// read that followed does. A symlinked Info.plist reported its link size and then loaded the
    /// oversized target, bypassing the cap.
    func testSymlinkedOversizedPlistIsSkipped() throws {
        let bundle = root.appendingPathComponent("Linked.app", isDirectory: true)
        let contentsDir = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        // A valid plist padded past the cap, so rejecting it can only be the size limit.
        let padding = String(repeating: "a", count: WizardMetrics.maxInfoPlistReadBytes + 1)
        let target = root.appendingPathComponent("big-target.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.example.linked</string>
            <key>Padding</key><string>\(padding)</string>
        </dict></plist>
        """.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: contentsDir.appendingPathComponent("Info.plist"), withDestinationURL: target)

        let info = BundleInfoReader.readBundleInfo(forPaths: [bundle.path])
        XCTAssertNil(info[bundle.path], "A symlinked Info.plist must not bypass the size cap")
    }

    func testPlistExactlyAtCapIsStillRead() throws {
        // Boundary: the cap is inclusive, so a plist of exactly the cap size must parse.
        let head = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.edge</string></dict></plist>
        """
        let pad = WizardMetrics.maxInfoPlistReadBytes - head.utf8.count
        let path = try makeBundle("Edge", plist: head + String(repeating: " ", count: pad))
        XCTAssertEqual(BundleInfoReader.readBundleInfo(forPaths: [path])[path]?.bundleID, "com.example.edge")
    }

    func testGarbagePlistYieldsNoEntry() throws {
        let path = try makeBundle("Garbage", plist: "this is not a valid plist at all")
        let info = BundleInfoReader.readBundleInfo(forPaths: [path])
        XCTAssertNil(info[path], "A corrupt Info.plist must fail soft, not crash")
    }

    func testEmptyInputReturnsEmptyResult() {
        XCTAssertTrue(BundleInfoReader.readBundleInfo(forPaths: []).isEmpty)
    }
}
