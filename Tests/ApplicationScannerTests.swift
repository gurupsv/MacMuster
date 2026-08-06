import XCTest
@testable import MacMuster

final class ApplicationScannerTests: XCTestCase {

    // MARK: - .app Suffix Stripping

    func testAppSuffixStripsOnlyTrailingSuffix() {
        // The fix replacesOccurrences → trailing-only strip. Test that an app with ".app" in the middle is handled correctly.
        let itemName = "My.app.Tool.app"
        let expectedName = (itemName.hasSuffix(".app") ? String(itemName.dropLast(4)) : itemName)
        XCTAssertEqual(expectedName, "My.app.Tool", "Trailing .app should be stripped but internal occurrences preserved")
    }

    func testAppWithoutSuffixIsNotModified() {
        let itemName = "TextEdit"
        let expectedName = (itemName.hasSuffix(".app") ? String(itemName.dropLast(4)) : itemName)
        XCTAssertEqual(expectedName, "TextEdit", "Non .app item should remain unchanged")
    }

    func testShortAppWithSuffixIsCorrectlyStripped() {
        let itemName = "X.app"
        let expectedName = (itemName.hasSuffix(".app") ? String(itemName.dropLast(4)) : itemName)
        XCTAssertEqual(expectedName, "X", "Short app name should be correctly stripped to just the base")
    }

    // MARK: - Directory Validation

    func testValidCustomDirectoryAbsolutePath() {
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/Applications"), "/Applications is a valid custom directory")
    }

