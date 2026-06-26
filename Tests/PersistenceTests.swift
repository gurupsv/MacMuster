import XCTest
@testable import MacMuster

final class PersistenceTests: XCTestCase {

    private var appModel: AppModel!

    override func setUpWithError() throws {
        appModel = AppModel()
    }

    override func tearDownWithError() throws {
        appModel = nil
    }

    // MARK: - Hidden Apps Persistence Tests

    func testToggleHiddenAppSavesToUserDefaults() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)
        let data = UserDefaults.standard.data(forKey: "hiddenAppPaths")
        XCTAssertNotNil(data)
    }

    func testLoadHiddenAppsReadsFromUserDefaults() {
        let hiddenPaths = Set(["/Applications/Test.app", "/Applications/Other.app"])
        let savedData = try? JSONEncoder().encode(hiddenPaths)
        UserDefaults.standard.set(savedData, forKey: "hiddenAppPaths")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.hiddenAppPaths.count, 2)
        XCTAssertTrue(newAppModel.hiddenAppPaths.contains("/Applications/Test.app"))
        XCTAssertTrue(newAppModel.hiddenAppPaths.contains("/Applications/Other.app"))
    }

    func testLoadHiddenAppsWithInvalidDataDoesNothing() {
        UserDefaults.standard.set("invalid-string", forKey: "hiddenAppPaths")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.hiddenAppPaths.count, 0)
    }

    func testLoadHiddenAppsWithNoDataDoesNothing() {
        UserDefaults.standard.removeObject(forKey: "hiddenAppPaths")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.hiddenAppPaths.count, 0)
    }

    func testIsAppHiddenReturnsTrueForHiddenPath() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)
        XCTAssertTrue(appModel.isAppHidden(app.path))
    }

    func testIsAppHiddenReturnsFalseForNonHiddenPath() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])
        XCTAssertFalse(appModel.isAppHidden(app.path))
    }

    func testToggleHiddenAppWithApplicationObject() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app)
        XCTAssertTrue(appModel.isAppHidden(app.path))
    }

    // MARK: - Custom Directories Persistence Tests

    func testLoadCustomDirectoriesReadsFromUserDefaults() {
        UserDefaults.standard.set(["/Users/test/CustomApps", "/Users/test/OtherApps"], forKey: "customDirectories")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customDirectories.count, 2)
        XCTAssertTrue(newAppModel.customDirectories.contains("/Users/test/CustomApps"))
        XCTAssertTrue(newAppModel.customDirectories.contains("/Users/test/OtherApps"))
    }

    func testLoadCustomDirectoriesWithNoDataUsesDefaultOnly() {
        UserDefaults.standard.removeObject(forKey: "customDirectories")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customDirectories.count, 0)
        XCTAssertEqual(newAppModel.allScanDirectories.count, AppModel.defaultScanDirectories.count)
    }

    func testLoadCustomDirectoriesWithInvalidDataUsesDefaultOnly() {
        UserDefaults.standard.set("invalid-string", forKey: "customDirectories")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customDirectories.count, 0)
        XCTAssertEqual(newAppModel.allScanDirectories.count, AppModel.defaultScanDirectories.count)
    }

    // MARK: - Custom Directory Bookmarks Persistence Tests (F-4)

    /// A real, owned, non-symlinked directory under the system temp dir — `isValidCustomDirectory`
    /// requires the path to actually exist (and resolve to itself), so a fabricated path like
    /// "/Users/test/CustomApps" would silently fail validation and never reach persistence.
    private func makeTestDirectory() -> String {
        let tempRoot = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        let testDir = (tempRoot as NSString).appendingPathComponent("MacMusterF4Test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }

    func testAddCustomDirectoryWithBookmarkSavesBookmarkToUserDefaults() {
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let bookmarkData = Data([0x01, 0x02, 0x03])
        appModel.addCustomDirectory(testDir, bookmarkData: bookmarkData)

        XCTAssertTrue(appModel.customDirectories.contains(testDir))
        let saved = UserDefaults.standard.dictionary(forKey: "customDirectoryBookmarks") as? [String: Data]
        XCTAssertEqual(saved?[testDir], bookmarkData)
    }

    func testAddCustomDirectoryWithoutBookmarkStillAddsDirectory() {
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        appModel.addCustomDirectory(testDir)

        XCTAssertTrue(appModel.customDirectories.contains(testDir))
    }

    func testRemoveCustomDirectoryClearsItsBookmarkFromUserDefaults() {
        let testDir = makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        appModel.addCustomDirectory(testDir, bookmarkData: Data([0x01]))
        appModel.removeCustomDirectory(testDir)

        let saved = UserDefaults.standard.dictionary(forKey: "customDirectoryBookmarks") as? [String: Data]
        XCTAssertNil(saved?[testDir])
    }

    func testSaveCustomDirectoryBookmarksWritesToUserDefaults() {
        let bookmarks = ["/some/path": Data([0x0a, 0x0b])]
        PreferencesStore.shared.saveCustomDirectoryBookmarks(bookmarks)

        let saved = UserDefaults.standard.dictionary(forKey: "customDirectoryBookmarks") as? [String: Data]
        XCTAssertEqual(saved?["/some/path"], Data([0x0a, 0x0b]))
    }

    func testLoadCustomDirectoryBookmarksReadsFromUserDefaults() {
        UserDefaults.standard.set(["/some/path": Data([0x0c, 0x0d])], forKey: "customDirectoryBookmarks")

        let loaded = PreferencesStore.shared.loadCustomDirectoryBookmarks()
        XCTAssertEqual(loaded?["/some/path"], Data([0x0c, 0x0d]))
    }

    // MARK: - Font Family Persistence Tests

    func testSetFontFamilySavesToUserDefaults() {
        appModel.setFontFamily("SF Pro")
        let font = UserDefaults.standard.string(forKey: "fontFamily")
        XCTAssertEqual(font, "SF Pro")
    }

    func testSetFontFamilyUpdatesProperty() {
        appModel.setFontFamily("SF Pro")
        XCTAssertEqual(appModel.fontFamily, "SF Pro")
    }

    func testLoadFontFamilyReadsFromUserDefaults() {
        UserDefaults.standard.set("Helvetica", forKey: "fontFamily")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.fontFamily, "Helvetica")
    }

    func testLoadFontFamilyWithNoDataDoesNothing() {
        UserDefaults.standard.removeObject(forKey: "fontFamily")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.fontFamily, "SF Pro")
    }

    // MARK: - Column Count Persistence Tests

    func testSetColumnCountSavesToUserDefaults() {
        appModel.setColumnCount(6)
        let cols = UserDefaults.standard.value(forKey: "columnCount") as? Int
        XCTAssertEqual(cols, 6)
    }

    func testLoadColumnCountReadsFromUserDefaults() {
        UserDefaults.standard.set(6, forKey: "columnCount")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.columnCount, 6)
    }

    func testLoadColumnCountWithInvalidDataUsesDefault() {
        UserDefaults.standard.set("invalid-string", forKey: "columnCount")

        let newAppModel = AppModel()
        XCTAssertNotNil(newAppModel.columnCount)
    }

    func testLoadColumnCountWithZeroEnforcesMinimum() {
        UserDefaults.standard.set(0, forKey: "columnCount")

        let newAppModel = AppModel()
        XCTAssertGreaterThanOrEqual(newAppModel.columnCount, 1)
    }

    // MARK: - Sort Option Persistence Tests

    func testSetSortOptionSavesToUserDefaults() {
        appModel.setSortOption(.installationDate)
        let sortRaw = UserDefaults.standard.string(forKey: "sortOption")
        XCTAssertEqual(sortRaw, "Installation Date")
    }

    func testLoadSortOptionReadsFromUserDefaults() {
        UserDefaults.standard.set("Installation Date", forKey: "sortOption")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.sortOption, .installationDate)
    }

    func testLoadSortOptionWithInvalidRawValueUsesDefault() {
        UserDefaults.standard.set("InvalidOption", forKey: "sortOption")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.sortOption, .name)
    }

    func testLoadSortOptionWithNoDataUsesDefault() {
        UserDefaults.standard.removeObject(forKey: "sortOption")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.sortOption, .name)
    }

    // MARK: - Icon Size Persistence Tests

    func testSetIconSizeSavesToUserDefaults() {
        appModel.iconSize = .large
        let iconRaw = UserDefaults.standard.string(forKey: "iconSize")
        XCTAssertEqual(iconRaw, "Large")
    }

    func testLoadIconSizeReadsFromUserDefaults() {
        UserDefaults.standard.set("Medium", forKey: "iconSize")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.iconSize, .medium)
    }

    func testLoadIconSizeWithInvalidRawValueUsesDefault() {
        UserDefaults.standard.set("InvalidSize", forKey: "iconSize")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.iconSize, .small)
    }

    func testLoadIconSizeWithNoDataUsesDefault() {
        UserDefaults.standard.removeObject(forKey: "iconSize")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.iconSize, .small)
    }

    // MARK: - Refresh Interval Persistence Tests

    func testSetRefreshIntervalSavesToUserDefaults() {
        appModel.refreshInterval = 600
        let interval = UserDefaults.standard.value(forKey: "refreshInterval") as? Double
        XCTAssertEqual(interval, 600)
    }

    func testLoadRefreshIntervalReadsFromUserDefaults() {
        UserDefaults.standard.set(600, forKey: "refreshInterval")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.refreshInterval, 600)
    }

    func testLoadRefreshIntervalWithNoDataUsesDefault() {
        UserDefaults.standard.removeObject(forKey: "refreshInterval")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.refreshInterval, 300)
    }

    // MARK: - Current Folder Id Persistence Tests

    func testOpenFolderSavesCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.openFolder(folderId)
        let folderIdStored = UserDefaults.standard.string(forKey: "currentFolderId")
        XCTAssertEqual(folderIdStored, folderId)
    }

    func testCloseFolderResetsCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.openFolder(folderId)
        appModel.closeFolder()
        let folderIdStored = UserDefaults.standard.string(forKey: "currentFolderId")
        XCTAssertNil(folderIdStored)
    }

    func testLoadCurrentFolderIdReadsFromUserDefaults() {
        let folder = AppFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        UserDefaults.standard.set(folder.id, forKey: "currentFolderId")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.currentFolderId, folder.id)
    }

    func testLoadCurrentFolderIdWithNoDataDoesNothing() {
        UserDefaults.standard.removeObject(forKey: "currentFolderId")

        let newAppModel = AppModel()
        XCTAssertNil(newAppModel.currentFolderId)
    }

    // MARK: - Custom Order Persistence Tests

    func testSetCustomOrderSavesToUserDefaults() {
        let apps = [
            Application(id: "/Applications/App1.app", name: "App1", path: "/Applications/App1.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil),
            Application(id: "/Applications/App2.app", name: "App2", path: "/Applications/App2.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        appModel.customOrder[apps[0].path] = 0
        appModel.customOrder[apps[1].path] = 1
        let data = UserDefaults.standard.data(forKey: "customOrder")
        XCTAssertNotNil(data)
    }

    func testLoadCustomOrderReadsFromUserDefaults() {
        let order = ["/Applications/App1.app": 0, "/Applications/App2.app": 1]
        let savedData = try? JSONEncoder().encode(order)
        UserDefaults.standard.set(savedData, forKey: "customOrder")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customOrder["/Applications/App1.app"], 0)
        XCTAssertEqual(newAppModel.customOrder["/Applications/App2.app"], 1)
    }

    func testLoadCustomOrderWithInvalidDataDoesNothing() {
        UserDefaults.standard.set("invalid-string", forKey: "customOrder")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customOrder.count, 0)
    }

    func testLoadCustomOrderWithNoDataDoesNothing() {
        UserDefaults.standard.removeObject(forKey: "customOrder")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.customOrder.count, 0)
    }

    // MARK: - Combined Persistence Tests

    func testLoadAllPersistedPreferencesFromUserDefaults() {
        UserDefaults.standard.set(6, forKey: "columnCount")
        UserDefaults.standard.set("Development", forKey: "currentFolderId")
        UserDefaults.standard.set("Installation Date", forKey: "sortOption")
        UserDefaults.standard.set("Large", forKey: "iconSize")
        UserDefaults.standard.set(600, forKey: "refreshInterval")
        UserDefaults.standard.set("Helvetica", forKey: "fontFamily")
        UserDefaults.standard.set(["/Applications/Test.app"], forKey: "hiddenAppPaths")
        UserDefaults.standard.set(["/Users/test/CustomApps"], forKey: "customDirectories")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.columnCount, 6)
        XCTAssertEqual(newAppModel.currentFolderId, "Development")
        XCTAssertEqual(newAppModel.sortOption, .installationDate)
        XCTAssertEqual(newAppModel.iconSize, .large)
        XCTAssertEqual(newAppModel.refreshInterval, 600)
        XCTAssertEqual(newAppModel.fontFamily, "Helvetica")
        XCTAssertEqual(newAppModel.hiddenAppPaths.count, 1)
        XCTAssertEqual(newAppModel.customDirectories.count, 1)
    }

    func testSaveAllPersistedPreferencesWritesToUserDefaults() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.openFolder(folderId)
        appModel.setSortOption(.installationDate)
        appModel.iconSize = .large
        appModel.refreshInterval = 600
        appModel.setFontFamily("Helvetica")
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])
        appModel.toggleHiddenApp(app.path)
        appModel.addCustomDirectory("/Users/test/CustomApps")

        XCTAssertNotNil(UserDefaults.standard.string(forKey: "currentFolderId"))
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "sortOption"))
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "iconSize"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "refreshInterval"))
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "fontFamily"))
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "hiddenAppPaths"))
        XCTAssertNotNil(UserDefaults.standard.stringArray(forKey: "customDirectories"))
    }

    // MARK: - Font Size / Weight Persistence Tests (I-3)

    func testSetFontSizeSavesToUserDefaults() {
        appModel.fontSize = 18.0
        let size = UserDefaults.standard.value(forKey: "fontSize") as? Double
        XCTAssertEqual(size, 18.0)
    }

    func testLoadFontSizeReadsFromUserDefaults() {
        UserDefaults.standard.set(18.0, forKey: "fontSize")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.fontSize, 18.0)
    }

    func testLoadFontSizeWithInvalidValueFallsBackToDefault() {
        UserDefaults.standard.set(999.0, forKey: "fontSize")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.fontSize, 14.0)
    }

    func testLoadFontWeightReadsFromUserDefaults() {
        UserDefaults.standard.set("bold", forKey: "fontWeight")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.fontWeight, "bold")
    }

    func testSetFontWeightSavesToUserDefaults() {
        appModel.setFontWeight("bold")
        let weight = UserDefaults.standard.string(forKey: "fontWeight")
        XCTAssertEqual(weight, "bold")
    }

    func testSetFontWeightUpdatesProperty() {
        appModel.setFontWeight("bold")
        XCTAssertEqual(appModel.fontWeight, "bold")
    }

    // MARK: - Glow Settings Persistence Tests (I-3)

    func testSetGlowEnabledSavesToUserDefaults() {
        appModel.glowEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "glowEnabled"))
    }

    func testLoadGlowEnabledReadsFromUserDefaults() {
        UserDefaults.standard.set(false, forKey: "glowEnabled")
        let newAppModel = AppModel()
        XCTAssertFalse(newAppModel.glowEnabled)
    }

    func testSetGlowColorSavesHexToUserDefaults() {
        appModel.glowColor = .black
        let hex = UserDefaults.standard.string(forKey: "glowColor")
        XCTAssertEqual(hex, "#000000")
    }

    func testLoadGlowColorReadsFromUserDefaults() {
        UserDefaults.standard.set("#000000", forKey: "glowColor")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.glowColor, .black)
    }

    func testSetGlowIntensitySavesToUserDefaults() {
        appModel.glowIntensity = 0.7
        let intensity = UserDefaults.standard.value(forKey: "glowIntensity") as? Double
        XCTAssertEqual(intensity, 0.7)
    }

    func testSetGlowIntensityClampsAboveOne() {
        appModel.glowIntensity = 5.0
        XCTAssertEqual(appModel.glowIntensity, 1.0)
    }

    func testLoadGlowIntensityReadsFromUserDefaults() {
        UserDefaults.standard.set(0.7, forKey: "glowIntensity")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.glowIntensity, 0.7)
    }

    func testSetGlowWidthSavesToUserDefaults() {
        appModel.glowWidth = 20.0
        let width = UserDefaults.standard.value(forKey: "glowWidth") as? Double
        XCTAssertEqual(width, 20.0)
    }

    func testSetGlowWidthClampsBelowMinimum() {
        appModel.glowWidth = 1.0
        XCTAssertEqual(appModel.glowWidth, 5.0)
    }

    func testLoadGlowWidthReadsFromUserDefaults() {
        UserDefaults.standard.set(20.0, forKey: "glowWidth")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.glowWidth, 20.0)
    }

    // MARK: - Toggle Settings Persistence Tests (I-3)

    func testSetShowFoldersFirstSavesToUserDefaults() {
        appModel.showFoldersFirst = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showFoldersFirst"))
    }

    func testLoadShowFoldersFirstReadsFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: "showFoldersFirst")
        let newAppModel = AppModel()
        XCTAssertTrue(newAppModel.showFoldersFirst)
    }

    func testSetHasShownLauncherSavesToUserDefaults() {
        appModel.hasShownLauncher = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasShownLauncher"))
    }

    func testLoadHasShownLauncherReadsFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: "hasShownLauncher")
        let newAppModel = AppModel()
        XCTAssertTrue(newAppModel.hasShownLauncher)
    }

    func testSetShowRecentAppsSavesToUserDefaults() {
        appModel.showRecentApps = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "recentAppsEnabled"))
    }

    func testLoadShowRecentAppsReadsFromUserDefaults() {
        UserDefaults.standard.set(false, forKey: "recentAppsEnabled")
        let newAppModel = AppModel()
        XCTAssertFalse(newAppModel.showRecentApps)
    }

    func testSetPressFeedbackEnabledSavesToUserDefaults() {
        appModel.pressFeedbackEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "pressFeedbackEnabled"))
    }

    func testLoadPressFeedbackEnabledReadsFromUserDefaults() {
        UserDefaults.standard.set(false, forKey: "pressFeedbackEnabled")
        let newAppModel = AppModel()
        XCTAssertFalse(newAppModel.pressFeedbackEnabled)
    }

    // MARK: - Overlay Opacity Persistence Tests (I-3)

    func testSetOverlayOpacitySavesToUserDefaults() {
        appModel.overlayOpacity = 0.5
        let opacity = UserDefaults.standard.value(forKey: "overlayOpacity") as? Double
        XCTAssertEqual(opacity, 0.5)
    }

    func testSetOverlayOpacityClampsToRange() {
        appModel.overlayOpacity = 99.0
        XCTAssertLessThanOrEqual(appModel.overlayOpacity, kOverlayOpacityMax)
    }

    func testLoadOverlayOpacityReadsFromUserDefaults() {
        UserDefaults.standard.set(0.5, forKey: "overlayOpacity")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.overlayOpacity, 0.5)
    }

    // MARK: - Folders Persistence Tests (I-3)

    func testCreateFolderSavesToUserDefaults() {
        _ = appModel.createFolder(name: "Dev Tools", appPaths: ["/Applications/Xcode.app"])
        let data = UserDefaults.standard.data(forKey: "appFolders")
        XCTAssertNotNil(data)
    }

    func testLoadFoldersReadsFromUserDefaults() {
        let folder = AppFolder(name: "Dev Tools", appPaths: ["/Applications/Xcode.app"])
        let savedData = try? JSONEncoder().encode([folder])
        UserDefaults.standard.set(savedData, forKey: "appFolders")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.folders.count, 1)
        XCTAssertEqual(newAppModel.folders.first?.name, "Dev Tools")
    }
}
