import XCTest
@testable import MacMuster

@MainActor
final class FolderTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        appModel = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "appFolders")
        UserDefaults.standard.removeObject(forKey: "hiddenAppPaths")
        UserDefaults.standard.removeObject(forKey: "customDirectories")
        UserDefaults.standard.removeObject(forKey: "customDirectoryBookmarks")
        UserDefaults.standard.removeObject(forKey: "currentFolderId")
        UserDefaults.standard.removeObject(forKey: "customOrder")
        UserDefaults.standard.removeObject(forKey: "sortOption")
        UserDefaults.standard.removeObject(forKey: "columnCount")
        UserDefaults.standard.removeObject(forKey: "iconSize")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "fontFamily")
        UserDefaults.standard.removeObject(forKey: "fontSize")
        UserDefaults.standard.removeObject(forKey: "fontWeight")
        UserDefaults.standard.removeObject(forKey: "glowEnabled")
        UserDefaults.standard.removeObject(forKey: "glowColor")
        UserDefaults.standard.removeObject(forKey: "glowIntensity")
        UserDefaults.standard.removeObject(forKey: "glowWidth")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "showFoldersFirst")
        UserDefaults.standard.removeObject(forKey: "hasShownLauncher")
        UserDefaults.standard.removeObject(forKey: "recentAppsEnabled")
        UserDefaults.standard.removeObject(forKey: "pressFeedbackEnabled")
    }

    // MARK: - AppFolder Codable Tests

    func testAppFolderIsCodable() {
        let folder = AppFolder(name: "Development", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertNoThrow(try encoder.encode(folder))
        XCTAssertNoThrow(try decoder.decode(AppFolder.self, from: try encoder.encode(folder)))
    }

    func testAppFolderIdIsUUID() {
        let folder = AppFolder(name: "Test", appPaths: [])
        XCTAssertTrue(folder.id.count == 36)
        XCTAssertTrue(folder.id.contains("-"))
    }

    func testAppFolderCreatedAtAndModifiedAtAreCurrentDate() {
        let folder = AppFolder(name: "Test", appPaths: [])
        XCTAssertFalse(folder.createdAt < Date().addingTimeInterval(-1))
        XCTAssertFalse(folder.modifiedAt < Date().addingTimeInterval(-1))
    }

    func testAppFolderHashableBasedOnId() {
        let id = UUID().uuidString
        let folder1 = AppFolder(id: id, name: "Test", appPaths: ["/Applications/App1.app"])
        let folder2 = AppFolder(id: id, name: "Different", appPaths: ["/Applications/App2.app"])
        XCTAssertEqual(folder1.hashValue, folder2.hashValue)
    }

    func testAppFolderEqualityBasedOnId() {
        let folder1 = AppFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folder2 = AppFolder(name: "Different", appPaths: ["/Applications/App2.app"])
        XCTAssertNotEqual(folder1, folder2)
    }

    func testAppFolderEqualityWithSameId() {
        let id = UUID().uuidString
        let folder1 = AppFolder(id: id, name: "Test", appPaths: ["/Applications/App1.app"])
        let folder2 = AppFolder(id: id, name: "Different", appPaths: ["/Applications/App2.app"])
        XCTAssertEqual(folder1, folder2)
    }

    // MARK: - Folder CRUD Tests

    func testCreateFolderAddsToFoldersList() {
        _ = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        XCTAssertEqual(appModel.folders.count, 1)
        XCTAssertEqual(appModel.folders[0].name, "Development")
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testCreateFolderWithMultipleApps() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app", "/Applications/Sublime.app"])
        XCTAssertEqual(folder!.appPaths.count, 3)
        XCTAssertEqual(appModel.folders[0].appPaths.count, 3)
    }

    func testDeleteFolderRemovesFromList() {
        let folder = appModel.createFolder(name: "Temp", appPaths: ["/Applications/Test.app"])
        let folderId = folder!.id
        appModel.deleteFolder(folderId: folderId)
        XCTAssertEqual(appModel.folders.count, 0)
        XCTAssertFalse(appModel.folders.contains(where: { $0.id == folderId }))
    }

    func testDeleteNonExistentFolderDoesNothing() {
        appModel.deleteFolder(folderId: "non-existent-id")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testRenameFolderUpdatesName() {
        let folder = appModel.createFolder(name: "OldName", appPaths: ["/Applications/App1.app"])
        let folderId = folder!.id
        appModel.renameFolder(folderId: folderId, newName: "NewName")
        XCTAssertEqual(appModel.folders[0].name, "NewName")
    }

    func testRenameNonExistentFolderDoesNothing() {
        appModel.renameFolder(folderId: "non-existent-id", newName: "NewName")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testRenameFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folderId = folder!.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.renameFolder(folderId: folderId, newName: "Updated")
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testAddAppToFolderAddsPathToList() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id
        appModel.addAppToFolder("/Applications/VSCode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app", "/Applications/VSCode.app"])
    }

    func testAddAppToFolderDoesNotDuplicate() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id
        appModel.addAppToFolder("/Applications/Xcode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths.count, 1)
    }

    func testAddAppToNonExistentFolderDoesNothing() {
        appModel.addAppToFolder("/Applications/Test.app", folderId: "non-existent-id")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testAddAppToFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folderId = folder!.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.addAppToFolder("/Applications/App2.app", folderId: folderId)
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testRemoveAppFromFolderRemovesPath() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let folderId = folder!.id
        appModel.removeAppFromFolder("/Applications/VSCode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testRemoveNonExistentAppFromFolderDoesNothing() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id
        appModel.removeAppFromFolder("/Applications/NonExistent.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testRemoveAppFromNonExistentFolderDoesNothing() {
        appModel.removeAppFromFolder("/Applications/Test.app", folderId: "non-existent-id")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testRemoveAppFromFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app", "/Applications/App2.app"])
        let folderId = folder!.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.removeAppFromFolder("/Applications/App2.app", folderId: folderId)
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testMoveAppInFolderAddsToTargetAndRemovesFromSource() {
        let folder1 = appModel.createFolder(name: "Source", appPaths: ["/Applications/Xcode.app"])
        let folder2 = appModel.createFolder(name: "Target", appPaths: ["/Applications/VSCode.app"])
        let sourceId = folder1!.id
        let targetId = folder2!.id

        appModel.moveAppInFolder("/Applications/Xcode.app", from: sourceId, to: targetId)

        XCTAssertEqual(appModel.folders.first(where: { $0.id == sourceId })?.appPaths, [])
        XCTAssertEqual(appModel.folders.first(where: { $0.id == targetId })?.appPaths, ["/Applications/VSCode.app", "/Applications/Xcode.app"])
    }

    func testMoveAppInFolderSameFolderDoesNothing() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let folderId = folder!.id

        appModel.moveAppInFolder("/Applications/Xcode.app", from: folderId, to: folderId)

        XCTAssertEqual(appModel.folders[0].appPaths.count, 2)
    }

    // MARK: - Folder Navigation Tests

    func testOpenFolderSetsCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id
        appModel.openFolder(folderId)
        XCTAssertEqual(appModel.currentFolderId, folderId)
    }

    func testCloseFolderResetsCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id
        appModel.openFolder(folderId)
        appModel.closeFolder()
        XCTAssertNil(appModel.currentFolderId)
    }

    func testCurrentFolderReturnsMatchingFolder() {
        let folder1 = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        _ = appModel.createFolder(name: "Tools", appPaths: ["/Applications/VSCode.app"])
        appModel.openFolder(folder1!.id)
        XCTAssertEqual(appModel.currentFolder?.name, "Development")
        XCTAssertEqual(appModel.currentFolder?.id, folder1!.id)
    }

    func testCurrentFolderReturnsNilWhenNoFolderOpen() {
        XCTAssertNil(appModel.currentFolder)
    }

    // MARK: - Folder Application Generation Tests

    func testGetFolderApplicationCreatesCompositeApp() {
        let folder = AppFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let app = appModel.getFolderApplication(folder)
        XCTAssertEqual(app.name, "Development")
        XCTAssertEqual(app.path, folder.id)
        XCTAssertEqual(app.folderId, folder.id)
        XCTAssertTrue(app.isFolder)
        XCTAssertEqual(app.containedApps, folder.appPaths)
    }

    func testGetFolderApplicationDescriptionShowsAppCount() {
        let folder = AppFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let app = appModel.getFolderApplication(folder)
        XCTAssertEqual(app.bundleDescription, "2 apps")
    }

    func testGetFolderApplicationDescriptionForSingleApp() {
        let folder = AppFolder(name: "Single", appPaths: ["/Applications/Xcode.app"])
        let app = appModel.getFolderApplication(folder)
        XCTAssertEqual(app.bundleDescription, "1 app")
    }

    func testGetFolderApplicationUsesFolderCreatedAtAsInstallationDate() {
        let folder = AppFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let app = appModel.getFolderApplication(folder)
        XCTAssertEqual(app.installationDate, folder.createdAt)
    }

    // MARK: - Folder Icon Generation Tests

    func testGenerateFolderIconReturnsNilForEmptyApps() {
        XCTAssertNil(IconService.shared.generateFolderIcon([]))
    }

    func testGenerateFolderIconReturnsNonNilForSingleApp() {
        let app = Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        XCTAssertNotNil(IconService.shared.generateFolderIcon([app]))
    }

    func testGenerateFolderIconUsesDefaultGridSize3() {
        let apps = (1...9).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        let icon = IconService.shared.generateFolderIcon(apps)
        XCTAssertNotNil(icon)
    }

    func testGenerateFolderIconWithCustomGridSize() {
        let apps = (1...16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        let icon = IconService.shared.generateFolderIcon(apps, gridSize: 4)
        XCTAssertNotNil(icon)
    }

    func testGenerateFolderIconWithMoreAppsThanGridCapacity() {
        let apps = (1...20).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        }
        let icon = IconService.shared.generateFolderIcon(apps, gridSize: 3)
        XCTAssertNotNil(icon)
        // Grid size 3 can show 9 apps (3*3), so only first 9 should be used
    }

    // MARK: - Folder Icon Layout Tests
    //
    // The mini-grid adapts its cell count to the member count and centers the drawn
    // block, so every folder tile fills the same square footprint regardless of how
    // many apps it contains. These use fully opaque synthetic icons so the opaque
    // bounding box of the composited image is deterministic.

    private func makeSolidIconApp(_ index: Int) -> Application {
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        return Application(id: "/Applications/Solid\(index).app", name: "Solid\(index)",
                           path: "/Applications/Solid\(index).app", icon: icon,
                           installationDate: Date(), isFolder: false)
    }

    /// Opaque bounding box of the image as fractions of the canvas (x/y from the top-left).
    private func opaqueBounds(of image: NSImage) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (Double(minX) / Double(width), Double(minY) / Double(height),
                Double(maxX + 1) / Double(width), Double(maxY + 1) / Double(height))
    }

    func testGenerateFolderIconTwoAppsUsesLargeCellsCenteredVertically() throws {
        let icon = try XCTUnwrap(IconService.shared.generateFolderIcon([makeSolidIconApp(1), makeSolidIconApp(2)]))
        let bounds = try XCTUnwrap(opaqueBounds(of: icon))
        // 2 apps → 2×2 grid → one row of half-height cells, centered: y spans 0.25–0.75.
        XCTAssertEqual(bounds.minY, 0.25, accuracy: 0.03)
        XCTAssertEqual(bounds.maxY, 0.75, accuracy: 0.03)
        XCTAssertEqual(bounds.minX, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxX, 1.0, accuracy: 0.03)
    }

    func testGenerateFolderIconSixAppsCentersRowBlockVertically() throws {
        let apps = (1...6).map { makeSolidIconApp($0) }
        let icon = try XCTUnwrap(IconService.shared.generateFolderIcon(apps))
        let bounds = try XCTUnwrap(opaqueBounds(of: icon))
        // 6 apps → 3×3 grid → two rows of third-height cells, centered: y spans 1/6–5/6.
        XCTAssertEqual(bounds.minY, 1.0 / 6.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxY, 5.0 / 6.0, accuracy: 0.03)
        XCTAssertEqual(bounds.minX, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxX, 1.0, accuracy: 0.03)
    }

    func testGenerateFolderIconFullGridFillsCanvas() throws {
        let apps = (1...9).map { makeSolidIconApp($0) }
        let icon = try XCTUnwrap(IconService.shared.generateFolderIcon(apps))
        let bounds = try XCTUnwrap(opaqueBounds(of: icon))
        XCTAssertEqual(bounds.minY, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxY, 1.0, accuracy: 0.03)
        XCTAssertEqual(bounds.minX, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxX, 1.0, accuracy: 0.03)
    }

    func testGenerateFolderIconSingleAppFillsCanvas() throws {
        let icon = try XCTUnwrap(IconService.shared.generateFolderIcon([makeSolidIconApp(1)]))
        let bounds = try XCTUnwrap(opaqueBounds(of: icon))
        // 1 app → 1×1 grid → the single icon fills the whole tile.
        XCTAssertEqual(bounds.minY, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxY, 1.0, accuracy: 0.03)
        XCTAssertEqual(bounds.minX, 0.0, accuracy: 0.03)
        XCTAssertEqual(bounds.maxX, 1.0, accuracy: 0.03)
    }

    func testGenerateFolderIconThreeAppsCentersPartialBottomRow() throws {
        let apps = (1...3).map { makeSolidIconApp($0) }
        let icon = try XCTUnwrap(IconService.shared.generateFolderIcon(apps))
        guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("could not rasterize folder icon")
        }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        func alpha(atXFraction fx: Double, yFraction fy: Double) -> CGFloat {
            rep.colorAt(x: Int(Double(width) * fx), y: Int(Double(height) * fy))?.alphaComponent ?? 0
        }
        // 3 apps → 2×2 grid: top row full (2 icons), bottom row 1 icon centered — the
        // bottom corners stay empty while the bottom center is drawn.
        XCTAssertGreaterThan(alpha(atXFraction: 0.5, yFraction: 0.75), 0.5, "bottom-center cell should be drawn")
        XCTAssertLessThan(alpha(atXFraction: 0.1, yFraction: 0.75), 0.5, "bottom-left should be empty")
        XCTAssertLessThan(alpha(atXFraction: 0.9, yFraction: 0.75), 0.5, "bottom-right should be empty")
        XCTAssertGreaterThan(alpha(atXFraction: 0.1, yFraction: 0.25), 0.5, "top row should span the width")
        XCTAssertGreaterThan(alpha(atXFraction: 0.9, yFraction: 0.25), 0.5, "top row should span the width")
    }

    // MARK: - Folder Persistence Tests

    func testSaveFoldersWritesToUserDefaults() {
        _ = appModel.createFolder(name: "Test", appPaths: ["/Applications/Test.app"])
        let data = UserDefaults.standard.data(forKey: "appFolders")
        XCTAssertNotNil(data)
    }

    func testLoadFoldersReadsFromUserDefaults() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/Test.app"])
        let savedData = try? JSONEncoder().encode([folder])
        UserDefaults.standard.set(savedData, forKey: "appFolders")

        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.folders.count, 1)
        XCTAssertEqual(newAppModel.folders[0].name, "Test")
    }

    func testLoadFoldersWithInvalidDataDoesNothing() {
        UserDefaults.standard.set("invalid-string", forKey: "appFolders")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.folders.count, 0)
    }

    func testLoadFoldersWithNoDataDoesNothing() {
        UserDefaults.standard.removeObject(forKey: "appFolders")
        let newAppModel = AppModel()
        XCTAssertEqual(newAppModel.folders.count, 0)
    }

    // MARK: - Folder Management with SetApplications

    func testCreateFolderAfterSetApplications() {
        let apps = [
            Application(id: "/Applications/Xcode.app", name: "Xcode", path: "/Applications/Xcode.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
            Application(id: "/Applications/VSCode.app", name: "VSCode", path: "/Applications/VSCode.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil),
        ]
        appModel.setApplications(apps)
        _ = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        XCTAssertEqual(appModel.folders.count, 1)
    }

    func testDeleteFolderAfterSetApplications() {
        let apps = [Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)]
        appModel.setApplications(apps)
        let folder = appModel.createFolder(name: "Temp", appPaths: ["/Applications/Test.app"])
        appModel.deleteFolder(folderId: folder!.id)
        XCTAssertEqual(appModel.folders.count, 0)
    }

    // MARK: - Folder Scanning Tests

    func testDefaultScanDirectoriesIncludesStandardPaths() {
        let dirs = AppModel.defaultScanDirectories
        XCTAssertTrue(dirs.contains("/Applications"))
        XCTAssertTrue(dirs.contains("/Applications/Utilities"))
        XCTAssertTrue(dirs.contains("/System/Applications"))
        XCTAssertTrue(dirs.contains("/System/Applications/Utilities"))
    }

    func testDefaultScanDirectoriesIncludesUserAppsIfExists() {
        let dirs = AppModel.defaultScanDirectories
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: userApps) {
            XCTAssertTrue(dirs.contains(userApps))
        }
    }

    func testAllScanDirectoriesCombinesDefaultAndCustom() {
        let apps = [Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)]
        appModel.setApplications(apps)
        appModel.customDirectories = ["/Users/test/CustomApps"]
        XCTAssertEqual(appModel.allScanDirectories.count, AppModel.defaultScanDirectories.count + 1)
    }

    func testAddCustomDirectoryAddsToList() {
        let apps = [Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/Users/test/CustomApps")
        XCTAssertTrue(appModel.customDirectories.contains("/Users/test/CustomApps"))
    }

    func testAddCustomDirectoryDoesNotDuplicate() {
        let apps = [Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/Users/test/CustomApps")
        appModel.addCustomDirectory("/Users/test/CustomApps")
        XCTAssertEqual(appModel.customDirectories.count, 1)
    }

    func testAddCustomDirectoryToNonExistentPath() {
        let apps = [Application(id: "/Applications/Test.app", name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/NonExistentPath")
        XCTAssertTrue(appModel.customDirectories.contains("/NonExistentPath"))
    }

    // MARK: - Display Pipeline Tests (I-1)

    private func makeApp(_ path: String) -> Application {
        Application(id: path, name: (path as NSString).lastPathComponent, path: path, icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
    }

    func testGetDisplayedAppsInsideFolderShowsOnlyFolderApps() {
        appModel.setApplications([
            makeApp("/Applications/Xcode.app"),
            makeApp("/Applications/VSCode.app"),
            makeApp("/Applications/Other.app"),
        ])
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        appModel.openFolder(folder!.id)

        let displayed = appModel.getDisplayedApps()
        XCTAssertEqual(Set(displayed.map(\.path)), Set(["/Applications/Xcode.app", "/Applications/VSCode.app"]))
        XCTAssertFalse(displayed.contains { $0.path == "/Applications/Other.app" })
    }

    func testRootLevelSearchMatchesAppsInsideFolders() {
        appModel.setApplications([
            makeApp("/Applications/Xcode.app"),
            makeApp("/Applications/Other.app"),
        ])
        _ = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        // Stay at root (currentFolderId == nil) and search — should still find the app even though
        // it's tucked inside a folder.
        appModel.searchTerm = "xcode"

        let displayed = appModel.getDisplayedApps()
        XCTAssertTrue(displayed.contains { $0.path == "/Applications/Xcode.app" })
    }

    func testShowFoldersFirstOrdersFoldersBeforeLooseApps() {
        appModel.setApplications([
            makeApp("/Applications/AAA.app"),
            makeApp("/Applications/Zebra.app"),
        ])
        _ = appModel.createFolder(name: "Folder", appPaths: ["/Applications/Zebra.app"])
        appModel.showFoldersFirst = true

        let displayed = appModel.getDisplayedApps()
        XCTAssertTrue(displayed.first?.isFolder == true)
    }

    func testNoNestedFoldersSupported() {
        appModel.setApplications([
            makeApp("/Applications/ParentOnly.app"),
            makeApp("/Applications/ChildOnly.app"),
        ])
        let parent = AppFolder(name: "Parent", appPaths: ["/Applications/ParentOnly.app"])
        let child = AppFolder(name: "Child", appPaths: ["/Applications/ChildOnly.app"])

        appModel.folders = [parent, child]

        appModel.openFolder(parent.id)
        let paths = Set(appModel.getDisplayedApps().map(\.path))
        XCTAssertTrue(paths.contains("/Applications/ParentOnly.app"))
        XCTAssertFalse(paths.contains("/Applications/ChildOnly.app")) // Child folder apps are not included — no nesting supported
    }

    func testRealAppInsideFolderCarriesFolderId() {
        appModel.setApplications([makeApp("/Applications/Xcode.app")])
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        appModel.openFolder(folder!.id)

        let displayed = appModel.getDisplayedApps()
        XCTAssertTrue(displayed.contains { $0.path == "/Applications/Xcode.app" })
        XCTAssertEqual(displayed.first(where: { $0.path == "/Applications/Xcode.app" })!.folderId, folder!.id) // Real app carries parent folder identity (allows context menu to show Move to Root)
    }

    func testCreateFolderReturnsNilWhenInsideAnotherFolder() {
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        appModel.openFolder(folder!.id)

        let result = appModel.createFolder(name: "SubDev", appPaths: ["/Applications/VSCode.app"])
        XCTAssertNil(result) // Cannot create nested folders — returns nil
        XCTAssertEqual(appModel.folders.count, 1) // Only the original folder exists
    }

    func testMoveAppToRootRemovesAppFromFolder() {
        let apps = [makeApp("/Applications/Xcode.app"), makeApp("/Applications/VSCode.app")]
        appModel.setApplications(apps)
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let folderId = folder!.id

        appModel.moveAppToRoot("/Applications/Xcode.app", folderId: folderId)

        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/VSCode.app"]) // Xcode removed from folder
    }

    func testMoveAppToRootWhenInsideFolderResetsCurrentFolderId() {
        let apps = [makeApp("/Applications/Xcode.app")]
        appModel.setApplications(apps)
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id

        appModel.openFolder(folderId)
        appModel.moveAppToRoot("/Applications/Xcode.app", folderId: folderId)

        XCTAssertNil(appModel.currentFolderId) // Folder emptied after moving last app to root — currentFolderId resets
    }

    func testMoveAppToRootNonExistentPathDoesNothing() {
        let folder = appModel.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder!.id

        appModel.moveAppToRoot("/Applications/NonExistent.app", folderId: folderId)

        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"]) // Nothing removed — path not in folder
    }

    func testMoveAppToRootNonExistentFolderDoesNothing() {
        appModel.moveAppToRoot("/Applications/Test.app", folderId: "non-existent-id")

        XCTAssertEqual(appModel.folders.count, 0) // No folders exist — operation does nothing
    }
}
