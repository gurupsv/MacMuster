import Foundation

/// Handles folder creation, deletion, renaming, and recursive child-folder lookup.
@MainActor
final class FolderStore {
    static let shared = FolderStore()
    private init() {}
    
    /// Every write to this array encodes the whole folder list into `UserDefaults`, so mutators
    /// below copy → mutate → assign once, and the observer skips a write that changes nothing.
    /// `LibraryScanState.folders` mirrors back into this property from its own `didSet`; without
    /// the equality guard that echo re-encoded the list a further time on every folder edit, and
    /// per-field writes inside a mutator multiplied it (`moveAppInFolder` encoded ~5 times).
    var folders: [AppFolder] = [] {
        didSet {
            guard !Self.haveSameContent(folders, oldValue) else { return }
            saveFolders()
        }
    }
    
    /// `AppFolder ==` compares ids only, so `!=` would treat every membership edit as "unchanged"
    /// and silently skip the save; compare content instead.
    private static func haveSameContent(_ a: [AppFolder], _ b: [AppFolder]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.hasSameContent(as: $1) }
    }

    private func saveFolders() {
        PreferencesStore.shared.saveFolders(folders)
    }
    
    func createFolder(name: String, appPaths: [String]) -> AppFolder {
        let folder = AppFolder(name: name, appPaths: appPaths)
        folders.append(folder)
        return folder
    }
    
    func deleteFolder(folderId: String) {
        folders.removeAll { $0.id == folderId }
    }
    
    func renameFolder(folderId: String, newName: String) {
        var updated = folders
        guard let index = updated.firstIndex(where: { $0.id == folderId }) else { return }
        updated[index].name = newName
        updated[index].modifiedAt = Date()
        folders = updated
    }
    
    func addAppToFolder(_ appPath: String, folderId: String) {
        var updated = folders
        if Self.insert(appPath, into: folderId, in: &updated) { folders = updated }
    }
    
    func removeAppFromFolder(_ appPath: String, folderId: String) {
        var updated = folders
        if Self.remove(appPath, from: folderId, in: &updated) { folders = updated }
    }
    
    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) {
        var updated = folders
        let added = Self.insert(appPath, into: toFolderId, in: &updated)
        let removed = folderId != toFolderId && Self.remove(appPath, from: folderId, in: &updated)
        if added || removed { folders = updated }
    }

    /// Returns whether the array was touched. A missing folder or a non-`.app` path is a no-op;
    /// an already-present path is too, as before (no `modifiedAt` bump).
    private static func insert(_ appPath: String, into folderId: String, in folders: inout [AppFolder]) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folderId }),
              appPath.hasSuffix(".app"),
              !folders[index].appPaths.contains(appPath) else { return false }
        folders[index].appPaths.append(appPath)
        folders[index].modifiedAt = Date()
        return true
    }

    /// Returns whether the folder exists (matching the old behaviour of stamping `modifiedAt`
    /// even when the path was not a member).
    private static func remove(_ appPath: String, from folderId: String, in folders: inout [AppFolder]) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return false }
        folders[index].appPaths.removeAll { $0 == appPath }
        folders[index].modifiedAt = Date()
        return true
    }
    
    /// The apps belonging to one folder, filtered and ordered for display.
    ///
    /// Was `getAllAppsIncludingChildFolders`, which promised a traversal it never performed —
    /// `AppFolder` has no child-folder relationship to walk, only `appPaths`. Renamed rather than
    /// implemented: folder nesting is a feature to design, not a bug to fix, and a name that
    /// describes behaviour nobody wrote is the more immediate problem.
    func appsInFolder(
        for folderId: String,
        appPathIndex: [String: Application],
        hiddenAppPaths: Set<String>,
        customOrder: [String: Int],
        sortOption: ApplicationSorter.SortOption
    ) -> [Application] {
        guard let folder = folders.first(where: { $0.id == folderId }) else { return [] }

        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        let result: [Application] = containedApps.filter { !hiddenAppPaths.contains($0.path) }
        
        return ApplicationSorter.sort(result, by: sortOption, customOrder: customOrder)
    }
    
    func getFolderApplication(_ folder: AppFolder, containedApps: [Application], displayCount: Int? = nil) -> Application {
        // `id`/`path` are the bare folder UUID (no synthetic prefix needed — real app paths always
        // start with "/" and UUIDs never do, so collisions are impossible). `folderId` carries the
        // identity explicitly so callers don't need to parse it back out of `path`/`id`.
        let count = displayCount ?? containedApps.count
        return Application(
            id: folder.id,
            name: folder.name,
            path: folder.id,
            icon: nil, // Icon is handled by IconService
            installationDate: folder.createdAt,
            isFolder: true,
            containedApps: folder.appPaths,
            bundleDescription: String(localized: "\(count) app\(count == 1 ? "" : "s")"),
            folderId: folder.id
        )
    }
}
