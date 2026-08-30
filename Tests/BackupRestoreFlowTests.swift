import XCTest
@testable import MacMuster

/// Covers the second round of backup/restore defects: **UX-2**, **UX-3**, **BUG-1**, **BUG-2**
/// and **BUG-9**. Integrity and path-traversal live in `BackupIntegrityTests`.
@MainActor
final class BackupRestoreFlowTests: XCTestCase {

    private var appModel: AppModel!

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v4", isDirectory: true)
    }

    override func setUp() async throws {
        clearDefaults()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        appModel = nil
        clearDefaults()
    }

    private nonisolated func clearDefaults() {
        for key in ["appFolders", "hiddenAppPaths", "customOrder", "currentFolderId",
                    "sortOption", "refreshInterval", "columnCount", "customDirectories",
                    "knownBundleMtimes", "recentlyUpdatedPaths"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeArchive(
        appFolders: [AppFolder] = [],
        hiddenAppPaths: Set<String> = [],
        customOrder: [String: Int] = [:],
        refreshInterval: Double = ScanMetrics.refreshIntervalDefault,
        icons: BackupManager.IconPack = BackupManager.IconPack(entries: [:])
    ) -> BackupManager.BackupArchive {
        BackupManager.BackupArchive(
            appFolders: appFolders,
            customOrder: customOrder,
            hiddenAppPaths: hiddenAppPaths,
            sortOption: ApplicationSorter.SortOption.installationDate.rawValue,
            iconSize: IconSize.large.rawValue,
            showFoldersFirst: false,
            refreshInterval: refreshInterval,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 16.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: icons
        )
    }

    private func apply(_ archive: BackupManager.BackupArchive, validAppPaths: Set<String> = []) {
        BackupManager.shared.apply(
            preview: BackupManager.BackupPreview(
                archive: archive, validAppPaths: validAppPaths, missingAppPaths: []
            )
        )
    }

    // MARK: - UX-2: a restore must reach the live UI, not just disk

    func testRestoredFoldersReachTheLiveLibrary() {
        let folder = AppFolder(name: "Restored", appPaths: [])
        apply(makeArchive(appFolders: [folder]))

        XCTAssertTrue(appModel.folders.isEmpty, "Precondition: apply() alone writes to disk, not to the live model")

        appModel.reloadAfterRestore()

        XCTAssertEqual(appModel.folders.count, 1, "Restored folders should reach the live library — this is UX-2")
        XCTAssertEqual(appModel.folders.first?.name, "Restored", "The restored folder should be the one from the archive")
    }

    func testRestoredSettingsReachTheLiveModel() {
        appModel.settings.iconSize = .small
        appModel.settings.fontSize = 12.0

        apply(makeArchive())
        appModel.reloadAfterRestore()

        XCTAssertEqual(appModel.settings.iconSize, .large, "Restored icon size should reach the live settings")
        XCTAssertEqual(appModel.settings.fontSize, 16.0, "Restored font size should reach the live settings")
    }

    func testRestoredHiddenAppsAndOrderingReachTheLiveLibrary() {
        apply(makeArchive(
            hiddenAppPaths: ["/Applications/Hidden.app"],
            customOrder: ["/Applications/First.app": 0]
        ))
        appModel.reloadAfterRestore()

        XCTAssertEqual(appModel.hiddenAppPaths, ["/Applications/Hidden.app"], "Restored hidden apps should reach the live library")
        XCTAssertEqual(appModel.customOrder["/Applications/First.app"], 0, "Restored custom order should reach the live library")
        XCTAssertEqual(appModel.sortOption, .installationDate, "Restored sort option should reach the live library")
    }

    func testReloadReplacesPreRestoreStateRatherThanMergingWithIt() {
        // A restore is a replacement. Folders and hidden apps that existed before must not
        // survive it just because the archive happens not to mention them.
        appModel.library.folders = [AppFolder(name: "Pre-existing", appPaths: [])]
        appModel.library.hiddenAppPaths = ["/Applications/WasHidden.app"]

        apply(makeArchive())
        appModel.reloadAfterRestore()

        XCTAssertTrue(appModel.folders.isEmpty, "A restore from an archive with no folders should clear existing ones")
        XCTAssertTrue(appModel.hiddenAppPaths.isEmpty, "A restore from an archive with no hidden apps should clear existing ones")
    }

    // MARK: - BUG-2: folder timestamps survive a restore

    func testRestorePreservesFolderTimestamps() throws {
        // Build a folder with timestamps well in the past, the way a real archive carries them.
        let original = AppFolder(name: "Old", appPaths: ["/Applications/Gone.app"])
        let json = try JSONEncoder().encode(original)
        var decoded = try JSONDecoder().decode(AppFolder.self, from: json)
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        decoded.modifiedAt = past

        apply(makeArchive(appFolders: [decoded]), validAppPaths: [])
        appModel.reloadAfterRestore()

        let restored = try XCTUnwrap(appModel.folders.first, "The folder should be restored")
        XCTAssertEqual(Int(restored.createdAt.timeIntervalSince1970), Int(original.createdAt.timeIntervalSince1970),
            "createdAt must survive the restore — rebuilding the folder from its parts stamped it with Date()")
        XCTAssertEqual(Int(restored.modifiedAt.timeIntervalSince1970), Int(past.timeIntervalSince1970),
            "modifiedAt must survive the restore")
        XCTAssertTrue(restored.appPaths.isEmpty, "Apps no longer on disk should still be pruned from membership")
    }

    // MARK: - BUG-1: the exported refresh interval matches the app's own default

    func testBackupRefreshIntervalDefaultMatchesTheAppDefault() {
        // The exporter defaulted to 30 s where the rest of the app uses 300, so a backup taken
        // before the user ever touched the setting restored a rescan ten times more aggressive.
        XCTAssertEqual(ScanMetrics.refreshIntervalDefault, 300, "The shared default should be 5 minutes")
        XCTAssertEqual(SettingsAppearance().refreshInterval, ScanMetrics.refreshIntervalDefault,
            "A fresh SettingsAppearance should start at the shared default")
    }

    func testRestoredRefreshIntervalReachesTheLiveSettings() {
        apply(makeArchive(refreshInterval: 900))
        appModel.reloadAfterRestore()

        XCTAssertEqual(appModel.settings.refreshInterval, 900, "A restored refresh interval should reach the live settings")
    }

    // MARK: - UX-3: the title-bar close button must not hang the restore flow

    func testClosingThePreviewWindowResumesRunModalWithCancel() async {
        // The window's style mask includes .closable, so it can be dismissed without touching
        // either button. With no delegate watching for that, runModal's continuation was never
        // resumed and the restore flow hung for the rest of the session.
        let panel = RestorePreviewPanel(folderCount: 1, appCount: 1, missingCount: 1,
                                        missingPaths: ["/Applications/Gone.app"])
        // Assert the wiring, not just the handler: invoking windowWillClose by hand proves the
        // handler works but would pass even with the delegate never assigned, which was the bug.
        XCTAssertTrue(panel.handlesWindowClose, "The panel must be the window's delegate, or AppKit never reports the close")

        let modal = Task { await panel.runModal() }
        while !panel.isAwaitingResponse { await Task.yield() }

        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        let result = await modal.value
        XCTAssertEqual(result, .cancel, "Closing the window should resolve runModal as a cancel, not hang it")
    }

    func testASecondCompletionIsIgnored() async {
        // Cancel orders the window out, which can itself deliver windowWillClose — so the
        // completion path has to be safe to reach twice. A double resume traps at runtime.
        let panel = RestorePreviewPanel(folderCount: 0, appCount: 0, missingCount: 0, missingPaths: [])
        let modal = Task { await panel.runModal() }
        while !panel.isAwaitingResponse { await Task.yield() }

        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        _ = await modal.value
        XCTAssertFalse(panel.isAwaitingResponse, "The panel should be settled after completing")
    }

    // MARK: - BUG-9: the icon pack must be usable after restore

    func testIconPackCarriesMetaSidecarsSoRestoredIconsAreUsable() throws {
        // cachedIcon requires both the bitmap and its .meta sidecar. The pack used to skip the
        // sidecars, so every restored icon was ignored and re-decoded — the biggest part of a
        // backup, carried for nothing.
        let bundlePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("IconPack-\(UUID().uuidString).app", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: bundlePath)
            IconCacheManager.shared.pruneDeletedApps(currentAppPaths: [])
        }

        let icon = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: bundlePath, appearance: .light)
        let key = IconCacheManager.shared.cacheKey(for: bundlePath, appearance: .light)

        // Export, then wipe the on-disk cache and restore from the archive.
        let exported = BackupManager.shared.readIconPack()
        XCTAssertNotNil(exported[key], "The pack should carry the icon bitmap")
        XCTAssertNotNil(exported[key + BackupManager.iconMetaSuffix],
            "The pack should carry the .meta sidecar — without it the restored bitmap can never be read back")

        try FileManager.default.removeItem(at: cacheDir)
        apply(makeArchive(icons: BackupManager.IconPack(entries: exported)))

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(key).path),
            "The bitmap should be restored")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(key + BackupManager.iconMetaSuffix).path),
            "The sidecar should be restored")
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light),
            "A restored icon should actually be readable from the cache — this is BUG-9")
    }

    func testIconPackKeyValidationAcceptsSidecarsButStillRejectsTraversal() {
        let key = String(repeating: "ab", count: 32)
        XCTAssertTrue(BackupManager.isValidIconPackKey(key), "A bare digest should be accepted")
        XCTAssertTrue(BackupManager.isValidIconPackKey(key + ".meta"), "A .meta sidecar should be accepted")

        for hostile in ["../../../evil.meta", "../evil", "/etc/passwd.meta", ".meta",
                        String(repeating: "z", count: 64) + ".meta", key + ".meta.meta"] {
            XCTAssertFalse(BackupManager.isValidIconPackKey(hostile), "Should be rejected: \(hostile)")
        }
    }
}
