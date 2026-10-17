import Foundation

/// The two `Info.plist` values the smart-folder classifier needs, read once per app.
///
/// Both are optional: an app may ship a bundle identifier without a category, or neither (some
/// system apps have neither). The assigner treats an absent key as "no signal from this tier" and
/// falls through to the next tier, so a nil field is a normal, expected result — not an error.
struct BundleInfo: Sendable, Equatable {
    let bundleID: String?
    /// The raw value of the `LSApplicationCategoryType` key — a `public.app-category.*` UTI string
    /// looked up in `SmartFolderCategory.byCategoryUTI`.
    let lsCategory: String?
}

/// Reads bundle identifiers and category UTIs from app bundles.
///
/// Deliberately **never on the scan path**: a full-library read costs one plist parse per app, so
/// it is paid only when the wizard runs. `readBundleInfo(forPaths:)` does synchronous file I/O and
/// must be called from a `Task.detached` (the wizard does this in Phase 4); the returned
/// dictionary omits any path whose Info.plist is missing, unreadable, over the size cap, or
/// carries neither of the two values. Everything fails soft — a bad bundle yields no entry, never
/// an exception.
enum BundleInfoReader {

    /// Reads info for every path that yields something, mapping `path -> BundleInfo`.
    static func readBundleInfo(forPaths paths: [String]) -> [String: BundleInfo] {
        var result: [String: BundleInfo] = [:]
        for path in paths {
            if let info = readBundleInfo(forPath: path) { result[path] = info }
        }
        return result
    }

    /// Reads a single bundle's `Contents/Info.plist`, returning nil when there is nothing usable.
    private static func readBundleInfo(forPath path: String) -> BundleInfo? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")

        // Bounded read instead of stat-then-read. `attributesOfItem` does not follow symlinks but
        // `Data(contentsOf:)` does, so a symlinked Info.plist reported its link size (a few bytes)
        // and then loaded whatever it pointed at, bypassing the cap. Reading at most cap + 1 bytes
        // enforces the cap on the bytes actually read, whatever the path resolves to, and leaves no
        // gap between checking the size and reading the file.
        guard let handle = FileHandle(forReadingAtPath: plistPath) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: WizardMetrics.maxInfoPlistReadBytes + 1),
              !data.isEmpty,
              data.count <= WizardMetrics.maxInfoPlistReadBytes,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any] else {
            return nil
        }

        let bundleID = plist["CFBundleIdentifier"] as? String
        let lsCategory = plist["LSApplicationCategoryType"] as? String
        guard bundleID != nil || lsCategory != nil else { return nil }
        return BundleInfo(bundleID: bundleID, lsCategory: lsCategory)
    }
}
