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
        let size = NSSize(width: iconSize, height: iconSize)

        // Use NSImage(size:flipped:drawingHandler:) instead of lockFocus/unlockFocus — safer and more modern.
        let image = NSImage(size: size, flipped: false) { rect -> Bool in
            let clipPath = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
            clipPath.addClip()

            let workspace = NSWorkspace.shared
            for index in 0..<min(apps.count, gridSize * gridSize) {
                let row = index / gridSize
                let col = index % gridSize
                let icon = apps[index].icon ?? workspace.icon(forFile: apps[index].path)
                let cellRect = NSRect(x: CGFloat(col) * cellSize,
                                      y: CGFloat(gridSize - 1 - row) * cellSize,
                                      width: cellSize, height: cellSize)
                icon.draw(in: cellRect, from: NSRect.zero, operation: .copy, fraction: 1.0)
            }
            return true
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
        let iconsByPath = Dictionary(uniqueKeysWithValues: loadedIcons)
        var order = displayOrder
        for i in order.indices where iconsByPath[order[i].path] != nil {
            order[i].icon = iconsByPath[order[i].path]
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
