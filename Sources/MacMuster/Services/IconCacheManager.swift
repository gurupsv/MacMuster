import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Which light/dark variant an icon was rendered under.
///
/// Resolving the appearance is main-actor work (`NSApp.effectiveAppearance`), but icons are
/// decoded and cached on the cooperative pool. So callers resolve this once on the main actor
/// and pass the value down — the cache and the rasterizer never read `NSApp` themselves.
/// Carrying it explicitly also pins one batch to one appearance: if the user toggles the theme
/// mid-decode, every icon in flight still gets stored under the key it was rendered for,
/// instead of writing a dark bitmap into the light slot where nothing would ever correct it.
enum IconAppearance: String, CaseIterable, Codable, Sendable {
    case light
    case dark

    /// The appearance currently in effect.
    ///
    /// `NSApp` is an implicitly-unwrapped optional that is nil until the application object
    /// exists — never the case in the running app, but true in unit tests and headless use.
    /// Falling back to light beats trapping.
    @MainActor
    static var current: IconAppearance {
        guard let app = NSApp else { return .light }
        return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    var nsAppearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}

/// Manages persistent on-disk caching of decoded app icons.
/// Caches icons by app bundle path with modification-time tracking for automatic invalidation.
/// Icon variants for light and dark appearances are cached separately with appearance-aware keys.
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
    //
    // "v4": icons are now cached per appearance, so each app has up to two entries (light and
    // dark). v3 entries recorded only `appPath`, which made the two variants indistinguishable
    // once read back off disk — every app appeared twice in `cachedAppPaths()` with no way to
    // tell which was which. A new directory abandons those ambiguous entries; `CacheEntry` now
    // records the appearance it was rendered under.
    private let cacheDir: URL = IconCacheManager.calculateCacheDirectory()

