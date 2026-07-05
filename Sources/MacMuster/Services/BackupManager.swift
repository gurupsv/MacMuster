import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Handles backup export and restore of MacMuster library state (folders, ordering, icons, settings).
@MainActor
final class BackupManager {
    static let shared = BackupManager()
    private init() {}

    // MARK: - Archive Types

    struct BackupArchive: Codable {
        let schemaVersion: Int
        var checksum: String // SHA256 hex digest of the final JSON data for integrity verification on restore; mutable so we can compute it after encoding and re-encode with the actual value.
        let appFolders: [AppFolder]
        let customOrder: [String: Int]
        let hiddenAppPaths: Set<String>
        let sortOption: String
        let iconSize: String
        let showFoldersFirst: Bool
        let refreshInterval: Double
        let currentFolderId: String?
        let customDirectories: [String]
        let glowEnabled: Bool
        let glowColor: String
        let glowIntensity: Double
        let glowWidth: Double
        let fontFamily: String
        let fontSize: Double
        let fontWeight: String
        let pressFeedbackEnabled: Bool
        let recentAppsEnabled: Bool
        let overlayOpacity: Double
        let showInDock: Bool
        let icons: IconPack

        init(
            schemaVersion: Int = 1,
            checksum: String = "", // computed at export time; empty on import from older schemas
            appFolders: [AppFolder],
            customOrder: [String: Int],
            hiddenAppPaths: Set<String>,
            sortOption: String,
            iconSize: String,
            showFoldersFirst: Bool,
            refreshInterval: Double,
            currentFolderId: String?,
            customDirectories: [String],
            glowEnabled: Bool,
            glowColor: String,
            glowIntensity: Double,
            glowWidth: Double,
            fontFamily: String,
            fontSize: Double,
            fontWeight: String,
            pressFeedbackEnabled: Bool,
            recentAppsEnabled: Bool,
            overlayOpacity: Double,
            showInDock: Bool,
            icons: IconPack
        ) {
            self.schemaVersion = schemaVersion
            self.checksum = checksum
            self.appFolders = appFolders
            self.customOrder = customOrder
            self.hiddenAppPaths = hiddenAppPaths
            self.sortOption = sortOption
            self.iconSize = iconSize
            self.showFoldersFirst = showFoldersFirst
            self.refreshInterval = refreshInterval
            self.currentFolderId = currentFolderId
            self.customDirectories = customDirectories
            self.glowEnabled = glowEnabled
            self.glowColor = glowColor
            self.glowIntensity = glowIntensity
            self.glowWidth = glowWidth
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.pressFeedbackEnabled = pressFeedbackEnabled
            self.recentAppsEnabled = recentAppsEnabled
            self.overlayOpacity = overlayOpacity
            self.showInDock = showInDock
            self.icons = icons
        }
    }

    struct IconPack: Codable {
        let entries: [String: Data]

        init(entries: [String: Data]) {
            self.entries = entries
        }
    }

    // MARK: - Restore Preview

    struct BackupPreview {
        let archive: BackupArchive
        let validAppPaths: Set<String>
        let missingAppPaths: Set<String>
        let folderCount: Int
        let appCount: Int

        init(archive: BackupArchive, validAppPaths: Set<String>, missingAppPaths: Set<String>) {
            self.archive = archive
            self.validAppPaths = validAppPaths
            self.missingAppPaths = missingAppPaths
            self.folderCount = archive.appFolders.count
            self.appCount = validAppPaths.count + archive.appFolders.flatMap { $0.appPaths }.count
        }
    }

    // MARK: - Export

