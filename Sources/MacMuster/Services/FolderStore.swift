import Foundation

/// Handles folder creation, deletion, renaming, and recursive child-folder lookup.
@MainActor
final class FolderStore {
    static let shared = FolderStore()
    private init() {}
    
    var folders: [AppFolder] = [] {
        didSet { saveFolders() }
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
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders[index].name = newName
            folders[index].modifiedAt = Date()
        }
    }
    
    func addAppToFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        guard appPath.hasSuffix(".app") else { return }
        if !folders[index].appPaths.contains(appPath) {
            folders[index].appPaths.append(appPath)
            folders[index].modifiedAt = Date()
        }
    }
    
    func removeAppFromFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[index].appPaths.removeAll { $0 == appPath }
        folders[index].modifiedAt = Date()
    }
    
    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) {
        addAppToFolder(appPath, folderId: toFolderId)
        if folderId != toFolderId {
            removeAppFromFolder(appPath, folderId: folderId)
        }
    }
    
    func getAllAppsIncludingChildFolders(
        for folderId: String,
        appPathIndex: [String: Application],
        hiddenAppPaths: Set<String>,
        customOrder: [String: Int],
        sortOption: ApplicationSorter.SortOption
    ) -> [Application] {
        guard folders.first(where: { $0.id == folderId }) != nil else { return [] }

        let containedApps = folders.first(where: { $0.id == folderId })!.appPaths.compactMap { appPathIndex[$0] }
        var result: [Application] = containedApps.filter { !hiddenAppPaths.contains($0.path) }
        
        if !customOrder.isEmpty {
            result.sort {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) {
                case (nil, nil): return false
                case (nil, _):   return false
                case (_, nil):   return true
                case (let av?, let bv?): return av < bv
                }
            }
        } else {
            result = ApplicationSorter.sort(result, by: sortOption)
        }
        
        return result
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
            bundleDescription: "\(count) app\(count == 1 ? "" : "s")",
            folderId: folder.id
        )
    }
}
