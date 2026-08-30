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

    /// On-disk container. The checksum covers `payload`'s bytes **exactly as written**, so
    /// verification never has to re-encode the archive to check it.
    ///
    /// That indirection is the whole point. The previous design stored the digest *inside* the
    /// archive and hashed the whole file, which cannot work: the digest would have to cover itself.
    /// Re-encoding the decoded archive to work around that is no fix either, because the encoding
    /// is not byte-stable across processes — `hiddenAppPaths` is a `Set<String>`, and a Set encodes
    /// to a JSON array in iteration order, which depends on per-process hash seeding.
    /// Hashing an opaque byte blob sidesteps both problems.
    struct BackupFile: Codable {
        let checksum: String
        let payload: Data
    }

    struct BackupArchive: Codable {
        let schemaVersion: Int
        /// Legacy field, retained only so archives written by older builds still decode.
        /// Integrity is now carried by `BackupFile.checksum` over the payload bytes; nothing
        /// reads this. Always written as "".
        var checksum: String
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
        let launchAnimationDirection: String
        let launchAnimationEnabled: Bool
        let presentationMode: String
        let tintColor: String
        let tintStrength: Double
        let showHiddenApps: Bool
        let launchMode: String
        // Schema v2: recently-updated badge state. The mtime baseline (`knownBundleMtimes`)
        // is long-lived; the badge membership (`recentlyUpdatedPaths`) is age-evicted. Both
        // round-trip so a restored backup continues badging apps that updated just before
        // the backup was taken, and measures future deltas against the backed-up baseline.
        let knownBundleMtimes: [String: Date]
        let recentlyUpdatedPaths: [String: Date]
        let icons: IconPack

        init(
            schemaVersion: Int = 2,
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
            launchAnimationDirection: String = "zoomOut",
            launchAnimationEnabled: Bool = true,
            presentationMode: String = "Glass",
            tintColor: String = "#0000FF",
            tintStrength: Double = 0.0,
            showHiddenApps: Bool = false,
            launchMode: String = "Window",
            knownBundleMtimes: [String: Date] = [:],
            recentlyUpdatedPaths: [String: Date] = [:],
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
            self.launchAnimationDirection = launchAnimationDirection
            self.launchAnimationEnabled = launchAnimationEnabled
            self.presentationMode = presentationMode
            self.tintColor = tintColor
            self.tintStrength = tintStrength
            self.showHiddenApps = showHiddenApps
            self.launchMode = launchMode
            self.knownBundleMtimes = knownBundleMtimes
            self.recentlyUpdatedPaths = recentlyUpdatedPaths
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
        panel.prompt = String(localized: "Save")
        panel.title = String(localized: "Export MacMuster Backup")
        panel.nameFieldStringValue = "MacMuster-Backup.json"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let folders = FolderStore.shared.folders
        let customOrder = PreferencesStore.shared.loadCustomOrder() ?? [:]
        let hiddenAppPaths = PreferencesStore.shared.loadHiddenApps() ?? Set<String>()
        let sortOption = PreferencesStore.shared.loadSortOption() ?? ApplicationSorter.SortOption.name.rawValue
        let iconSize = PreferencesStore.shared.loadIconSize() ?? IconSize.medium.rawValue
        let showFoldersFirst = PreferencesStore.shared.loadShowFoldersFirst()
        let refreshInterval = PreferencesStore.shared.loadRefreshInterval() ?? ScanMetrics.refreshIntervalDefault
        let currentFolderId = PreferencesStore.shared.loadCurrentFolderId()
        let customDirectories = PreferencesStore.shared.loadCustomDirectories() ?? []

        // Glow settings
        let glowEnabled = PreferencesStore.shared.loadGlowEnabled()
        let glowColor = PreferencesStore.shared.loadGlowColor() ?? "#ffffff"
        let glowIntensity = PreferencesStore.shared.loadGlowIntensity() ?? GlowMetrics.glowIntensityDefault
        let glowWidth = PreferencesStore.shared.loadGlowWidth() ?? GlowMetrics.glowWidthDefault

        // Font settings
        let fontFamily = PreferencesStore.shared.loadFontFamily() ?? "System"
        let fontSize = PreferencesStore.shared.loadFontSize() ?? 14.0
        let fontWeight = PreferencesStore.shared.loadFontWeight() ?? "Regular"

        // Other settings
        let pressFeedbackEnabled = PreferencesStore.shared.loadPressFeedbackEnabled()
        let recentAppsEnabled = PreferencesStore.shared.loadRecentAppsEnabled()
        let overlayOpacity = PreferencesStore.shared.loadOverlayOpacity() ?? GlowMetrics.overlayOpacityDefault
        let showInDock = PreferencesStore.shared.loadShowInDock()

        // Previously-missing settings (Bug #4)
        let launchAnimationDirection = PreferencesStore.shared.loadLaunchAnimationDirection() ?? "zoomOut"
        let launchAnimationEnabled = PreferencesStore.shared.loadLaunchAnimationEnabled()
        let presentationMode = PreferencesStore.shared.loadPresentationMode() ?? "Glass"
        let tintColor = PreferencesStore.shared.loadTintColor() ?? "#0000FF"
        let tintStrength = PreferencesStore.shared.loadTintStrength() ?? 0.0
        let showHiddenApps = PreferencesStore.shared.loadShowHiddenApps()
        let launchMode = PreferencesStore.shared.loadLaunchMode() ?? "Window"

        // Schema v2: recently-updated badge state. Backed up so a restored backup continues
        // badging apps that updated just before the backup was taken, and so the mtime baseline
        // survives a restore-and-rescan without re-badging every app as updated.
        let knownBundleMtimes = PreferencesStore.shared.loadKnownBundleMtimes() ?? [:]
        let recentlyUpdatedPaths = PreferencesStore.shared.loadRecentlyUpdatedPaths() ?? [:]

        // Icon pack — read PNGs from disk cache and encode as base64 Data
        let iconEntries = readIconPack()

        let archive = BackupArchive(
            schemaVersion: 2,
            checksum: "", // legacy field; integrity lives on the BackupFile container
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
            launchAnimationDirection: launchAnimationDirection,
            launchAnimationEnabled: launchAnimationEnabled,
            presentationMode: presentationMode,
            tintColor: tintColor,
            tintStrength: tintStrength,
            showHiddenApps: showHiddenApps,
            launchMode: launchMode,
            knownBundleMtimes: knownBundleMtimes,
            recentlyUpdatedPaths: recentlyUpdatedPaths,
            icons: IconPack(entries: iconEntries)
        )

        do {
            try Self.encodeArchive(archive).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Encoding / Decoding

    /// Encodes `archive` into the on-disk `BackupFile` container, checksum included.
    /// Split out from `export()` (which is gated behind an `NSSavePanel`) so the integrity
    /// round-trip is reachable from tests.
    nonisolated static func encodeArchive(_ archive: BackupArchive) throws -> Data {
        let payload = try JSONEncoder().encode(archive)
        let file = BackupFile(checksum: sha256Hex(payload), payload: payload)
        return try JSONEncoder().encode(file)
    }

    /// Decodes archive bytes, verifying integrity when the container carries a checksum.
    /// Returns nil when the data is not a backup at all, or when verification fails.
    ///
    /// Falls back to decoding a bare `BackupArchive` for archives written before the container
    /// existed. Those carry no usable checksum — the old scheme never produced a verifiable one —
    /// so they are accepted unverified rather than rejected outright.
    nonisolated static func decodeArchive(from data: Data) -> BackupArchive? {
        if let file = try? JSONDecoder().decode(BackupFile.self, from: data) {
            guard sha256Hex(file.payload) == file.checksum else {
                return nil // Corrupted or truncated in transit.
            }
            return try? JSONDecoder().decode(BackupArchive.self, from: file.payload)
        }
        return try? JSONDecoder().decode(BackupArchive.self, from: data)
    }

    nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Restore

    func restore(from url: URL) -> BackupPreview? {
        guard let data = try? Data(contentsOf: url),
              let archive = Self.decodeArchive(from: data) else {
            return nil // Not a backup, or failed integrity verification.
        }

        // Validate app paths against disk
        let allAppPaths = Set(archive.appFolders.flatMap { $0.appPaths })

        var valid: Set<String> = []
        var missing: Set<String> = []

        for path in allAppPaths {
            // One stat answers both "does it exist" and "is it a directory" — an .app bundle
            // must be both, plus carry the .app suffix.
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue,
                  path.hasSuffix(".app") else {
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

        // Recreate folders — remove missing app paths from each folder's membership.
        //
        // Copy the decoded folder and edit the one field that changes, rather than building a
        // fresh AppFolder from its parts: that initializer stamps `createdAt`/`modifiedAt` with
        // `Date()`, so every restored folder silently lost the timestamps the archive had
        // faithfully carried. Dropping apps that are no longer installed is a restore-time
        // adaptation, not a user edit, so `modifiedAt` is preserved too — the restored state
        // should read as the state that was backed up.
        for folder in archive.appFolders {
            var cleanedFolder = folder
            cleanedFolder.appPaths = folder.appPaths.filter { preview.validAppPaths.contains($0) }
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

        // Previously-missing settings (Bug #4)
        PreferencesStore.shared.saveLaunchAnimationDirection(archive.launchAnimationDirection)
        PreferencesStore.shared.saveLaunchAnimationEnabled(archive.launchAnimationEnabled)
        PreferencesStore.shared.savePresentationMode(archive.presentationMode)
        PreferencesStore.shared.saveTintColor(archive.tintColor)
        PreferencesStore.shared.saveTintStrength(archive.tintStrength)
        PreferencesStore.shared.saveShowHiddenApps(archive.showHiddenApps)
        PreferencesStore.shared.saveLaunchMode(LaunchMode(rawValue: archive.launchMode) ?? .window)

        // Schema v2: restore the recently-updated badge state. The mtime baseline is restored
        // verbatim so the next scan measures deltas against the backed-up baseline rather than
        // treating every app as freshly updated. The badge membership is restored too, but
        // age-eviction on the next `loadFromDefaults` drops entries that expired while the
        // backup was on the shelf.
        PreferencesStore.shared.saveKnownBundleMtimes(archive.knownBundleMtimes)
        PreferencesStore.shared.saveRecentlyUpdatedPaths(archive.recentlyUpdatedPaths)

        // Restore icon cache — write PNGs from archive to disk cache
        restoreIconPack(from: archive.icons)
    }

    // MARK: - Private

    /// Whether `key` is a filename `IconCacheManager` could actually have written: the bare
    /// 64-character lowercase hex SHA256 digest it uses as a cache filename, nothing else.
    ///
    /// Icon-pack keys arrive from an untrusted backup file and are appended to the cache
    /// directory path, so anything looser is an arbitrary-file-write primitive — a key of
    /// `../../../../foo` escapes the cache directory entirely, and `~/Library/LaunchAgents`
    /// is reachable that way. Matching the exact expected shape rejects path separators,
    /// `..`, absolute paths, and empty keys as a side effect of being strict, rather than
    /// trying to enumerate bad input.
    /// Explicit ASCII ranges rather than `isHexDigit`/`isNumber`, which also accept uppercase
    /// and non-ASCII digits (`isNumber` is true for "٣"). The cache only ever writes lowercase
    /// ASCII hex, so that is exactly what is accepted.
    nonisolated static func isValidIconCacheKey(_ key: String) -> Bool {
        key.count == 64 && key.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    nonisolated static let iconMetaSuffix = ".meta"

    /// Whether `name` is a filename the icon cache could have written — either the bitmap (a bare
    /// 64-char hex digest) or its `.meta` sidecar. Both halves travel in the pack, and both become
    /// write paths on restore, so both go through the same shape check. Anything else — path
    /// separators, `..`, absolute paths, an empty name — fails by not matching the shape, which
    /// is what keeps this a whitelist rather than an attempt to enumerate bad input.
    nonisolated static func isValidIconPackKey(_ name: String) -> Bool {
        guard name.hasSuffix(iconMetaSuffix) else { return isValidIconCacheKey(name) }
        return isValidIconCacheKey(String(name.dropLast(iconMetaSuffix.count)))
    }

    /// Reads the on-disk icon cache into pack entries. Internal rather than private so a test can
    /// assert what an export actually carries — the bug this guards against (a pack missing its
    /// `.meta` sidecars) is invisible from the outside until a restore silently does nothing.
    func readIconPack() -> [String: Data] {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v4", isDirectory: true)

        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return [:] }

        var entries: [String: Data] = [:]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil) else { return [:] }

        for fileURL in contents {
            // The v4 cache stores each icon as a bare SHA256 hex filename **plus** a `.meta` JSON
            // sidecar, and `IconCacheManager.cachedIcon` requires both to be present before it
            // will read an entry. The sidecars used to be skipped here, which made the whole icon
            // pack inert: a restore wrote bitmaps with no metadata, so every one of them was
            // ignored and re-decoded from scratch — the largest part of a backup, carried for
            // nothing. Take both halves, accepting only names the cache itself could have
            // written so the archive can never carry a key `restoreIconPack` would refuse.
            let name = fileURL.lastPathComponent
            guard Self.isValidIconPackKey(name) else { continue }

            do {
                entries[name] = try Data(contentsOf: fileURL)
            } catch {
                // Skip corrupted icon files silently
            }
        }

        // A bitmap without its sidecar can never be read back, and a sidecar without its bitmap
        // is dead weight. Ship only complete pairs rather than bytes that cannot be used.
        return entries.filter { key, _ in
            key.hasSuffix(Self.iconMetaSuffix)
                ? entries[String(key.dropLast(Self.iconMetaSuffix.count))] != nil
                : entries[key + Self.iconMetaSuffix] != nil
        }
    }

    private func restoreIconPack(from iconPack: IconPack) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v4", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        for (key, imageData) in iconPack.entries {
            // The key comes from an untrusted file and is about to become a write path.
            guard Self.isValidIconPackKey(key) else { continue }

            let iconURL = cacheDir.appendingPathComponent(key, isDirectory: false)

            // Belt and braces: even a key that passed the shape check must still land inside
            // the cache directory. Cheap, and it survives someone loosening the check above.
            guard iconURL.standardizedFileURL.deletingLastPathComponent().path
                    == cacheDir.standardizedFileURL.path else { continue }

            do {
                try imageData.write(to: iconURL)
            } catch {
                // Skip failed writes silently — icons are non-critical
            }
        }
    }
}