    private static func calculateCacheDirectory() -> URL {
        guard let first = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/MacMuster/icons-v4", isDirectory: true)
        }
        return first.appendingPathComponent("MacMuster/icons-v4", isDirectory: true)
    }

    /// Cache directories abandoned by earlier key schemes. Each bump orphaned its predecessor
    /// (v3 alone runs to ~12 MB for a typical library), and nothing ever reclaimed them.
    private static let supersededCacheDirNames = ["icons", "icons-v2", "icons-v3"]

    /// Removes cache directories left behind by previous key schemes. Safe to call repeatedly;
    /// each name is a directory this class itself created, so there is nothing else to hit.
    func removeSupersededCaches() {
        let parent = cacheDir.deletingLastPathComponent()
        for name in Self.supersededCacheDirNames {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name, isDirectory: true))
        }
    }

    private struct CacheEntry: Codable {
        let appPath: String
        let bundleMtime: Date
        /// Appearance this icon was rasterized under. Without it, the two per-appearance
        /// variants of one app are indistinguishable when enumerated off disk.
        let appearance: IconAppearance
    }

    /// Tries to load a cached icon for the given app path. Returns nil if cache miss or stale.
    ///
    /// Checks the in-memory cache first (zero I/O on a hit). Only on a memory miss does it fall
    /// through to the on-disk cache (stat + two disk reads + decode). A disk hit is then promoted
    /// into the memory cache so subsequent reads for the same path are free.
    func cachedIcon(for appPath: String, appearance: IconAppearance) -> NSImage? {
        let memKey = memoryCacheKey(appPath, appearance: appearance)
        if let memory = memoryCache.object(forKey: memKey) {
            return memory
        }

        let cacheKey = cacheKey(for: appPath, appearance: appearance)
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
                deleteCache(for: appPath, appearance: appearance)
                return nil
            }
        } catch {
            deleteCache(for: appPath, appearance: appearance)
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
            memoryCache.setObject(nsImage, forKey: memKey)
            return nsImage
        } catch {
            // If PNG decode fails, delete corrupted cache entry
        }

        deleteCache(for: appPath, appearance: appearance)
        return nil
    }

    /// Saves an icon to cache along with bundle modification time.
    ///
    /// Writes to both the in-memory cache (for instant subsequent reads) and the on-disk cache
    /// (so the icon survives relaunch).
    func cacheIcon(_ icon: NSImage, for appPath: String, appearance: IconAppearance) {
        let memKey = memoryCacheKey(appPath, appearance: appearance)
        memoryCache.setObject(icon, forKey: memKey)

        guard let bundleMtime = currentBundleModificationTime(for: appPath) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let cacheKey = cacheKey(for: appPath, appearance: appearance)
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

            let entry = CacheEntry(appPath: appPath, bundleMtime: bundleMtime, appearance: appearance)
            let metaData = try JSONEncoder().encode(entry)
            try metaData.write(to: metaURL)
        } catch {
            // Silent failure — cache write is not critical
        }
    }

    /// Returns cached app paths along with their cached mtimes, for the appearance currently
    /// in effect. Used by the background refresh to detect stale entries.
    ///
    /// Filtering by appearance is what keeps each app path appearing **at most once**: an app
    /// that has been rendered under both light and dark has two cache entries, and returning
    /// both would hand callers a list with duplicate keys.
    func cachedAppPaths(appearance: IconAppearance) -> [(appPath: String, cachedMtime: Date)] {
        allCacheEntries()
            .filter { $0.appearance == appearance }
            .map { ($0.appPath, $0.bundleMtime) }
    }

    /// Every distinct app path in the cache, across all appearances. Used for pruning, which
    /// must see an app even if its only cached variant belongs to the other appearance.
    func allCachedAppPaths() -> Set<String> {
        Set(allCacheEntries().map(\.appPath))
    }

    private func allCacheEntries() -> [CacheEntry] {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else {
            return []
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [CacheEntry] = []
        for fileURL in contents {
            guard fileURL.pathExtension == "meta" else { continue }
            guard let metaData = try? Data(contentsOf: fileURL),
                  let entry = try? JSONDecoder().decode(CacheEntry.self, from: metaData) else {
                continue
            }

            results.append(entry)
        }

        return results
    }

    /// Wipes every cached icon — in-memory and on-disk — regardless of bundle mtime.
    /// Unlike the mtime-based invalidation everywhere else, this is for the case where the
    /// decoded icon itself is wrong or corrupted rather than stale: a manual "force refresh"
    /// escape hatch since mtime never changes for a bundle that hasn't been reinstalled.
    func clearAll() {
        memoryCache.removeAllObjects()
        mtimeCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDir)
    }

    /// Deletes cache entries for apps that no longer exist on disk.
    func pruneDeletedApps(currentAppPaths: Set<String>) {
        // Enumerate across *all* appearances, not just the current one — otherwise a deleted
        // app whose only cached variant belongs to the other appearance is never reclaimed.
        for appPath in allCachedAppPaths() {
            guard !currentAppPaths.contains(appPath) else { continue }
            deleteCacheAllAppearances(for: appPath)
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

    /// The single definition of how a path and an appearance combine into a cache identity.
    /// Both the memory key and the on-disk filename derive from this, so a variant written
    /// under one appearance can never be read back under another.
    private func variantKey(_ appPath: String, appearance: IconAppearance) -> String {
        "\(appPath)_\(appearance.rawValue)"
    }

    /// Memory cache key includes appearance so light and dark variants are separate in-memory.
    private func memoryCacheKey(_ appPath: String, appearance: IconAppearance) -> NSString {
        variantKey(appPath, appearance: appearance) as NSString
    }

    /// Full SHA256 digest of the path + appearance, hex-encoded — fixed-length and collision-free.
    /// Light and dark variants are cached separately on disk, so switching appearance will find
    /// the variant that was cached for the current appearance.
    func cacheKey(for appPath: String, appearance: IconAppearance) -> String {
        let digest = SHA256.hash(data: Data(variantKey(appPath, appearance: appearance).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Deletes every cached appearance variant for an app — used when the app itself is gone.
    private func deleteCacheAllAppearances(for appPath: String) {
        for appearance in IconAppearance.allCases {
            deleteCache(for: appPath, appearance: appearance)
        }
    }

    private func deleteCache(for appPath: String, appearance: IconAppearance) {
        memoryCache.removeObject(forKey: variantKey(appPath, appearance: appearance) as NSString)

        let cacheKey = cacheKey(for: appPath, appearance: appearance)
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
