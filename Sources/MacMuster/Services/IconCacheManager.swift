import Foundation
import AppKit
import CryptoKit

/// Manages persistent on-disk caching of decoded app icons.
/// Caches icons by app bundle path with modification-time tracking for automatic invalidation.
nonisolated final class IconCacheManager: @unchecked Sendable {
    static let shared = IconCacheManager()
    private init() {}

    // "v2": the original cache key scheme truncated the path hash to its first 8 bytes, so any
    // two apps sharing an 8-character path prefix (e.g. everything under /System/Applications/
    // or /Applications/) collided on the same cache file. Using a new directory name abandons
    // those corrupted entries rather than risk ever reading one back.
    private let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacMuster/icons-v2", isDirectory: true)

    private struct CacheEntry: Codable {
        let appPath: String
        let bundleMtime: Date
    }

    /// Tries to load a cached icon for the given app path. Returns nil if cache miss or stale.
    func cachedIcon(for appPath: String) -> NSImage? {
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

        // Load the cached icon image using NSKeyedUnarchiver
        do {
            let imageData = try Data(contentsOf: iconURL)
            if let image = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: imageData) {
                return image
            }
        } catch {
            // If unarchiving fails, delete corrupted cache entry
        }

        deleteCache(for: appPath)
        return nil
    }

    /// Saves an icon to cache along with bundle modification time.
    func cacheIcon(_ icon: NSImage, for appPath: String) {
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

        // Use NSKeyedArchiver for robust serialization of NSImage.
        // This preserves all image data, representations, and properties better than PNG.
        do {
            let iconData = try NSKeyedArchiver.archivedData(withRootObject: icon, requiringSecureCoding: false)
            try iconData.write(to: iconURL)

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
        }
    }

    // MARK: - Private

    /// Full SHA256 digest of the path, hex-encoded — fixed-length and collision-free regardless
    /// of how many paths share a common prefix (unlike a truncated byte-hex encoding, which
    /// previously collided for every app under the same top-level directory, e.g. all of
    /// /System/Applications/* hashed to the same key and shared one cache file).
    private func cacheKey(for appPath: String) -> String {
        let digest = SHA256.hash(data: Data(appPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func deleteCache(for appPath: String) {
        let cacheKey = cacheKey(for: appPath)
        let iconURL = cacheDir.appendingPathComponent(cacheKey, isDirectory: false)
        let metaURL = cacheDir.appendingPathComponent(cacheKey + ".meta", isDirectory: false)

        try? FileManager.default.removeItem(at: iconURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    private func currentBundleModificationTime(for appPath: String) -> Date? {
        guard FileManager.default.fileExists(atPath: appPath) else {
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: appPath)
        return attrs?[.modificationDate] as? Date
    }

    private func datesEqualIgnoringSubsecond(_ d1: Date, _ d2: Date) -> Bool {
        // Compare only to the second (ignore subsecond precision)
        return Int(d1.timeIntervalSince1970) == Int(d2.timeIntervalSince1970)
    }
}