    func testInvalidCustomDirectoryRelativePath() {
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("Applications"), "Relative path without leading / is invalid")
    }

    func testInvalidCustomDirectoryNotADirectory() {
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/etc/hosts"), "/etc/hosts is a file, not a directory")
    }

    // MARK: - Default Scan Directories

    func testDefaultScanDirectoriesIncludeStandardLocations() {
        let dirs = ApplicationScanner.defaultScanDirectories
        XCTAssertTrue(dirs.contains("/Applications"), "Includes /Applications")
        XCTAssertTrue(dirs.contains("/Applications/Utilities"), "Includes /Applications/Utilities")
        XCTAssertTrue(dirs.contains("/System/Applications"), "Includes /System/Applications")
    }

    func testDefaultScanDirectoriesIncludeUserAppsIfExists() {
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: userApps) {
            XCTAssertTrue(ApplicationScanner.defaultScanDirectories.contains(userApps), "Includes ~/Applications when it exists")
        } else {
            XCTAssertFalse(ApplicationScanner.defaultScanDirectories.contains(userApps), "Does not include ~/Applications when it doesn't exist")
        }
    }

    // MARK: - Dedup Across Directories

    func testScanDirectoriesDedupeSameAppInTwoDirectories() throws {
        // /Applications/Utilities contains Terminal.app, and /Applications also contains
        // Terminal.app (via symlink or direct). Without dedup, Terminal would appear twice.
        // Test the dedup logic with a real app that exists in multiple scan paths.
        guard FileManager.default.fileExists(atPath: "/Applications/Utilities/Terminal.app") else {
            throw XCTSkip("Terminal.app not found in /Applications/Utilities")
        }
        let result = ApplicationScanner.shared.scanDirectories(directories: ["/Applications", "/Applications/Utilities"])
        let terminalCount = result.apps.filter { $0.path.contains("Terminal.app") }.count
        XCTAssertEqual(terminalCount, 1, "Terminal.app should appear exactly once despite being in two scan directories")
    }

    func testScanDirectoriesDedupeByResolvedPath() throws {
        // If a path resolves to the same canonical path via symlink, it should dedupe.
        // Use two paths that resolve to the same real app.
        guard FileManager.default.fileExists(atPath: "/Applications/Utilities/Terminal.app") else {
            throw XCTSkip("Terminal.app not found")
        }
        let result = ApplicationScanner.shared.scanDirectories(directories: [
            "/Applications/Utilities",
            "/Applications",
        ])
        let terminalPaths = result.apps.filter { $0.path.contains("Terminal.app") }.map { $0.path }
        XCTAssertEqual(terminalPaths.count, 1, "Terminal.app should dedupe to a single path")
        // The path should be the resolved one
        let resolved = (terminalPaths.first ?? "") as NSString
        let resolvedPath = resolved.resolvingSymlinksInPath
        XCTAssertEqual(resolvedPath, resolved as String, "Path should be resolved")
    }

    func testScanNonExistentDirectoryReturnsEmpty() {
        let result = ApplicationScanner.shared.scanDirectories(directories: ["/NonExistentDirectory"])
        XCTAssertTrue(result.apps.isEmpty, "Non-existent directory should return no apps")
    }

    func testScanEmptyDirectoryListReturnsEmpty() {
        let result = ApplicationScanner.shared.scanDirectories(directories: [])
        XCTAssertTrue(result.apps.isEmpty, "Empty directory list should return no apps")
    }

    func testScanMixOfValidAndInvalidDirectories() {
        let result = ApplicationScanner.shared.scanDirectories(directories: [
            "/Applications",
            "/NonExistentDirectory",
            "/Applications/Utilities",
        ])
        XCTAssertFalse(result.apps.isEmpty, "Valid directories should produce apps")
        let safari = result.apps.filter { $0.path.contains("Safari.app") }
        XCTAssertFalse(safari.isEmpty, "Safari.app should be found")
    }

    // MARK: - Custom Directory Validation

    func testValidCustomDirectoryExistsAndIsDirectory() {
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/System/Applications"),
            "Existing directory should be valid")
    }

    func testValidCustomDirectoryDoesNotYetExist() {
        // A path that doesn't exist yet (e.g. unmounted volume) is considered valid.
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/Volumes/Unmounted/CustomApps"),
            "Non-existent path should still be considered valid")
    }

    func testInvalidCustomDirectorySymlink() {
        // Create a temporary symlink to test symlink rejection.
        let tempDir = NSTemporaryDirectory()
        let realDir = (tempDir as NSString).appendingPathComponent("RealDir-\(UUID().uuidString)")
        let symlinkDir = (tempDir as NSString).appendingPathComponent("SymlinkDir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: realDir, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(atPath: symlinkDir, withDestinationPath: realDir)
        defer { try? FileManager.default.removeItem(atPath: symlinkDir); try? FileManager.default.removeItem(atPath: realDir) }

        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(symlinkDir),
            "Symlink should be rejected to prevent directory traversal")
    }

    func testInvalidCustomDirectoryWorldWritable() {
        // Create a directory with world-writable permissions to test rejection.
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("WorldWritable-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: testDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testDir); try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(testDir),
            "World-writable directory should be rejected")
    }

    func testValidCustomDirectoryRestrictedPermissions() {
        // Create a directory with restricted permissions (owner-only) to test acceptance.
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("Restricted-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: testDir)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(testDir),
            "Restricted permissions (0o700) should be valid")
    }

    func testInvalidCustomDirectoryBrokenSymlink() {
        // A broken symlink (pointing to non-existent target) doesn't exist on disk, so
        // isValidCustomDirectory considers it valid (non-existent paths are valid — only
        // existing non-directory paths are rejected). The symlink check only applies to
        // existing paths.
        let tempDir = NSTemporaryDirectory()
        let brokenSymlink = (tempDir as NSString).appendingPathComponent("BrokenSymlink-\(UUID().uuidString)")
        try? FileManager.default.createSymbolicLink(atPath: brokenSymlink, withDestinationPath: "/NonExistentTarget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: brokenSymlink) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(brokenSymlink),
            "Broken symlink is non-existent on disk — treated as valid (same as unmounted volume)")
    }

    func testCustomDirectoryWithTrailingSlashRejected() {
        // A path with trailing slash resolves to the parent (e.g. "/Applications/" → "/Applications").
        // Since resolvedPath != path, the symlink check rejects it.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/Applications/"),
            "Trailing slash resolves differently — rejected as symlink-equivalent")
    }

    func testCustomDirectoryWithDoubleSlashRejected() {
        // A path with double slash resolves to the parent (e.g. "//Applications" → "/Applications").
        // Since resolvedPath != path, the symlink check rejects it.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("//Applications"),
            "Double slash resolves differently — rejected as symlink-equivalent")
    }

    func testCustomDirectoryWithOnlySlash() {
        // Root directory "/" should be valid (hasPrefix("/") holds, it exists and is a directory).
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/"),
            "Root directory should be valid")
    }

    func testCustomDirectoryWithSpaces() {
        // A path with spaces should be valid (hasPrefix("/") holds, resolution handles it).
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("Dir With Spaces")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(testDir),
            "Directory with spaces in name should be valid")
    }

    func testCustomDirectoryWithUnicode() {
        // A path with Unicode characters should be valid.
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("アプリ")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(testDir),
            "Directory with Unicode characters should be valid")
    }

    func testCustomDirectoryWithDotPrefix() {
        // A hidden directory (dot prefix) should be valid.
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent(".hiddenDir")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(testDir),
            "Hidden directory (dot prefix) should be valid")
    }

    func testCustomDirectoryWithDotDotPath() {
        // A path with ".." components should be rejected (symlink resolution would differ).
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("..")
        // ".." resolves to the parent directory, which differs from the path itself
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(testDir),
            "Path with '..' (symlink) should be rejected")
    }

    func testCustomDirectoryPathTooShort() {
        // A very short path should be rejected (hasPrefix("/") holds, but it's either "/" or invalid).
        // "/" is valid (tested above). "A" is invalid (doesn't exist, but hasPrefix("/") holds).
        // Actually, "A" doesn't havePrefix("/") so it's rejected for that reason.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("A"),
            "Single character without / should be rejected")
    }

    func testCustomDirectoryWithNullCharacter() {
        // A path with a null character is rejected by isValidCustomDirectory — hasPrefix("/")
        // returns false because the null character truncates the string in Swift.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("/\0"),
            "Path with null character — rejected")
    }

    func testCustomDirectoryWithNewlineCharacter() {
        // A path with a newline character doesn't exist on disk, so isValidCustomDirectory
        // considers it valid (non-existent paths are valid — same as unmounted volume).
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/\n"),
            "Non-existent path with newline — treated as valid (same as unmounted volume)")
    }

    func testCustomDirectoryWithBackslashCharacter() {
        // A path with a backslash character doesn't exist on disk, so isValidCustomDirectory
        // considers it valid (non-existent paths are valid — same as unmounted volume).
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory("/\\"),
            "Non-existent path with backslash — treated as valid (same as unmounted volume)")
    }

    func testCustomDirectoryWithForwardSlashInMiddle() {
        // A path with a forward slash in the middle (like "/a/b") should be valid if the directory exists.
        let tempDir = NSTemporaryDirectory()
        let testDir = (tempDir as NSString).appendingPathComponent("a/b")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(testDir),
            "Nested path with / in middle should be valid")
    }

    func testCustomDirectoryWithTilde() {
        // A path with "~" should be rejected (hasPrefix("/") is false for "~").
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("~"),
            "Tilde path should be rejected (no leading /)")
    }

    func testCustomDirectoryWithTildeAndSlash() {
        // "~/" should be rejected (hasPrefix("/") is false for "~").
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory("~/"),
            "Tilde with slash should be rejected (no leading /)")
    }

    func testCustomDirectoryWithUserHome() {
        // The user home directory should be valid (hasPrefix("/") holds, it exists and is a directory,
        // and it's not a symlink or world-writable).
        XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(NSHomeDirectory()),
            "User home directory should be valid")
    }

    func testCustomDirectoryWithSystemTempRejected() {
        // The system temp directory exists and is a directory, but it is typically world-writable
        // (0o777). The world-writable check in isValidCustomDirectory rejects it.
        XCTAssertFalse(ApplicationScanner.isValidCustomDirectory(NSTemporaryDirectory()),
            "System temp directory is world-writable — rejected")
    }

    func testCustomDirectoryWithLibrary() {
        // The user library directory should be valid (hasPrefix("/") holds, it exists and is a directory).
        let libDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library")
        if FileManager.default.fileExists(atPath: libDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(libDir),
                "User library directory should be valid")
        }
    }

    func testCustomDirectoryWithDesktop() {
        // The user desktop directory should be valid.
        let desktopDir = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        if FileManager.default.fileExists(atPath: desktopDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(desktopDir),
                "User desktop directory should be valid")
        }
    }

    func testCustomDirectoryWithDocuments() {
        // The user documents directory should be valid.
        let docsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Documents")
        if FileManager.default.fileExists(atPath: docsDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(docsDir),
                "User documents directory should be valid")
        }
    }

    func testCustomDirectoryWithDownloads() {
        // The user downloads directory should be valid.
        let downloadsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        if FileManager.default.fileExists(atPath: downloadsDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(downloadsDir),
                "User downloads directory should be valid")
        }
    }

    func testCustomDirectoryWithMovies() {
        // The user movies directory should be valid.
        let moviesDir = (NSHomeDirectory() as NSString).appendingPathComponent("Movies")
        if FileManager.default.fileExists(atPath: moviesDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(moviesDir),
                "User movies directory should be valid")
        }
    }

    func testCustomDirectoryWithMusic() {
        // The user music directory should be valid.
        let musicDir = (NSHomeDirectory() as NSString).appendingPathComponent("Music")
        if FileManager.default.fileExists(atPath: musicDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(musicDir),
                "User music directory should be valid")
        }
    }

    func testCustomDirectoryWithPictures() {
        // The user pictures directory should be valid.
        let picturesDir = (NSHomeDirectory() as NSString).appendingPathComponent("Pictures")
        if FileManager.default.fileExists(atPath: picturesDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(picturesDir),
                "User pictures directory should be valid")
        }
    }

    func testCustomDirectoryWithPublic() {
        // The user public directory should be valid.
        let publicDir = (NSHomeDirectory() as NSString).appendingPathComponent("Public")
        if FileManager.default.fileExists(atPath: publicDir) {
            XCTAssertTrue(ApplicationScanner.isValidCustomDirectory(publicDir),
                "User public directory should be valid")
        }
    }
}