    func export() -> URL? {
        let jsonType = UniformTypeIdentifiers.UTType.json

        let panel = NSSavePanel()
        panel.allowedContentTypes = [jsonType]
        panel.prompt = "Save"
        panel.title = "Export MacMuster Backup"
        panel.nameFieldStringValue = "MacMuster-Backup.json"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let folders = FolderStore.shared.folders
        let customOrder = PreferencesStore.shared.loadCustomOrder() ?? [:]
        let hiddenAppPaths = PreferencesStore.shared.loadHiddenApps() ?? Set<String>()
        let sortOption = PreferencesStore.shared.loadSortOption() ?? ApplicationSorter.SortOption.name.rawValue
        let iconSize = PreferencesStore.shared.loadIconSize() ?? IconSize.medium.rawValue
        let showFoldersFirst = PreferencesStore.shared.loadShowFoldersFirst()
        let refreshInterval = PreferencesStore.shared.loadRefreshInterval() ?? 30.0
        let currentFolderId = PreferencesStore.shared.loadCurrentFolderId()
        let customDirectories = PreferencesStore.shared.loadCustomDirectories() ?? []

        // Glow settings
        let glowEnabled = PreferencesStore.shared.loadGlowEnabled()
        let glowColor = PreferencesStore.shared.loadGlowColor() ?? "#ffffff"
        let glowIntensity = PreferencesStore.shared.loadGlowIntensity() ?? AppMetrics.glowIntensityDefault
        let glowWidth = PreferencesStore.shared.loadGlowWidth() ?? AppMetrics.glowWidthDefault

        // Font settings
        let fontFamily = PreferencesStore.shared.loadFontFamily() ?? "System"
        let fontSize = PreferencesStore.shared.loadFontSize() ?? 14.0
        let fontWeight = PreferencesStore.shared.loadFontWeight() ?? "Regular"

        // Other settings
        let pressFeedbackEnabled = PreferencesStore.shared.loadPressFeedbackEnabled()
        let recentAppsEnabled = PreferencesStore.shared.loadRecentAppsEnabled()
        let overlayOpacity = PreferencesStore.shared.loadOverlayOpacity() ?? AppMetrics.overlayOpacityDefault
        let showInDock = PreferencesStore.shared.loadShowInDock()

        // Icon pack — read PNGs from disk cache and encode as base64 Data
        let iconEntries = readIconPack()

        var archive = BackupArchive(
            schemaVersion: 1,
            checksum: "", // placeholder — will be computed after final encoding
            appFolders: folders,
            customOrder: customOrder,
            hiddenAppPaths: hiddenAppPaths,
            sortOption: sortOption,
            iconSize: iconSize,
            showFoldersFirst: showFoldersFirst,
            refreshInterval: refreshInterval,
            currentFolderId: currentFolderId,
            customDirectories: customDirectories,
            glowEnabled: glowEnabled,
            glowColor: glowColor,
            glowIntensity: glowIntensity,
            glowWidth: glowWidth,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            pressFeedbackEnabled: pressFeedbackEnabled,
            recentAppsEnabled: recentAppsEnabled,
            overlayOpacity: overlayOpacity,
            showInDock: showInDock,
            icons: IconPack(entries: iconEntries)
        )

        do {
            let initialJSON = try JSONEncoder().encode(archive) // encode with checksum placeholder
            // Compute SHA256 checksum of the JSON containing placeholder.
            let digest1 = SHA256.hash(data: initialJSON)
            let checksumHex = digest1.map { String(format: "%02x", $0) }.joined()
            archive.checksum = checksumHex
            // Re-encode with actual checksum inserted — produces a different JSON, so re-compute on the true final JSON.
            let finalJSON = try JSONEncoder().encode(archive) // encode with actual checksum now
            let finalChecksumHex = SHA256.hash(data: finalJSON).map { String(format: "%02x", $0) }.joined()
            archive.checksum = finalChecksumHex
            try finalJSON.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Restore

    func restore(from url: URL) -> BackupPreview? {
        var finalJSON: Data
        var archive: BackupArchive
        do {
            finalJSON = try Data(contentsOf: url)
            archive = try JSONDecoder().decode(BackupArchive.self, from: finalJSON)
        } catch {
            return nil // Cannot decode — invalid file format.
        }

        // Verify checksum integrity (skip if checksum is empty — older schema backups have no checksum).
        if !archive.checksum.isEmpty {
            let digest = SHA256.hash(data: finalJSON)
            let expectedChecksumHex = digest.map { String(format: "%02x", $0) }.joined()
            if archive.checksum != expectedChecksumHex {
                return nil // Checksum mismatch — file was corrupted or tampered.
            }
        }

        // Validate app paths against disk
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

        return BackupPreview(archive: archive, validAppPaths: valid, missingAppPaths: missing)
    }

    // MARK: - Apply Restore

    func apply(preview: BackupPreview) {
        let archive = preview.archive

        // Sanitize custom directories — only those that exist on disk are applied
        let validCustomDirectories = archive.customDirectories.filter { FileManager.default.fileExists(atPath: $0) }

        // Clean up folders before applying restored data
        FolderStore.shared.folders.removeAll()

        // Recreate folders — remove missing app paths from each folder's membership
        for folder in archive.appFolders {
            let cleanedPaths = folder.appPaths.filter { preview.validAppPaths.contains($0) }
            let cleanedFolder = AppFolder(
                id: folder.id,
                name: folder.name,
                appPaths: cleanedPaths,
                customIcon: folder.customIcon,
                parentFolderId: folder.parentFolderId
            )
            FolderStore.shared.folders.append(cleanedFolder)
        }

        // Restore settings to PreferencesStore
        PreferencesStore.shared.saveCustomOrder(archive.customOrder)
        PreferencesStore.shared.saveHiddenApps(archive.hiddenAppPaths)
        PreferencesStore.shared.saveSortOption(archive.sortOption)
        PreferencesStore.shared.saveIconSize(archive.iconSize)
        PreferencesStore.shared.saveShowFoldersFirst(archive.showFoldersFirst)
        PreferencesStore.shared.saveRefreshInterval(archive.refreshInterval)
        PreferencesStore.shared.saveCurrentFolderId(archive.currentFolderId)
        PreferencesStore.shared.saveCustomDirectories(validCustomDirectories)

        // Glow settings
        PreferencesStore.shared.saveGlowEnabled(archive.glowEnabled)
        PreferencesStore.shared.saveGlowColor(archive.glowColor)
        PreferencesStore.shared.saveGlowIntensity(archive.glowIntensity)
        PreferencesStore.shared.saveGlowWidth(archive.glowWidth)

        // Font settings
        PreferencesStore.shared.saveFontFamily(archive.fontFamily)
        PreferencesStore.shared.saveFontSize(archive.fontSize)
        PreferencesStore.shared.saveFontWeight(archive.fontWeight)

        // Other settings
        PreferencesStore.shared.savePressFeedbackEnabled(archive.pressFeedbackEnabled)
        PreferencesStore.shared.saveRecentAppsEnabled(archive.recentAppsEnabled)
        PreferencesStore.shared.saveOverlayOpacity(archive.overlayOpacity)
        PreferencesStore.shared.saveShowInDock(archive.showInDock)

        // Restore icon cache — write PNGs from archive to disk cache
        restoreIconPack(from: archive.icons)
    }

    // MARK: - Private

    private func readIconPack() -> [String: Data] {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v3", isDirectory: true)

        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return [:] }

        var entries: [String: Data] = [:]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil) else { return [:] }

        for fileURL in contents {
            guard fileURL.pathExtension == "png" else { continue }

            do {
                let data = try Data(contentsOf: fileURL)
                entries[fileURL.lastPathComponent] = data
            } catch {
                // Skip corrupted icon files silently
            }
        }

        return entries
    }

    private func restoreIconPack(from iconPack: IconPack) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v3", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        for (key, imageData) in iconPack.entries {
            let iconURL = cacheDir.appendingPathComponent(key, isDirectory: false)

            do {
                try imageData.write(to: iconURL)
            } catch {
                // Skip failed writes silently — icons are non-critical
            }
        }
    }
}
