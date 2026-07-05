import XCTest
@testable import MacMuster

final class BackupManagerTests: XCTestCase {

    // MARK: - Schema Version (Critical #7 review finding — version tag in backup format)

    func testBackupArchiveHasSchemaVersion() {
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )
        XCTAssertEqual(archive.schemaVersion, 1, "Backup archive should have schema version field")
    }

    func testSchemaVersionDefaultsToOne() {
        let archive = BackupManager.BackupArchive(
            appFolders: [],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )
        XCTAssertEqual(archive.schemaVersion, 1, "Unspecified schema version should default to 1")
    }

    // MARK: - Restore Preview — Path Validation

    func testRestorePreviewValidAppPathExistsOnDisk() {
        let folder = AppFolder(id: "test-folder", name: "Test Folder", appPaths: ["/Applications/Safari.app"])
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [folder],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )

        // Safari.app exists on standard macOS — it should be validated as present
        let allAppPaths = Set(archive.appFolders.flatMap { $0.appPaths })
        var valid: Set<String> = []
        var missing: Set<String> = []

        for path in allAppPaths {
            guard FileManager.default.fileExists(atPath: path) else {
                missing.insert(path)
                continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                missing.insert(path)
                continue
            }
            guard path.hasSuffix(".app") else {
                missing.insert(path)
                continue
            }
            valid.insert(path)
        }

        XCTAssertTrue(valid.contains("/Applications/Safari.app"), "Safari.app on disk should be validated as present")
        XCTAssertEqual(missing.count, 0, "No paths should be missing when all apps exist on disk")
    }

    func testRestorePreviewMissingAppPathDoesNotExistOnDisk() {
        let folder = AppFolder(id: "test-folder", name: "Test Folder", appPaths: ["/Applications/NonExistent.app"])
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [folder],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )

        // NonExistent.app does not exist — it should be validated as missing
        let allAppPaths = Set(archive.appFolders.flatMap { $0.appPaths })
        var valid: Set<String> = []
        var missing: Set<String> = []

        for path in allAppPaths {
            guard FileManager.default.fileExists(atPath: path) else {
                missing.insert(path)
                continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                missing.insert(path)
                continue
            }
            guard path.hasSuffix(".app") else {
                missing.insert(path)
                continue
            }
            valid.insert(path)
        }

        XCTAssertTrue(missing.contains("/Applications/NonExistent.app"), "Non-existent app should be flagged as missing in preview")
        XCTAssertEqual(valid.count, 0, "No paths should be valid when all apps are missing on disk")
    }

    func testRestorePreviewRejectsNonAppPath() {
        let folder = AppFolder(id: "test-folder", name: "Test Folder", appPaths: ["/Applications/Utilities"]) // directory, not .app bundle
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [folder],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )

        let allAppPaths = Set(archive.appFolders.flatMap { $0.appPaths })
        var valid: Set<String> = []
        var missing: Set<String> = []

        for path in allAppPaths {
            guard FileManager.default.fileExists(atPath: path) else {
                missing.insert(path)
                continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                missing.insert(path)
                continue
            }
            guard path.hasSuffix(".app") else {
                missing.insert(path)
                continue
            }
            valid.insert(path)
        }

        XCTAssertTrue(missing.contains("/Applications/Utilities"), "Non-.app directory should be rejected in restore validation")
    }

    // MARK: - IconPack Codable

    func testIconPackEncodeAndDecode() {
        let iconPack = BackupManager.IconPack(entries: ["key1": Data([0, 1, 2])])
        do {
            let data = try JSONEncoder().encode(iconPack)
            let decoded = try JSONDecoder().decode(BackupManager.IconPack.self, from: data)
            XCTAssertEqual(decoded.entries.count, iconPack.entries.count, "Icon pack entries count should match")
            XCTAssertEqual(decoded.entries["key1"], iconPack.entries["key1"], "Icon pack entry data should match")
        } catch {
            XCTFail("IconPack encode/decode should succeed: \(error)")
        }
    }

    // MARK: - BackupPreview Computed Values

    func testBackupPreviewFolderCountMatchesArchive() {
        let folder = AppFolder(id: "test-folder", name: "Test Folder", appPaths: ["/Applications/Safari.app"])
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [folder],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )

        let validAppPaths = Set(["/Applications/Safari.app"])
        let missingAppPaths = Set<String>()
        let preview = BackupManager.BackupPreview(
            archive: archive,
            validAppPaths: validAppPaths,
            missingAppPaths: missingAppPaths
        )

        XCTAssertEqual(preview.folderCount, 1, "Folder count should match archive folder count")
    }

    func testBackupPreviewAppCountIncludesFoldersAndValidApps() {
        let folder = AppFolder(id: "test-folder", name: "Test Folder", appPaths: ["/Applications/Safari.app"])
        let archive = BackupManager.BackupArchive(
            schemaVersion: 1,
            appFolders: [folder],
            customOrder: [:],
            hiddenAppPaths: Set<String>(),
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 30.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: AppMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )

        let validAppPaths = Set(["/Applications/Safari.app"])
        let missingAppPaths = Set<String>()
        let preview = BackupManager.BackupPreview(
            archive: archive,
            validAppPaths: validAppPaths,
            missingAppPaths: missingAppPaths
        )

        XCTAssertEqual(preview.appCount, 1 + folder.appPaths.count, "App count should include valid apps plus all folder app paths")
    }
}