import Foundation
import AppKit
import Darwin

/// Handles scanning directories for .app bundles and resolving Bundle metadata.
nonisolated final class ApplicationScanner: @unchecked Sendable {
    static let shared = ApplicationScanner()
    private init() {}
    
    struct ScanResult {
        let apps: [Application]
        let metadata: [String: AppMetadata]
    }
    
    /// Scans the given directories for .app bundles. Hidden apps are still scanned and
    /// returned — visibility filtering happens in AppModel so a hidden app can be found
    /// again later and un-hidden.
    nonisolated func scanDirectories(directories: [String]) -> ScanResult {
        var apps: [Application] = []
        var metadata: [String: AppMetadata] = [:]
        var seenPaths: Set<String> = []
        
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
                
                let bundlePath = (fullPath as NSString).appendingPathComponent("Contents")
                guard FileManager.default.fileExists(atPath: bundlePath) else { continue }
                
                let bundle = Bundle(path: bundlePath)
                let name = bundle?.infoDictionary?["CFBundleName"] as? String ?? item.replacingOccurrences(of: ".app", with: "")
                let date = attributes?[.modificationDate] as? Date ?? Date()
                let size = attributes?[.size] as? Int
                
                let containedApps = findContainedApps(in: fullPath)
                
                let isFolder: Bool
                if item.hasSuffix(".app") {
                    isFolder = false
                    apps.append(Application(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        icon: nil,
                        installationDate: date,
                        isFolder: false,
                        containedApps: containedApps,
                        appSize: size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                        bundleDescription: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
                    ))

                    metadata[fullPath] = AppMetadata(
                        modificationDate: date,
                        size: size,
                        bundleIdentifier: bundle?.bundleIdentifier
                    )

                    if let nestedApps = containedApps {
                        for nestedFullPath in nestedApps {
                            guard FileManager.default.fileExists(atPath: nestedFullPath) else { continue }
                            guard !seenPaths.contains(nestedFullPath) else { continue }
                            seenPaths.insert(nestedFullPath)
                            
                            let nestedBundlePath = (nestedFullPath as NSString).appendingPathComponent("Contents")
                            guard FileManager.default.fileExists(atPath: nestedBundlePath) else { continue }
                            
                            let nestedBundle = Bundle(path: nestedBundlePath)
                            let nestedName = nestedBundle?.infoDictionary?["CFBundleName"] as? String ?? (nestedFullPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                            let nestedAttributes = try? FileManager.default.attributesOfItem(atPath: nestedFullPath)
                            let nestedDate = nestedAttributes?[.modificationDate] as? Date ?? Date()
                            let nestedSize = nestedAttributes?[.size] as? Int
                            
                            apps.append(Application(
                                id: nestedFullPath,
                                name: nestedName,
                                path: nestedFullPath,
                                icon: nil,
                                installationDate: nestedDate,
                                isFolder: false,
                                containedApps: nil,
                                appSize: nestedSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                                bundleDescription: nestedBundle?.infoDictionary?["CFBundleShortVersionString"] as? String
                            ))
                            
                            metadata[nestedFullPath] = AppMetadata(
                                modificationDate: nestedDate,
                                size: nestedSize,
                                bundleIdentifier: nestedBundle?.bundleIdentifier
                            )
                        }
                    }
                } else {
                    isFolder = (containedApps?.count ?? 0) >= 2
                    apps.append(Application(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        icon: nil,
                        installationDate: date,
                        isFolder: isFolder,
                        containedApps: containedApps,
                        appSize: size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                        bundleDescription: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
                    ))

                    metadata[fullPath] = AppMetadata(
                        modificationDate: date,
                        size: size,
                        bundleIdentifier: bundle?.bundleIdentifier
                    )
                }
            }
        }
        
        return ScanResult(apps: apps, metadata: metadata)
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
    
    /// Checks if a custom directory is valid (absolute, directory, not world-writable, not a symlink, owned by user).
    static func isValidCustomDirectory(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let fm = FileManager.default

        // Reject symlinks to prevent directory traversal attacks
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }

        // Check it's not a symlink by comparing resolved path
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        guard resolvedPath == path else { return false }

        // Reject if world-writable
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let posixPerms = attrs[.posixPermissions] as? Int,
              (posixPerms & 0o002) == 0 else { return false }

        // Reject if not owned by current user (prevents privilege escalation via shared writable dirs)
        if let ownerID = attrs[.ownerAccountID] as? NSNumber {
            let currentUID = getuid()
            guard ownerID.uintValue == currentUID else { return false }
        }

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
