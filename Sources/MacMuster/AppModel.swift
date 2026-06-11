import Foundation
import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
class AppModel {
    // MARK: - Constants
    var refreshInterval: TimeInterval = 300 // 5 minutes

    // MARK: - State
    var isLoading = true
    var appMetadataCache: [String: AppMetadata] = [:]
    var displayOrder: [Application] = []
    private var appPathIndex: [String: Application] = [:] // Optimization P2: Path -> App lookup index
    private var dataVersion: Int = 0 // Track changes to displayOrder for cache invalidation

    // Optimization P1: Scan caching to avoid redundant disk I/O every 5 minutes
    private struct ScanCache {
        let apps: [Application]
        let metadata: [String: AppMetadata]
        let dirMtimes: [String: Date]
        let timestamp: Date
    }
    private var scanCache: ScanCache?
    var hiddenAppPaths: Set<String> = [] {
        didSet {
            dataVersion += 1
            updateFilteredApps()
        }
    }
    var customDirectories: [String] = []
    var allScanDirectories: [String] = []

    // MARK: - Folders
    var folders: [AppFolder] = [] {
        didSet {
            dataVersion += 1
        }
    }
    private let folderIconCache = NSCache<NSString, NSImage>()
    var currentFolderId: String? = nil {
        didSet { dataVersion += 1 }
    }

    // MARK: - Recent Apps Tracking
    var _recentApps: [Application] = []
    private var recentAppLaunchTimes: [String: Date] = [:]
    private let maxRecentApps = 8

    // MARK: - UI & Navigation State
    var selectedAppIndex: Int = 0
    var scrollTargetIndex: Int?  // Set to trigger scrolling to index
    var scrollTargetAnchor: ScrollAnchor?  // Anchor for scrolling (top, center, bottom)
    var searchTerm: String = "" {
        didSet { dataVersion += 1 }
    }
    var fontFamily: String = "SF Pro"
    var fontSize: Double = 14.0
    var fontWeight: String = "normal"
    var columnCount: Int = 4
    var iconSize: IconSize = .small
    var selectedCategory: AppCategory = .user
    var categoryCounts: [AppCategory: Int] = [:]
    var _mostUsedApps: [Application] = []
    var mostUsedDirty: Bool = true
    var _recentlyLaunchedApps: [Application] = []
    var recentlyLaunchedDirty: Bool = true
    var customOrder: [String: Int] = [:]
    var sortOption: ApplicationSorter.SortOption = .name

    // MARK: - Glow Effect Settings (for overlay window edges)
    var glowEnabled: Bool = true
    var glowColor: Color = .white
    var glowIntensity: Double = 0.3 {
        didSet {
            // Clamp intensity between 0 and 1
            if glowIntensity < 0 { glowIntensity = 0 }
            if glowIntensity > 1 { glowIntensity = 1 }
        }
    }
    var glowWidth: Double = 40.0 {
        didSet {
            // Clamp width between 5 and 40
            if glowWidth < 5 { glowWidth = 5 }
            if glowWidth > 40 { glowWidth = 40 }
        }
    }

    // MARK: - Settings
    var showFoldersFirst: Bool = false {
        didSet {
            dataVersion += 1
            UserDefaults.standard.set(showFoldersFirst, forKey: "showFoldersFirst")
        }
    }

    // MARK: - Timer & Observers
    private var refreshTimer: Timer?

    // MARK: - Initialization
    init() {
        loadHiddenApps()
        loadFolders()
        loadPersistedPreferences()
        loadRecentLaunchTimes()
        loadCustomDirectories()
        loadFontFamily()
    }

    /// Start loading applications asynchronously. Called from the view's `.task` modifier
    /// so it's tied to the SwiftUI lifecycle and ensures proper observation setup.
    @MainActor
    func startLoading() async {
        guard isLoading else { return }
        defer { isLoading = false }

        let hiddenPaths = hiddenAppPaths
        let allDirs = allScanDirectories

        let result = await Self.scanApplications(directories: allDirs, hiddenPaths: hiddenPaths)

        self.appMetadataCache = result.metadata
        self.displayOrder = self.sortedApplications(result.apps)

        rebuildAppPathIndex()

        dataVersion += 1
        self.updateFilteredApps()
        self.setupRefreshTimer()
        await self.loadMissingIcons()
        // Refresh recent apps so _recentApps gets icon-populated Application structs
        self.updateRecentApps()
    }

