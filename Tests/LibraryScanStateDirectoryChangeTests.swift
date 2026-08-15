import XCTest
@testable import MacMuster

/// Covers `LibraryScanState.allScanDirectories`'s `didSet`: it must not invalidate every display
/// cache on a redundant assignment, and a real add/remove of a custom directory must rescan right
/// away rather than waiting out the 1s FSEvents settle delay meant for filesystem churn.
@MainActor
final class LibraryScanStateDirectoryChangeTests: XCTestCase {

    private var library: LibraryScanState!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        library = LibraryScanState()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        library.cleanupTimerAndObservers()
        library = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        let keys = [
            "appFolders", "hiddenAppPaths", "customDirectories", "customDirectoryBookmarks",
            "currentFolderId", "customOrder", "sortOption", "columnCount", "iconSize",
            "refreshInterval", "fontFamily", "fontSize", "fontWeight", "glowEnabled",
            "glowColor", "glowIntensity", "glowWidth", "overlayOpacity", "showFoldersFirst",
            "hasShownLauncher", "recentAppsEnabled", "pressFeedbackEnabled",
            "recentAppLaunchTimes", "appLaunchCounts", "presentationMode", "tintColor",
            "tintStrength", "showHiddenApps"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// A real, owned, non-symlinked directory under the system temp dir — `isValidCustomDirectory`
    /// rejects symlinks, and the raw temp path resolves through one on macOS (`/var` → `/private/var`).
    private func makeTestDirectory() -> String {
        let tempRoot = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        let testDir = (tempRoot as NSString).appendingPathComponent("MacMusterDirChangeTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// A minimal but valid `.app` bundle: `ApplicationScanner` requires a `Contents` subdirectory
    /// or it treats the bundle as broken and skips it.
    private func makeAppBundle(named name: String, in directory: String) throws -> String {
        let bundlePath = (directory as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            atPath: (bundlePath as NSString).appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        return bundlePath
    }

    private func pollUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - Redundant assignments must not invalidate caches

    func testReassigningAllScanDirectoriesToTheSameValueDoesNotBumpDataVersion() {
        library.isLoading = false
        let unchanged = library.allScanDirectories
        let versionBefore = library.dataVersion

        library.allScanDirectories = unchanged

        XCTAssertEqual(library.dataVersion, versionBefore,
            "Assigning the same directory list must not invalidate every display cache")
    }

    func testAssigningTheSameCustomDirectoriesDoesNotBumpDataVersion() async throws {
        library.isLoading = false
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }
        let appBundle = try makeAppBundle(named: "PollTester.app", in: testDir)

        library.customDirectories = [testDir]
        let scanned = await pollUntil(timeout: 1.5) {
            self.library.displayOrder.contains { $0.path == appBundle }
        }
        XCTAssertTrue(scanned, "setup: the directory change should have scanned before testing the redundant re-set")

        let versionBefore = library.dataVersion
        library.customDirectories = [testDir]

        XCTAssertEqual(library.dataVersion, versionBefore,
            "Re-saving the same custom directories (e.g. reopening Settings) must not invalidate every display cache")
    }

    // MARK: - A real change rescans immediately, not after the FSEvents settle delay

    func testAddingACustomDirectoryScansWithoutWaitingForTheFileSystemSettleDelay() async throws {
        library.isLoading = false
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }
        let appBundle = try makeAppBundle(named: "NewlyAdded.app", in: testDir)

        library.addCustomDirectory(testDir)

        // `ScanMetrics.installSettleNanoseconds` is a full second; a directory add/remove is a
        // user action, not FSEvents churn, so it must not be gated behind that settle delay.
        let found = await pollUntil(timeout: 0.6) {
            self.library.displayOrder.contains { $0.path == appBundle }
        }
        XCTAssertTrue(found,
            "Adding a custom directory should rescan immediately, not wait out the 1s FSEvents settle delay")
    }

    func testRemovingACustomDirectoryRescansWithoutWaitingForTheFileSystemSettleDelay() async throws {
        library.isLoading = false
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }
        let appBundle = try makeAppBundle(named: "ToBeRemoved.app", in: testDir)

        library.addCustomDirectory(testDir)
        let added = await pollUntil(timeout: 1.5) {
            self.library.displayOrder.contains { $0.path == appBundle }
        }
        XCTAssertTrue(added, "setup: the app should be visible before testing its removal")

        library.removeCustomDirectory(testDir)

        let removed = await pollUntil(timeout: 0.6) {
            !self.library.displayOrder.contains { $0.path == appBundle }
        }
        XCTAssertTrue(removed,
            "Removing a custom directory should rescan immediately, not wait out the 1s FSEvents settle delay")
    }
}
