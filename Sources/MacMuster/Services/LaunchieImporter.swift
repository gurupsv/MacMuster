import Foundation

/// Imports a Launchie (a similar app-launcher's) settings export into MacMuster's folder model.
///
/// Launchie's export is a different JSON shape entirely from `BackupManager.BackupArchive` — no
/// checksum wrapper, and a `settings` block full of concepts MacMuster has no equivalent for
/// (hotkeys, window style, quick access, per-folder sort mode). Only the parts with a real
/// MacMuster counterpart are imported: folder/app membership and grid ordering. Everything else
/// in the file is simply never decoded — `Codable` only reads the fields a struct declares.
@MainActor
final class LaunchieImporter {
    static let shared = LaunchieImporter()
    private init() {}

    // MARK: - Source Shape

    struct LaunchieArchive: Codable {
        struct FoldersContainer: Codable {
            let folders: [LaunchieFolder]
        }
        struct LaunchieFolder: Codable {
            let id: String
            let name: String
            let apps: [String]
        }
        struct Layout: Codable {
            let positions: [String: Int]
        }

        let folders: FoldersContainer
        let layout: Layout
    }

    /// Prefix Launchie uses in `layout.positions` to mark a folder's grid slot rather than an
    /// app's. MacMuster has no such prefix: a folder's position lives under its bare UUID,
    /// because a folder's synthetic `Application.path` *is* its UUID
    /// (see `FolderStore.getFolderApplication`).
    private static let folderPositionPrefix = "folder:"

    // MARK: - Preview

    struct ImportPreview {
        let folders: [AppFolder]
        let customOrder: [String: Int]
        let folderCount: Int
        let appCount: Int
        let missingPaths: [String]
        var missingCount: Int { missingPaths.count }
    }

    /// Parses a Launchie export at `url` into MacMuster's model, or nil if it isn't one.
    ///
    /// Apps no longer on disk are dropped from their folder — mirroring
    /// `BackupManager.restore` — and returned in `missingPaths` so the caller can show them
    /// before the user commits.
    func parse(from url: URL) -> ImportPreview? {
        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(LaunchieArchive.self, from: data) else {
            return nil
        }

        var missing: [String] = []
        var folders: [AppFolder] = []

        for source in archive.folders.folders {
            var validApps: [String] = []
            for path in source.apps {
                if Self.appExists(at: path) {
                    validApps.append(path)
                } else {
                    missing.append(path)
                }
            }
            folders.append(AppFolder(id: source.id, name: source.name, appPaths: validApps))
        }

        // Grid order: keep an app's slot only if it's still installed, and a folder's slot only
        // if the folder actually made it through the loop above (an id Launchie's own layout
        // references but its folders list doesn't define would otherwise create an orphan entry).
        let knownFolderIds = Set(folders.map(\.id))
        var customOrder: [String: Int] = [:]
        for (key, position) in archive.layout.positions {
            if key.hasPrefix(Self.folderPositionPrefix) {
                let folderId = String(key.dropFirst(Self.folderPositionPrefix.count))
                guard knownFolderIds.contains(folderId) else { continue }
                customOrder[folderId] = position
            } else {
                guard Self.appExists(at: key) else { continue }
                customOrder[key] = position
            }
        }

        let appCount = folders.reduce(0) { $0 + $1.appPaths.count }
        return ImportPreview(
            folders: folders,
            customOrder: customOrder,
            folderCount: folders.count,
            appCount: appCount,
            missingPaths: missing
        )
    }

    /// Same existence/shape check `BackupManager.restore` uses: must exist, be a directory, and
    /// carry the `.app` suffix.
    private static func appExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
            && path.hasSuffix(".app")
    }

    // MARK: - Apply

    /// Writes the imported folders and grid order into MacMuster's live stores.
    ///
    /// Unlike `BackupManager.apply`, this never touches appearance/behavior settings or the icon
    /// cache: Launchie's export carries no MacMuster-specific settings to restore, and icons are
    /// regenerated from the app bundles as usual.
    func apply(preview: ImportPreview) {
        FolderStore.shared.folders = preview.folders
        PreferencesStore.shared.saveCustomOrder(preview.customOrder)
    }
}