    // MARK: - Persistence & Setup
    private func loadHiddenApps() {
        if let data = UserDefaults.standard.data(forKey: "hiddenAppPaths"),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data) {
            hiddenAppPaths = paths
        }
    }

    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: "appFolders"),
           let savedFolders = try? JSONDecoder().decode([AppFolder].self, from: data) {
            folders = savedFolders
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: "appFolders")
        }
    }

    private func loadPersistedPreferences() {
        if let cols = UserDefaults.standard.value(forKey: "columnCount") as? Int {
            columnCount = max(1, cols)
        }
        if let folderId = UserDefaults.standard.string(forKey: "currentFolderId") {
            currentFolderId = folderId
        }
        if let data = UserDefaults.standard.data(forKey: "customOrder"),
           let order = try? JSONDecoder().decode([String: Int].self, from: data) {
            customOrder = order
        }
        if let sortRaw = UserDefaults.standard.string(forKey: "sortOption") {
            sortOption = ApplicationSorter.SortOption(rawValue: sortRaw) ?? .name
        }
        if let iconRaw = UserDefaults.standard.string(forKey: "iconSize") {
            iconSize = IconSize(rawValue: iconRaw) ?? .small
        }
        if let interval = UserDefaults.standard.value(forKey: "refreshInterval") as? Double {
            refreshInterval = interval
        }
        // Load showFoldersFirst setting
        if let showFoldersFirstRaw = UserDefaults.standard.value(forKey: "showFoldersFirst") as? Bool {
            showFoldersFirst = showFoldersFirstRaw
        }
        
        // Load glow effect settings
        if let glowEnabledRaw = UserDefaults.standard.value(forKey: "glowEnabled") as? Bool {
            glowEnabled = glowEnabledRaw
        }
        if let glowColorHex = UserDefaults.standard.string(forKey: "glowColor") {
            // Parse hex color string like "#FFFFFF" or "white"
            glowColor = parseColor(from: glowColorHex)
        }
        if let glowIntensityRaw = UserDefaults.standard.value(forKey: "glowIntensity") as? Double {
            glowIntensity = max(0, min(1, glowIntensityRaw))
        }
        if let glowWidthRaw = UserDefaults.standard.value(forKey: "glowWidth") as? Double {
            glowWidth = max(5, min(40, glowWidthRaw))
        }
    }
    
    private func parseColor(from hexString: String) -> Color {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Named colors
        switch trimmed {
        case "white": return .white
        case "black": return .black
        default: break
        }
        
        // Strip # prefix
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        
        // Parse hex: support 3-digit (#RGB) and 6-digit (#RRGGBB)
        let hexChars = Array(hex)
        let red, green, blue: Double
        if hexChars.count == 6 {
            red = Double(Int(String(hexChars[0...1]), radix: 16) ?? 255) / 255.0
            green = Double(Int(String(hexChars[2...3]), radix: 16) ?? 255) / 255.0
            blue = Double(Int(String(hexChars[4...5]), radix: 16) ?? 255) / 255.0
        } else if hexChars.count == 3 {
            red = Double(Int(String(hexChars[0]), radix: 16) ?? 15) / 15.0
            green = Double(Int(String(hexChars[1]), radix: 16) ?? 15) / 15.0
            blue = Double(Int(String(hexChars[2]), radix: 16) ?? 15) / 15.0
        } else {
            return .white
        }
        return Color(red: red, green: green, blue: blue)
    }


    private func loadCustomDirectories() {
        if let dirs = UserDefaults.standard.stringArray(forKey: "customDirectories") {
            customDirectories = dirs
            allScanDirectories = Self.defaultScanDirectories + dirs
        } else {
            allScanDirectories = Self.defaultScanDirectories
        }
    }

    private func loadFontFamily() {
        if let font = UserDefaults.standard.string(forKey: "fontFamily") {
            fontFamily = font
        }
    }

    // MARK: - Folder Methods

    @discardableResult
    func createFolder(name: String, appPaths: [String]) -> AppFolder {
        let folder = AppFolder(name: name, appPaths: appPaths)
        folders.append(folder)
        saveFolders()
        // Critical fix Issue 2: rebuild appPathIndex on folder changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder changes
        cachedDisplayedApps = nil
        return folder
    }

    func deleteFolder(folderId: String) {
        folders.removeAll { $0.id == folderId }
        folderIconCache.removeObject(forKey: folderId as NSString)
        saveFolders()
        // Critical fix Issue 2: rebuild appPathIndex on folder changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder changes
        cachedDisplayedApps = nil
    }

    func renameFolder(folderId: String, newName: String) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders[index].name = newName
            folders[index].modifiedAt = Date()
            saveFolders()
        }
    }

    func addAppToFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        if !folders[index].appPaths.contains(appPath) {
            folders[index].appPaths.append(appPath)
            folders[index].modifiedAt = Date()
            folderIconCache.removeObject(forKey: folderId as NSString)
            saveFolders()
        }
        // Critical fix Issue 2: rebuild appPathIndex on folder changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder changes
        cachedDisplayedApps = nil
    }

    func removeAppFromFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[index].appPaths.removeAll { $0 == appPath }
        folders[index].modifiedAt = Date()
        folderIconCache.removeObject(forKey: folderId as NSString)
        saveFolders()
        // Critical fix Issue 2: rebuild appPathIndex on folder changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder changes
        cachedDisplayedApps = nil
        // If we're viewing this folder and the app was the last one, go back to root
        if folderId == currentFolderId && folders[index].appPaths.isEmpty {
            currentFolderId = nil
        }
    }

    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) {
        addAppToFolder(appPath, folderId: toFolderId)
        if folderId != toFolderId {
            removeAppFromFolder(appPath, folderId: folderId)
        }
    }

    func openFolder(_ folderId: String) {
        currentFolderId = folderId
        savePersistedPreferences()
        // Critical fix Issue 2: rebuild appPathIndex on folder state changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder state changes
        cachedDisplayedApps = nil
    }

    func closeFolder() {
        currentFolderId = nil
        savePersistedPreferences()
        // Critical fix Issue 2: rebuild appPathIndex on folder state changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder state changes
        cachedDisplayedApps = nil
    }

    var currentFolder: AppFolder? {
        guard let folderId = currentFolderId else { return nil }
        return folders.first { $0.id == folderId }
    }

    func getFolderApplication(_ folder: AppFolder) -> Application {
        // Optimization P2: Use the index instead of linear search through displayOrder
        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        let compositeIcon = generateFolderIcon(containedApps, for: folder.id)

        return Application(
            id: "folder:\(folder.id)",
            name: folder.name,
            path: "folder:\(folder.id)",
            icon: compositeIcon,
            installationDate: folder.createdAt,
            isFolder: true,
            containedApps: folder.appPaths,
            appSize: nil,
            bundleDescription: "\(containedApps.count) app\(containedApps.count == 1 ? "" : "s")",
            isHidden: false
        )
    }

    func generateFolderIcon(_ apps: [Application], for folderId: String? = nil, gridSize: Int = 3) -> NSImage? {
        guard !apps.isEmpty else { return nil }
        
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
            let app = apps[index]

            let icon: NSImage
            if let appIcon = app.icon {
                icon = appIcon
            } else {
                icon = workspace.icon(forFile: app.path)
            }

            let rect = NSRect(x: CGFloat(col) * cellSize,
                            y: CGFloat(gridSize - 1 - row) * cellSize,
                            width: cellSize, height: cellSize)
            icon.draw(in: rect, from: NSRect.zero, operation: .copy, fraction: 1.0)
        }
        return image
    }

    private static let _cachedDefaultScanDirectories: [String] = {
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
    }()

    static var defaultScanDirectories: [String] { _cachedDefaultScanDirectories }

    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshDisplayOrder()
            }
        }
    }

    func cleanupTimerAndObservers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func loadMissingIcons() async {
        let missingPaths = displayOrder.filter { $0.icon == nil }.map(\.path)
        guard !missingPaths.isEmpty else { return }

        // Load icons in batches to avoid blocking the main thread for too long
        let workspace = NSWorkspace.shared
        var icons: [String: NSImage] = [:]
        for (i, path) in missingPaths.enumerated() {
            icons[path] = workspace.icon(forFile: path)
            if i.isMultiple(of: kIconCacheBatchSize) { await Task.yield() }
        }

        let updatedApps = self.displayOrder.map { app in
            if let icon = icons[app.path] {
                Application(
                    id: app.id,
                    name: app.name,
                    path: app.path,
                    icon: icon,
                    installationDate: app.installationDate,
                    isFolder: app.isFolder,
                    containedApps: app.containedApps,
                    appSize: app.appSize,
                    bundleDescription: app.bundleDescription,
                    isHidden: app.isHidden
                )
            } else {
                app
            }
        }
        self.displayOrder = updatedApps

        // Keep appPathIndex in sync so recent apps, folders, etc. get icon-populated objects
        rebuildAppPathIndex()
    }

    private func applicationsPreservingLoadedIcons(from scannedApps: [Application]) -> [Application] {
        let loadedIconsByPath = Dictionary(uniqueKeysWithValues: displayOrder.compactMap { app -> (String, NSImage)? in
            guard let icon = app.icon else { return nil }
            return (app.path, icon)
        })

        return scannedApps.map { scannedApp in
            var app = scannedApp
            if app.icon == nil, let loadedIcon = loadedIconsByPath[app.path] {
                app.icon = loadedIcon
            }
            return app
        }
    }

    private func rebuildAppPathIndex() {
        appPathIndex.removeAll(keepingCapacity: true)
        for app in displayOrder {
            appPathIndex[app.path] = app
        }
    }

    private func updateFilteredApps() {
        var counts: [AppCategory: Int] = [:]
        let visible = visibleApplications
        for app in visible {
            let cat = getCategory(for: app)
            counts[cat, default: 0] += 1
        }
        counts[.mostUsed] = _mostUsedApps.isEmpty ? visible.count : _mostUsedApps.count
        counts[.recentlyLaunched] = _recentlyLaunchedApps.isEmpty ? visible.count : _recentlyLaunchedApps.count
        counts[.newlyInstalled] = visible.count
        categoryCounts = counts
    }

    // MARK: - Background Scanning
    nonisolated static func scanApplications(directories: [String], hiddenPaths: Set<String>) async -> AppScanResult {
        var apps: [Application] = []
        var metadata: [String: AppMetadata] = [:]
        var seenPaths: Set<String> = []

        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir) else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in contents {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                // Deduplicate: skip if already found (e.g., symlink across directories)
                guard !seenPaths.contains(fullPath) else { continue }
                seenPaths.insert(fullPath)
                guard FileManager.default.fileExists(atPath: fullPath), !hiddenPaths.contains(fullPath) else { continue }

                let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath)
                let fileType = (attributes?[.type] as? FileAttributeType) ?? .typeRegular

                // Check if this is a regular file (not a directory)
                if fileType == .typeRegular {
                    // Skip non-directory files
                    continue
                }

                // This is a directory - check if it's a valid app bundle
                let bundlePath = (fullPath as NSString).appendingPathComponent("Contents")
                guard FileManager.default.fileExists(atPath: bundlePath) else { continue }

                let bundle = Bundle(path: bundlePath)
                let name = bundle?.infoDictionary?["CFBundleName"] as? String ?? item.replacingOccurrences(of: ".app", with: "")
                let date = attributes?[.modificationDate] as? Date ?? Date()
                let size = attributes?[.size] as? Int

                // Check for contained apps (nested .app bundles inside)
                let containedApps = Self.findContainedApps(in: fullPath)

                // Distinguish between .app bundles and regular directories:
                // - .app bundles are always treated as regular apps (isFolder = false)
                // - regular directories are treated as folders only if they contain 2+ .app bundles
                let isFolder: Bool
                if item.hasSuffix(".app") {
                    // This is an .app bundle - treat as regular app, never as folder
                    isFolder = false
                    // Add parent app
                    apps.append(Application(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        icon: nil,
                        installationDate: date,
                        isFolder: false,
                        containedApps: containedApps,
                        appSize: size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                        bundleDescription: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                        isHidden: false
                    ))

                    metadata[fullPath] = AppMetadata(
                        modificationDate: date,
                        size: size,
                        bundleIdentifier: bundle?.bundleIdentifier
                    )

                    // Add each nested app as a separate entry
                    if let nestedApps = containedApps {
                        for nestedItem in nestedApps {
                            let nestedFullPath = (fullPath as NSString).appendingPathComponent(nestedItem)
                            guard FileManager.default.fileExists(atPath: nestedFullPath), !hiddenPaths.contains(nestedFullPath) else { continue }
                            // Deduplicate: skip if already found
                            guard !seenPaths.contains(nestedFullPath) else { continue }
                            seenPaths.insert(nestedFullPath)

                            let nestedBundlePath = (nestedFullPath as NSString).appendingPathComponent("Contents")
                            guard FileManager.default.fileExists(atPath: nestedBundlePath) else { continue }

                            let nestedBundle = Bundle(path: nestedBundlePath)
                            let nestedName = nestedBundle?.infoDictionary?["CFBundleName"] as? String ?? nestedItem.replacingOccurrences(of: ".app", with: "")
                            let nestedAttributes = try? FileManager.default.attributesOfItem(atPath: nestedFullPath)
                            let nestedDate = nestedAttributes?[.modificationDate] as? Date ?? Date()
                            let nestedSize = nestedAttributes?[.size] as? Int

                            // Nested apps are also regular apps (never folders)
                            apps.append(Application(
                                id: nestedFullPath,
                                name: nestedName,
                                path: nestedFullPath,
                                icon: nil,
                                installationDate: nestedDate,
                                isFolder: false,
                                containedApps: nil,
                                appSize: nestedSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                                bundleDescription: nestedBundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                                isHidden: false
                            ))

                            metadata[nestedFullPath] = AppMetadata(
                                modificationDate: nestedDate,
                                size: nestedSize,
                                bundleIdentifier: nestedBundle?.bundleIdentifier
                            )
                        }
                    }
                } else {
                    // This is a regular directory - treat as folder only if it contains 2+ .app bundles
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
                        bundleDescription: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                        isHidden: false
                    ))

                    metadata[fullPath] = AppMetadata(
                        modificationDate: date,
                        size: size,
                        bundleIdentifier: bundle?.bundleIdentifier
                    )
                }
            }
        }

        return AppScanResult(metadata: metadata, apps: apps)
    }

    /// Finds .app bundles inside a directory, including nested paths like Contents/Developer/Applications/
    nonisolated private static func findContainedApps(in directoryPath: String) -> [String]? {
        guard FileManager.default.fileExists(atPath: directoryPath) else { return nil }

        var appBundles: [String] = []

        // Check for .app bundles at the top level
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) {
            appBundles = contents.filter { $0.hasSuffix(".app") }
        }

        // Also check common nested locations where apps might be stored (e.g., Xcode)
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
                        appBundles.append(item)
                    }
                }
            }
        }

        return appBundles.isEmpty ? nil : appBundles
    }

    // MARK: - Sorting
    func sortedApplications(_ apps: [Application]) -> [Application] {
        switch sortOption {
        case .name:
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .installationDate:
            return apps.sorted { $0.installationDate > $1.installationDate }
        }
    }

    // MARK: - Refresh & Updates
    // Changed from private to internal so AppDelegate/Views can trigger manual refreshes if needed
    func refreshDisplayOrder() async {
        let hiddenPaths = hiddenAppPaths
        let allDirs = allScanDirectories

        // Optimization P1: Check if directories have actually changed before re-scanning
        if let cache = scanCache {
            var hasChanged = false
            for dir in allDirs {
                let currentMtime = (try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date) ?? Date()
                if currentMtime != cache.dirMtimes[dir] {
                    hasChanged = true
                    break
                }
            }

            // Only re-scan if a directory changed or the interval has passed (e.g., to catch internal bundle changes)
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < refreshInterval * 2 {
                return // Skip scan, data is still fresh
            }
        }

        let result = await Self.scanApplications(directories: allDirs, hiddenPaths: hiddenPaths)

        // Update Cache
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            currentMtimes[dir] = (try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date) ?? Date()
        }
        scanCache = ScanCache(apps: result.apps, metadata: result.metadata, dirMtimes: currentMtimes, timestamp: Date())

        self.appMetadataCache = result.metadata
        let appsWithPreservedIcons = applicationsPreservingLoadedIcons(from: result.apps)
        self.displayOrder = self.sortedApplications(appsWithPreservedIcons)

        // Update the path index for O(1) lookups in folders and other methods
        rebuildAppPathIndex()

        dataVersion += 1
        self.updateFilteredApps()
        await self.loadMissingIcons()
        // Refresh recent apps so _recentApps gets icon-populated Application structs
        self.updateRecentApps()
    }

    // MARK: - Recent Apps Tracking
    func recordAppLaunch(at path: String) {
        recentAppLaunchTimes[path] = Date()
        pruneRecentLaunchTimes()
        updateRecentApps()
        persistRecentLaunchTimes()
    }
    
    private func pruneRecentLaunchTimes() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        if recentAppLaunchTimes.count > 500 {
            recentAppLaunchTimes = recentAppLaunchTimes.filter { $0.value > cutoff }
        }
    }
    
    private func persistRecentLaunchTimes() {
        if let data = try? JSONEncoder().encode(recentAppLaunchTimes) {
            UserDefaults.standard.set(data, forKey: "recentAppLaunchTimes")
        }
    }
    
    private func loadRecentLaunchTimes() {
        guard let data = UserDefaults.standard.data(forKey: "recentAppLaunchTimes"),
              let times = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        recentAppLaunchTimes = times
        pruneRecentLaunchTimes()
        updateRecentApps()
    }

    func isRecentApp(_ path: String) -> Bool {
        return _recentApps.contains { $0.path == path }
    }

    func getRecentApps() -> [Application] {
        return _recentApps
    }

    private func updateRecentApps() {
        // Optimization P2: Reduced sorting overhead by taking prefix before filtering
        let sortedLaunchTimes = recentAppLaunchTimes.sorted { $0.value > $1.value }
        let recentPaths = sortedLaunchTimes.prefix(maxRecentApps).map { $0.key }

        // Use the path index for O(1) lookup instead of filtering the whole displayOrder
        _recentApps = recentPaths.compactMap { appPathIndex[$0] }
    }

    // MARK: - Navigation & Selection

    /// Move selection up by one row (move up by column count, wrap to bottom if at top)
    func selectAppUp() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else if selectedAppIndex < columnCount {
            // At top row, wrap to bottom
            let rows = (apps.count + columnCount - 1) / columnCount
            selectedAppIndex = selectedAppIndex + (rows - 1) * columnCount
            if selectedAppIndex >= apps.count {
                selectedAppIndex = apps.count - 1
            }
            // Use bottom anchor so the wrapped-to-bottom app is visible
            scrollTargetAnchor = .bottom
        } else {
            selectedAppIndex -= columnCount
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    /// Move selection down by one row (move down by column count, wrap to top if at bottom)
    func selectAppDown() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else if selectedAppIndex >= apps.count - columnCount {
            // At or near bottom row, wrap to top
            selectedAppIndex = selectedAppIndex % columnCount
            if selectedAppIndex >= apps.count {
                selectedAppIndex = apps.count - 1
            }
            // Use top anchor so the wrapped-to-top app is visible
            scrollTargetAnchor = .top
        } else {
            selectedAppIndex += columnCount
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    /// Move selection left by one column (move left by 1, wrap to end of previous row)
    func selectAppLeft() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else if selectedAppIndex % columnCount == 0 {
            // At leftmost column, wrap to rightmost of previous row
            selectedAppIndex -= 1
            if selectedAppIndex < 0 {
                let lastRowStart = ((apps.count - 1) / columnCount) * columnCount
                selectedAppIndex = min(lastRowStart + columnCount - 1, apps.count - 1)
                // Use bottom anchor if wrapping to last row
                scrollTargetAnchor = .bottom
            } else {
                scrollTargetAnchor = .center
            }
        } else {
            selectedAppIndex -= 1
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    /// Move selection right by one column (move right by 1, wrap to start of next row)
    func selectAppRight() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else if selectedAppIndex % columnCount == columnCount - 1 {
            // At rightmost column, wrap to leftmost of next row
            selectedAppIndex += 1
            if selectedAppIndex >= apps.count {
                selectedAppIndex = selectedAppIndex % columnCount
                if selectedAppIndex >= apps.count {
                    selectedAppIndex = 0
                }
                // Use top anchor if wrapping to first row
                scrollTargetAnchor = .top
            } else {
                scrollTargetAnchor = .center
            }
        } else {
            selectedAppIndex += 1
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    /// Clears the scroll target after scrolling has been performed
    func clearScrollTarget() {
        scrollTargetIndex = nil
        scrollTargetAnchor = nil
    }

    @discardableResult
    func launchSelectedApp() -> Bool {
        let displayedApps = getDisplayedApps()
        guard selectedAppIndex >= 0, selectedAppIndex < displayedApps.count else { return false }
        let app = displayedApps[selectedAppIndex]
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        recordAppLaunch(at: app.path)
        return true
    }

    func clearSearchState() {
        searchTerm = ""
    }

    // MARK: - App Management
    // Quick Win 6: Consolidate toggleHiddenApp - single source of truth
    func toggleHiddenApp(_ path: String) {
        if hiddenAppPaths.contains(path) {
            hiddenAppPaths.remove(path)
        } else {
            hiddenAppPaths.insert(path)
        }
        saveHiddenApps()
        // Critical fix Issue 1: explicit cache invalidation on hidden app changes
        cachedDisplayedApps = nil
    }

    func toggleHiddenApp(_ app: Application) {
        toggleHiddenApp(app.path)
    }

    func isAppHidden(_ path: String) -> Bool {
        return hiddenAppPaths.contains(path)
    }

    func getCategory(for app: Application) -> AppCategory {
        // Optimization P3: Simplified logic - remove unreachable path and redundant checks
        if app.path.hasPrefix("/System") { return .system }
        return .user
    }

    func removeCustomDirectory(_ path: String) {
        customDirectories.removeAll { $0 == path }
        allScanDirectories = Self.defaultScanDirectories + customDirectories
        Task { await refreshDisplayOrder() }
    }

    func addCustomDirectory(_ path: String) {
        if !customDirectories.contains(path) {
            customDirectories.append(path)
            allScanDirectories = Self.defaultScanDirectories + customDirectories
        }
    }

    func setFontFamily(_ family: String) {
        fontFamily = family
        UserDefaults.standard.set(family, forKey: "fontFamily")
    }

    func setFontWeight(_ weight: String) {
        fontWeight = weight
    }

    func setColumnCount(_ count: Int) {
        columnCount = count
        UserDefaults.standard.set(count, forKey: "columnCount")
    }

    func setSortOption(_ option: ApplicationSorter.SortOption) {
        sortOption = option
        dataVersion += 1
        savePersistedPreferences()
    }

    func setIconSize(_ size: IconSize) {
        iconSize = size
        savePersistedPreferences()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        savePersistedPreferences()
    }

    func setShowFoldersFirst(_ value: Bool) {
        showFoldersFirst = value
        dataVersion += 1
        cachedDisplayedApps = nil
    }

    func setApplications(_ apps: [Application]) {
        displayOrder = apps
        rebuildAppPathIndex()
        updateRecentApps()
        updateFilteredApps()
    }

    func updateCustomOrder(from apps: [Application]) {
        for (index, app) in apps.enumerated() {
            customOrder[app.path] = index
        }
        displayOrder = apps
        dataVersion += 1
        updateFilteredApps()
        savePersistedPreferences()
    }

    func selectFirstApp() {
        guard !getDisplayedApps().isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = 0
    }

    func selectLastApp() {
        guard !getDisplayedApps().isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = getDisplayedApps().count - 1
    }

    func selectNextApp() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = (selectedAppIndex + 1) % apps.count
    }

    func selectPreviousApp() {
        let apps = getDisplayedApps()
        guard !apps.isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = (selectedAppIndex - 1 + apps.count) % apps.count
    }

    func selectApp(at index: Int) {
        let apps = getDisplayedApps()
        guard index >= 0, index < apps.count else { return }
        selectedAppIndex = index
    }

    func refreshMostUsedApps() {
        mostUsedDirty = false
        // Placeholder logic for most-used sorting
    }

    func refreshRecentlyLaunchedApps() {
        recentlyLaunchedDirty = false
        // Placeholder logic for recently launched sorting
    }

    func refreshNewlyInstalledApps() {
        // Placeholder logic for newly installed sorting
    }

    private func saveHiddenApps() {
        if let data = try? JSONEncoder().encode(hiddenAppPaths) {
            UserDefaults.standard.set(data, forKey: "hiddenAppPaths")
        }
    }

    private func savePersistedPreferences() {
        UserDefaults.standard.set(currentFolderId, forKey: "currentFolderId")
        if let data = try? JSONEncoder().encode(customOrder) {
            UserDefaults.standard.set(data, forKey: "customOrder")
        }
        UserDefaults.standard.set(sortOption.rawValue, forKey: "sortOption")
        UserDefaults.standard.set(iconSize.rawValue, forKey: "iconSize")
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        
        // Save glow effect settings
        UserDefaults.standard.set(glowEnabled, forKey: "glowEnabled")
        UserDefaults.standard.set(getHexColorValue(), forKey: "glowColor")
        UserDefaults.standard.set(glowIntensity, forKey: "glowIntensity")
    }
    
    private func getHexColorValue() -> String {
        let nsColor = NSColor(glowColor)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#ffffff" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }


    // MARK: - Computed Properties & Display Helpers

    var visibleApplications: [Application] {
        displayOrder.filter { !hiddenAppPaths.contains($0.path) }
    }

    private var cachedDisplayedApps: (version: Int, apps: [Application])?
    
    func getDisplayedApps() -> [Application] {
        if let cached = cachedDisplayedApps, cached.version == dataVersion {
            return cached.apps
        }
        
        // Collect the set of all app paths that live inside any folder (used in multiple places below)
        let appsInAnyFolder: Set<String> = folders.reduce(into: Set()) { $0.formUnion($1.appPaths) }

        // Determine the set of apps to display based on current folder context
        let baseApps: [Application]
        if let folderId = currentFolderId {
            // Inside a folder: show only apps that belong to this folder (and its child folders)
            baseApps = getAllAppsIncludingChildFolders(for: folderId)
        } else {
            // At root level (no active folder):
            // - loose apps (not in any folder) are shown individually
            // - apps that belong to a folder are hidden behind the folder icon
            let looseApps = visibleApplications.filter { !appsInAnyFolder.contains($0.path) }

            // Build folder icons, but only for folders that have at least one visible app
            let folderIcons: [Application] = folders.compactMap { folder in
                let hasVisible = folder.appPaths.contains { path in
                    !hiddenAppPaths.contains(path) && appPathIndex[path] != nil
                }
                return hasVisible ? getFolderApplication(folder) : nil
            }

            baseApps = looseApps + folderIcons
        }

        // Apply search filter
        var result: [Application]
        if !searchTerm.isEmpty {
            let lower = searchTerm.lowercased()

            if currentFolderId == nil {
                // Root-level search: match against ALL visible apps (loose + inside folders).
                // This lets the user find an app regardless of which folder it was moved to.
                // Folder icons are not included — results are the actual apps.
                result = sortedApplications(visibleApplications.filter { $0.lowercaseName.contains(lower) })
            } else {
                // Inside a folder: filter the folder's apps by name
                var filtered = baseApps.filter { $0.lowercaseName.contains(lower) }
                filtered = sortedApplications(filtered)
                result = filtered
            }
        } else {
            // No search — display baseApps with optional folder-first ordering
            var ordered = baseApps
            if showFoldersFirst && !ordered.isEmpty {
                let folderApps    = ordered.filter { $0.isFolder }
                let nonFolderApps = ordered.filter { !$0.isFolder }
                if !folderApps.isEmpty && !nonFolderApps.isEmpty {
                    ordered = folderApps + nonFolderApps
                }
            }

            if !customOrder.isEmpty {
                result = ordered.sorted {
                    let a = customOrder[$0.path], b = customOrder[$1.path]
                    switch (a, b) {
                    case (nil, nil): return false
                    case (nil, _):   return false
                    case (_, nil):   return true
                    case (let av?, let bv?): return av < bv
                    }
                }
            } else {
                // When showFoldersFirst is enabled, preserve the folder-first arrangement
                // Otherwise use default alphabetical sorting
                if showFoldersFirst && !ordered.isEmpty {
                    let folderApps    = ordered.filter { $0.isFolder }
                    let nonFolderApps = ordered.filter { !$0.isFolder }
                    if !folderApps.isEmpty && !nonFolderApps.isEmpty {
                        result = folderApps + nonFolderApps
                    } else {
                        result = sortedApplications(ordered)
                    }
                } else {
                    result = sortedApplications(ordered)
                }
            }
        }
        
        cachedDisplayedApps = (dataVersion, result)
        return result
    }
    
    // MARK: - Recursive Child Folder Search
    
    /// Get all apps from a folder and its child folders (recursively).
    /// A child folder is one that contains at least one app from the parent folder's appPaths.
    private func getAllAppsIncludingChildFolders(for folderId: String) -> [Application] {
        guard folders.first(where: { $0.id == folderId }) != nil else { return [] }

        var result: [Application] = []
        var visitedFolders: Set<String> = []  // start empty; collectApps adds ids as it visits them

        func collectApps(from currentFolderId: String) {
            guard !visitedFolders.contains(currentFolderId),
                  let currentFolder = folders.first(where: { $0.id == currentFolderId })
            else { return }
            visitedFolders.insert(currentFolderId)

            let containedApps = currentFolder.appPaths.compactMap { appPathIndex[$0] }
            result.append(contentsOf: containedApps)

            // Child folders share at least one appPath with this folder — recurse into them
            for childFolder in folders where !visitedFolders.contains(childFolder.id) {
                if childFolder.appPaths.contains(where: { currentFolder.appPaths.contains($0) }) {
                    collectApps(from: childFolder.id)
                }
            }
        }

        collectApps(from: folderId)

        // Respect hidden-app setting inside folders too
        result = result.filter { !hiddenAppPaths.contains($0.path) }

        if !customOrder.isEmpty {
            result.sort {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) {
                case (nil, nil): return false
                case (nil, _):   return false
                case (_, nil):   return true
                case (let av?, let bv?): return av < bv
                }
            }
        } else {
            result = sortedApplications(result)
        }

        return result
    }

    var filteredApplications: [Application] {
        getDisplayedApps()
    }

    // MARK: - Supporting Types

    enum AppCategory: String, CaseIterable {
        case mostUsed = "Most Used"
        case recentlyLaunched = "Recently Launched"
        case newlyInstalled = "Newly Installed"
        case system = "System"
        case utilities = "Utilities"
        case user = "User"
    }

    enum IconSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
    }

    // Quick Win 4: Make icon mutable to avoid full struct copies in loadMissingIcons()
    struct Application: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        var icon: NSImage?  // Changed from let to var
        let installationDate: Date
        let isFolder: Bool
        let containedApps: [String]?
        let appSize: String?
        let bundleDescription: String?
        let isHidden: Bool

        var lowercaseName: String { name.lowercased() }

        // Custom Hashable implementation since NSImage is not Equatable
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: Application, rhs: Application) -> Bool {
            return lhs.id == rhs.id
        }
    }

    struct AppMetadata {
        let modificationDate: Date?
        let size: Int?
        let bundleIdentifier: String?
    }

    struct AppScanResult {
        let metadata: [String: AppMetadata]
        let apps: [Application]
    }

    enum ScrollAnchor {
        case top
        case center
        case bottom
    }

    // MARK: - AppFolder

    struct AppFolder: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var appPaths: [String]
        var customIcon: String?
        let createdAt: Date
        var modifiedAt: Date

        init(id: String = UUID().uuidString,
             name: String,
             appPaths: [String],
             customIcon: String? = nil) {
            self.id = id
            self.name = name
            self.appPaths = appPaths
            self.customIcon = customIcon
            self.createdAt = Date()
            self.modifiedAt = Date()
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: AppFolder, rhs: AppFolder) -> Bool {
            return lhs.id == rhs.id
        }
    }
}