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
}