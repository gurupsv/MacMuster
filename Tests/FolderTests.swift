import XCTest
@testable import MacMuster

final class FolderTests: XCTestCase {

    private var appModel: AppModel!

    override func setUpWithError() throws {
        appModel = AppModel()
    }

    override func tearDownWithError() throws {
        appModel = nil
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
        let folder1 = AppFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folder2 = AppFolder(name: "Test", appPaths: ["/Applications/App2.app"])
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
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        XCTAssertEqual(appModel.folders.count, 1)
        XCTAssertEqual(appModel.folders[0].name, "Development")
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testCreateFolderWithMultipleApps() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app", "/Applications/Sublime.app"])
        XCTAssertEqual(folder.appPaths.count, 3)
        XCTAssertEqual(appModel.folders[0].appPaths.count, 3)
    }

    func testDeleteFolderRemovesFromList() {
        let folder = appModel.createFolder(name: "Temp", appPaths: ["/Applications/Test.app"])
        let folderId = folder.id
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
        let folderId = folder.id
        appModel.renameFolder(folderId: folderId, newName: "NewName")
        XCTAssertEqual(appModel.folders[0].name, "NewName")
    }

    func testRenameNonExistentFolderDoesNothing() {
        appModel.renameFolder(folderId: "non-existent-id", newName: "NewName")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testRenameFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folderId = folder.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.renameFolder(folderId: folderId, newName: "Updated")
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testAddAppToFolderAddsPathToList() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.addAppToFolder("/Applications/VSCode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app", "/Applications/VSCode.app"])
    }

    func testAddAppToFolderDoesNotDuplicate() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.addAppToFolder("/Applications/Xcode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths.count, 1)
    }

    func testAddAppToNonExistentFolderDoesNothing() {
        appModel.addAppToFolder("/Applications/Test.app", folderId: "non-existent-id")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testAddAppToFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app"])
        let folderId = folder.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.addAppToFolder("/Applications/App2.app", folderId: folderId)
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testRemoveAppFromFolderRemovesPath() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let folderId = folder.id
        appModel.removeAppFromFolder("/Applications/VSCode.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testRemoveNonExistentAppFromFolderDoesNothing() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.removeAppFromFolder("/Applications/NonExistent.app", folderId: folderId)
        XCTAssertEqual(appModel.folders[0].appPaths, ["/Applications/Xcode.app"])
    }

    func testRemoveAppFromNonExistentFolderDoesNothing() {
        appModel.removeAppFromFolder("/Applications/Test.app", folderId: "non-existent-id")
        XCTAssertEqual(appModel.folders.count, 0)
    }

    func testRemoveAppFromFolderUpdatesModifiedAt() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/App1.app", "/Applications/App2.app"])
        let folderId = folder.id
        let originalModifiedAt = appModel.folders[0].modifiedAt
        appModel.removeAppFromFolder("/Applications/App2.app", folderId: folderId)
        XCTAssertGreaterThanOrEqual(appModel.folders[0].modifiedAt, originalModifiedAt)
    }

    func testMoveAppInFolderAddsToTargetAndRemovesFromSource() {
        let folder1 = appModel.createFolder(name: "Source", appPaths: ["/Applications/Xcode.app"])
        let folder2 = appModel.createFolder(name: "Target", appPaths: ["/Applications/VSCode.app"])
        let sourceId = folder1.id
        let targetId = folder2.id

        appModel.moveAppInFolder("/Applications/Xcode.app", from: sourceId, to: targetId)

        XCTAssertEqual(appModel.folders.first(where: { $0.id == sourceId })?.appPaths, [])
        XCTAssertEqual(appModel.folders.first(where: { $0.id == targetId })?.appPaths, ["/Applications/VSCode.app", "/Applications/Xcode.app"])
    }

    func testMoveAppInFolderSameFolderDoesNothing() {
        let folder = appModel.createFolder(name: "Tools", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        let folderId = folder.id

        appModel.moveAppInFolder("/Applications/Xcode.app", from: folderId, to: folderId)

        XCTAssertEqual(appModel.folders[0].appPaths.count, 2)
    }

    // MARK: - Folder Navigation Tests

    func testOpenFolderSetsCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.openFolder(folderId)
        XCTAssertEqual(appModel.currentFolderId, folderId)
    }

    func testCloseFolderResetsCurrentFolderId() {
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folderId = folder.id
        appModel.openFolder(folderId)
        appModel.closeFolder()
        XCTAssertNil(appModel.currentFolderId)
    }

    func testCurrentFolderReturnsMatchingFolder() {
        let folder1 = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let folder2 = appModel.createFolder(name: "Tools", appPaths: ["/Applications/VSCode.app"])
        appModel.openFolder(folder1.id)
        XCTAssertEqual(appModel.currentFolder?.name, "Development")
        XCTAssertEqual(appModel.currentFolder?.id, folder1.id)
    }

    func testCurrentFolderReturnsNilWhenNoFolderOpen() {
        XCTAssertNil(appModel.currentFolder)
    }

    // MARK: - Folder Application Generation Tests

    func testGetFolderApplicationCreatesCompositeApp() {
        let folder = AppFolder(name: "Development", appPaths: ["/Applications/Xcode.app"])
        let app = appModel.getFolderApplication(folder)
        XCTAssertEqual(app.name, "Development")
        XCTAssertEqual(app.path, "folder:\(folder.id)")
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
        XCTAssertNil(appModel.generateFolderIcon([]))
    }

    func testGenerateFolderIconReturnsNonNilForSingleApp() {
        let app = AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())
        XCTAssertNotNil(appModel.generateFolderIcon([app]))
    }

    func testGenerateFolderIconUsesDefaultGridSize3() {
        let apps = (1...9).map { i in
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
        }
        let icon = appModel.generateFolderIcon(apps)
        XCTAssertNotNil(icon)
    }

    func testGenerateFolderIconWithCustomGridSize() {
        let apps = (1...16).map { i in
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
        }
        let icon = appModel.generateFolderIcon(apps, gridSize: 4)
        XCTAssertNotNil(icon)
    }

    func testGenerateFolderIconWithMoreAppsThanGridCapacity() {
        let apps = (1...20).map { i in
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
        }
        let icon = appModel.generateFolderIcon(apps, gridSize: 3)
        XCTAssertNotNil(icon)
        // Grid size 3 can show 9 apps (3*3), so only first 9 should be used
    }

    // MARK: - Folder Persistence Tests

    func testSaveFoldersWritesToUserDefaults() {
        let folder = appModel.createFolder(name: "Test", appPaths: ["/Applications/Test.app"])
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
            AppModel.Application(name: "Xcode", path: "/Applications/Xcode.app", icon: nil, installationDate: Date()),
            AppModel.Application(name: "VSCode", path: "/Applications/VSCode.app", icon: nil, installationDate: Date()),
        ]
        appModel.setApplications(apps)
        let folder = appModel.createFolder(name: "Development", appPaths: ["/Applications/Xcode.app", "/Applications/VSCode.app"])
        XCTAssertEqual(appModel.folders.count, 1)
    }

    func testDeleteFolderAfterSetApplications() {
        let apps = [AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())]
        appModel.setApplications(apps)
        let folder = appModel.createFolder(name: "Temp", appPaths: ["/Applications/Test.app"])
        appModel.deleteFolder(folderId: folder.id)
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
        let apps = [AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())]
        appModel.setApplications(apps)
        appModel.customDirectories = ["/Users/test/CustomApps"]
        XCTAssertEqual(appModel.allScanDirectories.count, AppModel.defaultScanDirectories.count + 1)
    }

    func testAddCustomDirectoryAddsToList() {
        let apps = [AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/Users/test/CustomApps")
        XCTAssertTrue(appModel.customDirectories.contains("/Users/test/CustomApps"))
    }

    func testAddCustomDirectoryDoesNotDuplicate() {
        let apps = [AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/Users/test/CustomApps")
        appModel.addCustomDirectory("/Users/test/CustomApps")
        XCTAssertEqual(appModel.customDirectories.count, 1)
    }

    func testAddCustomDirectoryToNonExistentPath() {
        let apps = [AppModel.Application(name: "Test", path: "/Applications/Test.app", icon: nil, installationDate: Date())]
        appModel.setApplications(apps)
        appModel.addCustomDirectory("/NonExistentPath")
        XCTAssertTrue(appModel.customDirectories.contains("/NonExistentPath"))
    }
}
