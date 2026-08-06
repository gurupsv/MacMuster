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
                guard FileManager.default.fileExists(atPath: fullPath) else { continue }
                
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
                    let date = attributes?[.modificationDate] as? Date ?? Date()
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
                        let date = attributes?[.modificationDate] as? Date ?? Date()
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
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !seenPaths.contains(resolvedPath) else { return }
        seenPaths.insert(resolvedPath)

        let bundlePath = (path as NSString).appendingPathComponent("Contents")
        guard FileManager.default.fileExists(atPath: bundlePath) else { return }

        // Use filename-derived name (never varies, no syscalls needed)
        let itemName = (path as NSString).lastPathComponent
        let name = Application.stripAppSuffix(itemName)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attributes?[.modificationDate] as? Date ?? Date()

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
    
    /// Finds .app bundles inside a directory, including nested locations.
    nonisolated func findContainedApps(in directoryPath: String) -> [String]? {
        guard FileManager.default.fileExists(atPath: directoryPath) else { return nil }
        
        var appBundles: [String] = []
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) {
            for item in contents where item.hasSuffix(".app") {
                let fullPath = (directoryPath as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    appBundles.append(fullPath)
                }
            }
        }
        
        let possibleNestedPaths = [
            "\(directoryPath)/Contents/Applications",
            "\(directoryPath)/Contents/Developer/Applications",
        ]
        
        for nestedDir in possibleNestedPaths {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: nestedDir, isDirectory: &isDirectory),
               isDirectory.boolValue,
               let nestedContents = try? FileManager.default.contentsOfDirectory(atPath: nestedDir) {
                for item in nestedContents where item.hasSuffix(".app") {
                    let itemPath = (nestedDir as NSString).appendingPathComponent(item)
                    var itemIsDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: itemPath, isDirectory: &itemIsDirectory),
                       itemIsDirectory.boolValue {
                        appBundles.append(itemPath)
                    }
                }
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
    nonisolated private func findAppsInPlainFolder(at directoryPath: String, depth: Int = 0) -> [String]? {
        guard depth <= Self.kMaxPlainFolderSearchDepth else { return nil }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else { return nil }

        var appBundles: [String] = []
        for item in contents {
            let fullPath = (directoryPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue else { continue }

            if item.hasSuffix(".app") {
                appBundles.append(fullPath)
            } else if let nested = findAppsInPlainFolder(at: fullPath, depth: depth + 1) {
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
    static func isValidCustomDirectory(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let fm = FileManager.default

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        if exists && !isDir.boolValue { return false }
        guard exists else { return true }

        // Reject symlinks to prevent directory traversal attacks
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        guard resolvedPath == path else { return false }

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
