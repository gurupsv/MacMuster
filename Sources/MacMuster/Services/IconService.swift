import AppKit

/// Handles icon loading, folder icon composition, and caching.
@MainActor
final class IconService {
    static let shared = IconService()
    private let folderIconCache = NSCache<NSString, NSImage>()
    private init() {}
    
    /// Rasterizes an app icon to a fixed-size bitmap on a background thread.
    /// Forces decode + downscale once, so SwiftUI just blits a small bitmap on the main thread.
    nonisolated static func rasterize(_ path: String, pixelSize: Int) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)

        // Fallback 1: Try to draw into a CGContext (works for most icons)
        var proposed = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        if let cg = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
           let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize,
                               bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
            if let scaled = ctx.makeImage() {
                return NSImage(cgImage: scaled, size: NSSize(width: pixelSize, height: pixelSize))
            }
        }

        // Fallback 2: If CGContext approach fails, try to resize the icon directly using NSImage
        let resized = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        resized.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                  from: NSRect.zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
    
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
        let missingPaths = displayOrder.compactMap { app in
            app.icon == nil ? app.path : nil
        }
        guard !missingPaths.isEmpty else { return [] }

        // Each icon loads from cache (instant) or decodes+downscales (background).
        // Fan the batch out across the cooperative thread pool instead of one at a time.
        return await withTaskGroup(of: (String, NSImage).self) { group in
            for path in missingPaths {
                group.addTask(priority: .userInitiated) {
                    (path, Self.loadOrDecodeIcon(path))
                }
            }
            var results: [(String, NSImage)] = []
            results.reserveCapacity(missingPaths.count)
            for await pair in group {
                results.append(pair)
            }
            return results
        }
    }

    /// Loads icon from cache if fresh, otherwise decodes fresh and caches.
    nonisolated private static func loadOrDecodeIcon(_ path: String) -> NSImage {
        if let cached = IconCacheManager.shared.cachedIcon(for: path) {
            return cached
        }

        let icon = Self.rasterize(path, pixelSize: AppMetrics.iconRasterPixelSizePx)
        IconCacheManager.shared.cacheIcon(icon, for: path)
        return icon
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

    /// Refreshes folder icons. Only folders whose member app icons are in `changedAppPaths` are
    /// regenerated — the previous behavior evicted and regenerated *every* folder on every icon
    /// batch, which was O(folders × icon-load-passes) even when none of a folder's members changed.
    /// Pass an empty set to regenerate all folders (e.g. on a full reload where icons were reset).
    func refreshFolderIcons(folders: [AppFolder], appPathIndex: [String: Application], changedAppPaths: Set<String>) {
        for folder in folders {
            // Skip folders whose member app icons weren't touched in this batch.
            if !changedAppPaths.isEmpty {
                let folderAffected = folder.appPaths.contains { changedAppPaths.contains($0) }
                guard folderAffected else { continue }
            }

            folderIconCache.removeObject(forKey: folder.id as NSString)
            let apps = folder.appPaths.compactMap { appPathIndex[$0] }
            _ = generateFolderIcon(apps, for: folder.id)
        }
    }
}
