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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
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

    // MARK: - Icon Pack Directory (Bug #1: icons-v3 → icons-v4)

    // Note: export() opens an NSSavePanel which requires UI interaction, so icon pack
    // directory tests verify the archive structure directly (see BackupArchive tests below).

    @MainActor
    func testIconPackRestoreWritesToV4CacheDirectory() throws {
        // Verify that restoreIconPack writes to the v4 cache directory.
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v4", isDirectory: true)
        // Clean up any existing v4 cache
        try? FileManager.default.removeItem(at: cacheDir)

        let iconPack = BackupManager.IconPack(entries: ["restore_test_key": Data([0x11, 0x22])])
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: iconPack
        )
        let preview = BackupManager.BackupPreview(
            archive: archive,
            validAppPaths: Set<String>(),
            missingAppPaths: Set<String>()
        )
        BackupManager.shared.apply(preview: preview)

        let restoredFile = cacheDir.appendingPathComponent("restore_test_key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredFile.path),
            "Restored icon should be written to the v4 cache directory")
        let restoredData = try Data(contentsOf: restoredFile)
        XCTAssertEqual(restoredData, Data([0x11, 0x22]),
            "Restored icon data should match the original")

        try? FileManager.default.removeItem(at: cacheDir)
    }

    // MARK: - BackupArchive Missing Fields (Bug #4)

    func testBackupArchiveIncludesAllSevenPreviouslyMissingFields() {
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
            showInDock: true,
            launchAnimationDirection: "zoomIn",
            launchAnimationEnabled: false,
            presentationMode: "Sheet",
            tintColor: "#FF0000",
            tintStrength: 0.5,
            showHiddenApps: true,
            launchMode: "Full Screen",
            icons: BackupManager.IconPack(entries: [:])
        )
        XCTAssertEqual(archive.launchAnimationDirection, "zoomIn")
        XCTAssertEqual(archive.launchAnimationEnabled, false)
        XCTAssertEqual(archive.presentationMode, "Sheet")
        XCTAssertEqual(archive.tintColor, "#FF0000")
        XCTAssertEqual(archive.tintStrength, 0.5)
        XCTAssertEqual(archive.showHiddenApps, true)
        XCTAssertEqual(archive.launchMode, "Full Screen")
    }

    func testBackupArchiveDefaultsForMissingFields() {
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
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: BackupManager.IconPack(entries: [:])
        )
        // Defaults for the 7 previously-missing fields
        XCTAssertEqual(archive.launchAnimationDirection, "zoomOut")
        XCTAssertEqual(archive.launchAnimationEnabled, true)
        XCTAssertEqual(archive.presentationMode, "Glass")
        XCTAssertEqual(archive.tintColor, "#0000FF")
        XCTAssertEqual(archive.tintStrength, 0.0)
        XCTAssertEqual(archive.showHiddenApps, false)
        XCTAssertEqual(archive.launchMode, "Window")
    }

    func testBackupArchiveRoundTripsAllFieldsViaJSON() throws {
        let archive = BackupManager.BackupArchive(
            appFolders: [],
            customOrder: ["/app": 1],
            hiddenAppPaths: Set(["/hidden.app"]),
            sortOption: ApplicationSorter.SortOption.installationDate.rawValue,
            iconSize: IconSize.large.rawValue,
            showFoldersFirst: true,
            refreshInterval: 900.0,
            currentFolderId: "folder-123",
            customDirectories: ["/Custom"],
            glowEnabled: true,
            glowColor: "#00FF00",
            glowIntensity: 0.8,
            glowWidth: 20.0,
            fontFamily: "Helvetica Neue",
            fontSize: 16.0,
            fontWeight: "bold",
            pressFeedbackEnabled: false,
            recentAppsEnabled: true,
            overlayOpacity: 0.75,
            showInDock: false,
            launchAnimationDirection: "zoomIn",
            launchAnimationEnabled: false,
            presentationMode: "Sheet",
            tintColor: "#FF00FF",
            tintStrength: 0.3,
            showHiddenApps: true,
            launchMode: "Maximized",
            icons: BackupManager.IconPack(entries: ["k": Data([1])])
        )
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(BackupManager.BackupArchive.self, from: data)
        XCTAssertEqual(decoded.launchAnimationDirection, "zoomIn")
        XCTAssertEqual(decoded.launchAnimationEnabled, false)
        XCTAssertEqual(decoded.presentationMode, "Sheet")
        XCTAssertEqual(decoded.tintColor, "#FF00FF")
        XCTAssertEqual(decoded.tintStrength, 0.3)
        XCTAssertEqual(decoded.showHiddenApps, true)
        XCTAssertEqual(decoded.launchMode, "Maximized")
        // Also verify existing fields survived
        XCTAssertEqual(decoded.sortOption, ApplicationSorter.SortOption.installationDate.rawValue)
        XCTAssertEqual(decoded.showFoldersFirst, true)
        XCTAssertEqual(decoded.glowColor, "#00FF00")
    }
}