import XCTest
@testable import MacMuster

@MainActor
final class LibraryScanStateDebounceTests: XCTestCase {

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

    // MARK: - isScanning flag guards against overlapping scans

    func testRefreshDisplayOrderSetsAndClearsIsScanning() async {
        library.isLoading = false
        let app = Application(
            id: "/System/Applications/Calculator.app", name: "Calculator",
            path: "/System/Applications/Calculator.app", icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        await library.refreshDisplayOrder()

        XCTAssertFalse(library.isScanning, "isScanning should be false after refreshDisplayOrder completes")
    }

    func testRefreshDisplayOrderSkipsWhenAlreadyScanning() async {
        library.isLoading = false
        let app = Application(
            id: "/System/Applications/Calculator.app", name: "Calculator",
            path: "/System/Applications/Calculator.app", icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        library.setApplications([app])

        library.isScanning = true

        let versionBefore = library.dataVersion
        await library.refreshDisplayOrder()

        XCTAssertEqual(library.dataVersion, versionBefore, "dataVersion should not change when scan is skipped due to isScanning")
    }

    func testIsScanningGuardPreventsReentry() async {
        library.isLoading = false
        library.isScanning = true

        let versionBefore = library.dataVersion
        await library.refreshDisplayOrder()

        XCTAssertTrue(library.isScanning, "isScanning should remain true when guard prevents re-entry")
        XCTAssertEqual(library.dataVersion, versionBefore, "dataVersion should not change when scan is skipped")
    }
}
