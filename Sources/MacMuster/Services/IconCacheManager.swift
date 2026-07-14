import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Manages persistent on-disk caching of decoded app icons.
/// Caches icons by app bundle path with modification-time tracking for automatic invalidation.
nonisolated final class IconCacheManager: @unchecked Sendable {
    static let shared = IconCacheManager()
    private init() {}

    /// In-memory layer in front of the disk cache. A cache hit here skips the SHA256 key
    /// derivation, 5 file-existence/stat syscalls, two disk reads (meta + icon), the JSON decode,
    /// and the `CGImageSource` PNG deserialization that the disk path would otherwise do every
    /// time — which matters for icons that scroll back into view and re-hit the cache.
    private let memoryCache = NSCache<NSString, NSImage>()

    /// In-memory mtime cache — avoids repeated fileExists + attributesOfItem syscalls for apps that
    /// are already in the display order. Cached mtimes are refreshed during pruneDeletedApps so they
    /// stay accurate and never drift stale without a fresh check.
    private let mtimeCache = NSCache<NSString, NSDate>()

    func cachedMtime(for appPath: String) -> Date? {
        return mtimeCache.object(forKey: appPath as NSString) as? Date
    }

    // "v2": the original cache key scheme truncated the path hash to its first 8 bytes, so any
    // two apps sharing an 8-character path prefix (e.g. everything under /System/Applications/
    // or /Applications/) collided on the same cache file. Using a new directory name abandons
    // those corrupted entries rather than risk ever reading one back.
    private let cacheDir: URL = IconCacheManager.calculateCacheDirectory()

    private static func calculateCacheDirectory() -> URL {
        guard let first = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/MacMuster/icons-v3", isDirectory: true)
        }
        return first.appendingPathComponent("MacMuster/icons-v3", isDirectory: true)
    }

    private struct CacheEntry: Codable {
        let appPath: String
        let bundleMtime: Date
    }

    /// Tries to load a cached icon for the given app path. Returns nil if cache miss or stale.
    ///
    /// Checks the in-memory cache first (zero I/O on a hit). Only on a memory miss does it fall
    /// through to the on-disk cache (stat + two disk reads + decode). A disk hit is then promoted
    /// into the memory cache so subsequent reads for the same path are free.
    func cachedIcon(for appPath: String) -> NSImage? {
        if let memory = memoryCache.object(forKey: appPath as NSString) {
            return memory
        }

        let cacheKey = cacheKey(for: appPath)
        let iconURL = cacheDir.appendingPathComponent(cacheKey, isDirectory: false)
        let metaURL = cacheDir.appendingPathComponent(cacheKey + ".meta", isDirectory: false)

        guard FileManager.default.fileExists(atPath: iconURL.path),
              FileManager.default.fileExists(atPath: metaURL.path) else {
            return nil
        }

        // Check if cache is fresh (bundle hasn't been modified since cache was written)
        guard let bundleMtime = currentBundleModificationTime(for: appPath) else {
            return nil
        }

        do {
            let metaData = try Data(contentsOf: metaURL)
            let entry = try JSONDecoder().decode(CacheEntry.self, from: metaData)
            // If bundle's mtime differs from cached mtime, cache is stale
            if !datesEqualIgnoringSubsecond(bundleMtime, entry.bundleMtime) {
                deleteCache(for: appPath)
                return nil
            }
        } catch {
            deleteCache(for: appPath)
            return nil
        }

        // Load the cached icon image from PNG
        do {
            let imageData = try Data(contentsOf: iconURL)
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            memoryCache.setObject(nsImage, forKey: appPath as NSString)
            return nsImage
        } catch {
            // If PNG decode fails, delete corrupted cache entry
        }

        deleteCache(for: appPath)
        return nil
    }

    /// Saves an icon to cache along with bundle modification time.
    ///
    /// Writes to both the in-memory cache (for instant subsequent reads) and the on-disk cache
    /// (so the icon survives relaunch).
    func cacheIcon(_ icon: NSImage, for appPath: String) {
        memoryCache.setObject(icon, forKey: appPath as NSString)

        guard let bundleMtime = currentBundleModificationTime(for: appPath) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let cacheKey = cacheKey(for: appPath)
        let iconURL = cacheDir.appendingPathComponent(cacheKey, isDirectory: false)
        let metaURL = cacheDir.appendingPathComponent(cacheKey + ".meta", isDirectory: false)

        // Store icon as PNG for smaller size, faster round-trip, and format-stability across OS versions.
        do {
            guard let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }
            guard let destination = CGImageDestinationCreateWithURL(iconURL as CFURL, "public.png" as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)

            let entry = CacheEntry(appPath: appPath, bundleMtime: bundleMtime)
            let metaData = try JSONEncoder().encode(entry)
            try metaData.write(to: metaURL)
        } catch {
            // Silent failure — cache write is not critical
        }
    }

    /// Returns all cached app paths along with their cached mtimes.
    /// Used for background refresh to detect stale entries.
    func cachedAppPaths() -> [(appPath: String, cachedMtime: Date)] {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else {
            return []
        }

        var results: [(String, Date)] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil) else {
            return []
        }

        for fileURL in contents {
            guard fileURL.pathExtension == "meta" else { continue }
            guard let metaData = try? Data(contentsOf: fileURL),
                  let entry = try? JSONDecoder().decode(CacheEntry.self, from: metaData) else {
                continue
            }

            results.append((entry.appPath, entry.bundleMtime))
        }

        return results
    }

    /// Deletes cache entries for apps that no longer exist on disk.
    func pruneDeletedApps(currentAppPaths: Set<String>) {
        let cachedApps = cachedAppPaths()
        for (appPath, _) in cachedApps {
            guard !currentAppPaths.contains(appPath) else { continue }
            deleteCache(for: appPath)
            mtimeCache.removeObject(forKey: appPath as NSString)
        }

        // Refresh mtime cache for remaining apps so subsequent reads skip fileExists/syscalls
        for appPath in currentAppPaths {
            if let mtime = currentBundleModificationTime(for: appPath) {
                mtimeCache.setObject(NSDate(timeIntervalSinceReferenceDate: mtime.timeIntervalSinceReferenceDate), forKey: appPath as NSString)
            }
        }
    }

    // MARK: - Private

    /// Full SHA256 digest of the path, hex-encoded — fixed-length and collision-free regardless
    /// of how many paths share a common prefix (unlike a truncated byte-hex encoding, which
    /// previously collided for every app under the same top-level directory, e.g. all of
    /// /System/Applications/* hashed to the same key and shared one cache file).
    func cacheKey(for appPath: String) -> String {
        let digest = SHA256.hash(data: Data(appPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func deleteCache(for appPath: String) {
        memoryCache.removeObject(forKey: appPath as NSString)

        let cacheKey = cacheKey(for: appPath)
        let iconURL = cacheDir.appendingPathComponent(cacheKey, isDirectory: false)
        let metaURL = cacheDir.appendingPathComponent(cacheKey + ".meta", isDirectory: false)

        try? FileManager.default.removeItem(at: iconURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    private func currentBundleModificationTime(for appPath: String) -> Date? {
        if let cached = mtimeCache.object(forKey: appPath as NSString) as? Date {
            return cached
        }

        guard FileManager.default.fileExists(atPath: appPath) else {
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: appPath)
        let mtime = attrs?[.modificationDate] as? Date
        if let mtime { mtimeCache.setObject(NSDate(timeIntervalSinceReferenceDate: mtime.timeIntervalSinceReferenceDate), forKey: appPath as NSString) }
        return mtime
    }

    private func datesEqualIgnoringSubsecond(_ d1: Date, _ d2: Date) -> Bool {
        // Compare only to the second (ignore subsecond precision)
        return Int(d1.timeIntervalSince1970) == Int(d2.timeIntervalSince1970)
    }
}
