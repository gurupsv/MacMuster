import Foundation
import AppKit
import Darwin

/// Handles scanning directories for .app bundles and resolving Bundle metadata.
nonisolated final class ApplicationScanner: @unchecked Sendable {
    static let shared = ApplicationScanner()
    private init() {}
    
    struct ScanResult {
        let apps: [Application]
    }
    
    /// Scans the given directories for .app bundles. Hidden apps are still scanned and
    /// returned — visibility filtering happens in AppModel so a hidden app can be found
    /// again later and un-hidden.
    nonisolated func scanDirectories(directories: [String]) -> ScanResult {
        var apps: [Application] = []
        var seenPaths: Set<String> = []

        // "/Applications/Utilities" (and its /System counterpart) is both a configured scan
        // directory in its own right *and* a plain child folder of "/Applications" — without this,
        // the plain-folder handling below would wrap it as a synthetic in-launcher folder while its
        // contents are *also* being surfaced individually because it's scanned directly, showing
        // every utility twice. Any directory that's explicitly configured to be scanned on its own
        // should never additionally be treated as a wrapper folder to synthesize.
        let resolvedConfiguredDirs = Set(directories.map { ($0 as NSString).resolvingSymlinksInPath })

        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in contents {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                let resolvedPath = (fullPath as NSString).resolvingSymlinksInPath
                guard !seenPaths.contains(resolvedPath) else { continue }
                seenPaths.insert(resolvedPath)

                // No separate existence check: `attributesOfItem` fails for a path that isn't
                // there, and a nil result already falls through to the `.typeRegular` skip below.
                let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath)
                let fileType = (attributes?[.type] as? FileAttributeType) ?? .typeRegular

                if fileType == .typeRegular {
                    continue
                }

                if item.hasSuffix(".app") {
                    // A real .app bundle must have its own Contents directory; if it doesn't,
                    // it's broken/incomplete and there's nothing useful to show.
                    let bundlePath = (fullPath as NSString).appendingPathComponent("Contents")
                    guard FileManager.default.fileExists(atPath: bundlePath) else { continue }

                    // Use filename-derived name (never varies, no syscalls needed)
                    let name = item.hasSuffix(".app") ? String(item.dropLast(4)) : item
                    // `.distantPast`, never `Date()`: a missing mtime used to become the current
                    // time, which moves on every scan — so `RecentlyUpdatedTracker` saw a fresh
                    // delta each time and re-badged the app as updated forever, and sorting by
                    // installation date shuffled it around. A fixed sentinel is stable and reads
                    // as "no known install date" in both places.
                    let date = attributes?[.modificationDate] as? Date ?? .distantPast
                    let containedApps = findContainedApps(in: fullPath)

                    apps.append(Application(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        icon: nil,
                        installationDate: date,
                        isFolder: false,
                        containedApps: containedApps,
                        bundleDescription: nil
                    ))

                    if let nestedApps = containedApps {
                        for nestedFullPath in nestedApps {
                            appendDiscoveredApp(at: nestedFullPath, apps: &apps, seenPaths: &seenPaths)
                        }
                    }
                } else {
                    // Not a bundle itself — a plain Finder folder (vendor installers create these
                    // constantly: "Microsoft Office", "Canon Utilities", etc.) never has its own
                    // Contents directory, so don't gate on that the way .app bundles are gated
                    // above. Whether there's anything to show here is determined by what's inside,
                    // not by whether this directory happens to look like a bundle itself.
                    guard !resolvedConfiguredDirs.contains(resolvedPath) else { continue }
                    guard let containedApps = findAppsInPlainFolder(at: fullPath) else { continue }

                    if containedApps.count >= 2 {
                        // Multiple apps grouped under one folder — surface it as a synthetic
                        // in-launcher folder rather than picking one arbitrarily.
                        let date = attributes?[.modificationDate] as? Date ?? .distantPast
                        apps.append(Application(
                            id: fullPath,
                            name: item,
                            path: fullPath,
                            icon: nil,
                            installationDate: date,
                            isFolder: true,
                            containedApps: containedApps,
                            bundleDescription: nil
                        ))
                    } else {
                        // Exactly one nested app — the wrapper folder itself isn't launchable, so
                        // surface the real app directly instead of an inert wrapper entry.
                        for nestedFullPath in containedApps {
                            appendDiscoveredApp(at: nestedFullPath, apps: &apps, seenPaths: &seenPaths)
                        }
                    }
                }
            }
        }

        return ScanResult(apps: apps)
    }

    /// Adds a single discovered `.app` bundle at `path` to `apps`, deduping against
    /// `seenPaths`. Shared by the "nested apps inside another bundle" case (e.g. Xcode's embedded
    /// Simulator.app) and the "single app inside a plain wrapper folder" case.
    nonisolated private func appendDiscoveredApp(
        at path: String,
        apps: inout [Application],
        seenPaths: inout Set<String>
    ) {
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        guard !seenPaths.contains(resolvedPath) else { return }

        // One stat covers existence as well as the mtime read further down; a nil result means
        // the bundle isn't there (or isn't readable), which is the same "skip it" outcome.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return }
        seenPaths.insert(resolvedPath)

        let bundlePath = (path as NSString).appendingPathComponent("Contents")
        guard FileManager.default.fileExists(atPath: bundlePath) else { return }

        // Use filename-derived name (never varies, no syscalls needed)
        let itemName = (path as NSString).lastPathComponent
        let name = Application.stripAppSuffix(itemName)
        let date = attributes[.modificationDate] as? Date ?? .distantPast

        apps.append(Application(
            id: path,
            name: name,
            path: path,
            icon: nil,
            installationDate: date,
            isFolder: false,
            containedApps: nil,
            bundleDescription: nil
        ))
    }
    
    /// The two places inside an `.app` bundle where macOS apps actually publish other apps —
    /// Xcode's `Contents/Developer/Applications` (Simulator, Instruments) being the motivating
    /// case. Checked by name rather than discovered by walking the bundle.
    private static let nestedAppDirectories = ["Contents/Applications", "Contents/Developer/Applications"]

    /// Finds `.app` bundles published inside another `.app` bundle.
    ///
    /// Called for every app found in a scan, so its cost is paid ~200 times per scan and every
    /// filesystem event triggers a scan. It used to begin by listing the bundle's own root looking
    /// for sibling `.app` children — a directory read per app that cannot succeed: an `.app`
    /// bundle's root holds `Contents`, and a `.app` nested directly in another's root is not a
    /// layout macOS produces. Measured across 210 bundles in `/Applications`,
    /// `/System/Applications` and `/System/Applications/Utilities`: **zero** had a root-level
    /// `.app` child, while 2 had one of the nested directories below. The plain-folder case where
    /// apps really do sit beside each other is `findAppsInPlainFolder`'s job, not this one.
    nonisolated func findContainedApps(in directoryPath: String) -> [String]? {
        var appBundles: [String] = []

        for relativePath in Self.nestedAppDirectories {
            let nestedDir = (directoryPath as NSString).appendingPathComponent(relativePath)
            // Enumerate straight away rather than checking existence first: the call fails for a
            // missing or non-directory path, which is the same "nothing here" answer for one
            // syscall instead of two.
            guard let nestedContents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: nestedDir, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for itemURL in nestedContents where itemURL.pathExtension == "app" {
                // `.isDirectoryKey` comes back with the enumeration, so confirming each entry is
                // a real bundle costs nothing extra instead of a stat apiece.
                let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory { appBundles.append(itemURL.path) }
            }
        }

        return appBundles.isEmpty ? nil : appBundles
    }

    /// Maximum recursion depth for `findAppsInPlainFolder` — generous for ordinary installer
    /// folder structures (rarely more than 2-3 levels deep) while still bounding worst-case work.
    private static let kMaxPlainFolderSearchDepth = 4

    /// Finds `.app` bundles nested arbitrarily deep inside a *plain* (non-bundle) folder, e.g.
    /// "Canon Utilities/Inkjet Extended Survey Program/Inkjet Extended Survey Program.app".
    /// Unlike `findContainedApps` (which only checks one level plus two hardcoded paths — fine for
    /// peeking inside an actual `.app` bundle, and deliberately shallow so it doesn't recurse
    /// through huge bundles like Xcode.app), this walks every subdirectory generically. That's
    /// only safe to do here because plain installer-created wrapper folders are small and shallow;
    /// once a `.app` is found it's treated as a leaf and never recursed into.
    nonisolated func findAppsInPlainFolder(at directoryPath: String, depth: Int = 0) -> [String]? {
        guard depth <= Self.kMaxPlainFolderSearchDepth else { return nil }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directoryPath, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return nil }

        var appBundles: [String] = []
        for itemURL in contents {
            // Both flags arrive with the enumeration rather than costing a stat per entry.
            guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }

            // Never descend through a symlink. A link pointing at an ancestor — or at "/" — turned
            // this walk into a re-traversal of the same tree at every depth; the depth cap bounds
            // that but does not make it cheap, since a link to "/" would enumerate four levels of
            // the whole filesystem. Vendor folders keep their apps in real subdirectories, so
            // refusing links costs nothing real and removes the pathological case outright.
            // A symlink *to* a bundle is still reported, it is just not walked into.
            //
            // Note this is enforced twice over, deliberately. The URL-based
            // `contentsOfDirectory(at:)` above will not open a symlinked directory at all (the
            // string-based `contentsOfDirectory(atPath:)` this replaced followed it happily, which
            // is what made the cycle reachable). That makes cycles structurally impossible, so no
            // visited-path set is needed — but the check below states the intent rather than
            // leaving it resting on an API's error behaviour.
            if values.isSymbolicLink == true {
                if itemURL.pathExtension == "app" { appBundles.append(itemURL.path) }
                continue
            }
            guard values.isDirectory == true else { continue }

            if itemURL.pathExtension == "app" {
                appBundles.append(itemURL.path)
            } else if let nested = findAppsInPlainFolder(at: itemURL.path, depth: depth + 1) {
                appBundles.append(contentsOf: nested)
            }
        }

        return appBundles.isEmpty ? nil : appBundles
    }

    /// Checks if a custom directory path is valid (absolute, not world-writable, not a symlink).
    /// Deliberately does not check ownership — standard system directories like /Applications are
    /// owned by root, not the current user, so an ownership check would reject legitimate directories.
    /// A path that doesn't exist yet (e.g. an unmounted external volume) is still considered valid —
    /// only a path that exists as something other than a directory (e.g. a plain file) is rejected.
    ///
    /// Re-checked before every scan rather than only when the directory is added: the answer can
    /// change underneath a stored result, and a validated directory that is later replaced with a
    /// symlink would otherwise be followed for the rest of the session. The checks are a handful
    /// of syscalls against a list that is normally empty and never long, so paying them per scan
    /// costs nothing measurable.
    static func isValidCustomDirectory(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let fm = FileManager.default

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        if exists && !isDir.boolValue { return false }
        guard exists else { return true }

        // Require an already-normalized path: no "..", no trailing or doubled slashes, nothing a
        // null byte truncated. Anything that normalizes to something other than what was passed is
        // refused rather than silently reinterpreted.
        //
        // `standardizedFileURL` normalizes *lexically* and leaves symlinks alone, which is the
        // whole point. The previous check compared against `resolvingSymlinksInPath`, which does
        // follow them — so it rejected every directory whose **ancestor** happened to be a symlink.
        // On macOS that includes anything under /var (a link to /private/var) and any home behind
        // a link, so ordinary directories were unaddable with no explanation given.
        guard URL(fileURLWithPath: path).standardizedFileURL.path == path else { return false }

        // Reject a symlink at the path itself — the traversal case actually worth refusing, since
        // that entry can be swapped for a link pointing somewhere else entirely. `.isSymbolicLinkKey`
        // describes the final component only, so an ancestor being a link is not held against it.
        if (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]))?
            .isSymbolicLink == true { return false }

        // Reject if world-writable
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let posixPerms = attrs[.posixPermissions] as? Int,
              (posixPerms & 0o002) == 0 else { return false }

        return true
    }
    
    /// Returns the default scan directories (cached).
    static var defaultScanDirectories: [String] {
        var paths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]
        let homeDir = NSHomeDirectory()
        let userApps = (homeDir as NSString).appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: userApps) {
            paths.append(userApps)
        }
        return paths
    }
}
