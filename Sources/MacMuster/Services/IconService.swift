import AppKit

/// Handles icon loading, folder icon composition, and caching.
@MainActor
final class IconService {
    static let shared = IconService()
    private let folderIconCache = NSCache<NSString, NSImage>()
    private init() {}
    
    func generateFolderIcon(_ apps: [Application], for folderId: String? = nil, gridSize: Int = 3) -> NSImage? {
        guard !apps.isEmpty else { return nil }
        
        // Check cache first
        if let folderId = folderId, let cached = folderIconCache.object(forKey: folderId as NSString) {
            return cached
        }
        
        let iconSize: CGFloat = 120
        let cellSize = iconSize / CGFloat(gridSize)
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        
        image.lockFocus()
        defer { image.unlockFocus() }
        let clipPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: NSSize(width: iconSize, height: iconSize)), xRadius: 20, yRadius: 20)
        clipPath.addClip()
        
        let workspace = NSWorkspace.shared
        for index in 0..<min(apps.count, gridSize * gridSize) {
            let row = index / gridSize
            let col = index % gridSize
            let icon = apps[index].icon ?? workspace.icon(forFile: apps[index].path)
            let rect = NSRect(x: CGFloat(col) * cellSize,
                              y: CGFloat(gridSize - 1 - row) * cellSize,
                              width: cellSize, height: cellSize)
            icon.draw(in: rect, from: NSRect.zero, operation: .copy, fraction: 1.0)
        }
        
        // Store to cache so subsequent calls hit the fast path
        if let folderId = folderId {
            folderIconCache.setObject(image, forKey: folderId as NSString)
        }
        return image
    }
    
    func loadMissingIcons(for displayOrder: [Application]) async -> [(String, NSImage)] {
        var pathToIndex: [String: Int] = [:]
        for (i, app) in displayOrder.enumerated() where app.icon == nil {
            pathToIndex[app.path] = i
        }
        guard !pathToIndex.isEmpty else { return [] }
        
        let missingPaths = Array(pathToIndex.keys)
        
        let loadedIcons: [(String, NSImage)] = await Task.detached(priority: .userInitiated) {
            let workspace = NSWorkspace.shared
            return missingPaths.map { ($0, workspace.icon(forFile: $0)) }
        }.value
        
        return loadedIcons
    }
    
    func updateIconsInPlace(for displayOrder: [Application], with loadedIcons: [(String, NSImage)]) -> [Application] {
        var order = displayOrder
        for (path, icon) in loadedIcons {
            if let idx = order.firstIndex(where: { $0.path == path }) {
                order[idx].icon = icon
            }
        }
        return order
    }
    
    func applicationsPreservingLoadedIcons(from scannedApps: [Application], loadedIconsByPath: [String: NSImage]) -> [Application] {
        scannedApps.map { scannedApp in
            var app = scannedApp
            if app.icon == nil, let loadedIcon = loadedIconsByPath[app.path] {
                app.icon = loadedIcon
            }
            return app
        }
    }

    func refreshFolderIcons(folders: [AppFolder], appPathIndex: [String: Application]) {
        for folder in folders {
            folderIconCache.removeObject(forKey: folder.id as NSString)
            let apps = folder.appPaths.compactMap { appPathIndex[$0] }
            _ = generateFolderIcon(apps, for: folder.id)
        }
    }
}
