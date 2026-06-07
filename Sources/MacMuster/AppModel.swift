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
    var hiddenAppPaths: Set<String> = []
    var customDirectories: [String] = []
    var allScanDirectories: [String] = []

    // MARK: - Folders
    var folders: [AppFolder] = []
    var currentFolderId: String? = nil

    // MARK: - Recent Apps Tracking
    var _recentApps: [Application] = []
    private var recentAppLaunchTimes: [String: Date] = [:]
    private let maxRecentApps = 8

    // MARK: - UI & Navigation State
    var selectedAppIndex: Int = 0
    var scrollTargetIndex: Int?  // Set to trigger scrolling to index
    var scrollTargetAnchor: ScrollAnchor?  // Anchor for scrolling (top, center, bottom)
    var searchTerm: String = ""
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

    // MARK: - Timer & Observers
    private var refreshTimer: Timer?

    // MARK: - Initialization
    init() {
        loadHiddenApps()
        loadFolders()
        loadPersistedPreferences()
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
        Task { await refreshDisplayOrder() }
        return folder
    }

    func deleteFolder(folderId: String) {
        folders.removeAll { $0.id == folderId }
        saveFolders()
        Task { await refreshDisplayOrder() }
    }

    func renameFolder(folderId: String, newName: String) {
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders[index].name = newName
            folders[index].modifiedAt = Date()
            saveFolders()
            Task { await refreshDisplayOrder() }
        }
    }

    func addAppToFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        if !folders[index].appPaths.contains(appPath) {
            folders[index].appPaths.append(appPath)
            folders[index].modifiedAt = Date()
            saveFolders()
            Task { await refreshDisplayOrder() }
        }
    }

    func removeAppFromFolder(_ appPath: String, folderId: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[index].appPaths.removeAll { $0 == appPath }
        folders[index].modifiedAt = Date()
        saveFolders()
        // If we're viewing this folder and the app was the last one, go back to root
        if folderId == currentFolderId && folders[index].appPaths.isEmpty {
            currentFolderId = nil
        }
        Task { await refreshDisplayOrder() }
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
    }

    func closeFolder() {
        currentFolderId = nil
        savePersistedPreferences()
    }

    var currentFolder: AppFolder? {
        guard let folderId = currentFolderId else { return nil }
        return folders.first { $0.id == folderId }
    }

    func getFolderApplication(_ folder: AppFolder) -> Application {
        // Optimization P2: Use the index instead of linear search through displayOrder
        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        let compositeIcon = generateFolderIcon(containedApps)

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

    func generateFolderIcon(_ apps: [Application], gridSize: Int = 3) -> NSImage? {
        guard !apps.isEmpty else { return nil }

        let iconSize: CGFloat = 120
        let cellSize = iconSize / CGFloat(gridSize)
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))

        image.lockFocus()
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
        image.unlockFocus()
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
        updateRecentApps()

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
    static func scanApplications(directories: [String], hiddenPaths: Set<String>) async -> AppScanResult {
        var apps: [Application] = []
        var metadata: [String: AppMetadata] = [:]

        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir) else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in contents {
                let fullPath = (dir as NSString).appendingPathComponent(item)
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

                // Determine if this is a folder containing multiple apps
                // Check for contained apps both for regular folders and .app bundles (like Xcode)
                let containedApps = Self.findContainedApps(in: fullPath)
                let isFolder = (containedApps?.isEmpty == false)

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

        return AppScanResult(metadata: metadata, apps: apps)
    }

    /// Finds .app bundles inside a directory, including nested paths like Contents/Developer/Applications/
    private static func findContainedApps(in directoryPath: String) -> [String]? {
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
    }

    // MARK: - Recent Apps Tracking
    func recordAppLaunch(at path: String) {
        recentAppLaunchTimes[path] = Date()
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
        guard selectedAppIndex >= 0, selectedAppIndex < displayOrder.count else { return false }
        let app = displayOrder[selectedAppIndex]
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

    func setApplications(_ apps: [Application]) {
        displayOrder = apps
        rebuildAppPathIndex()
        updateFilteredApps()
    }

    func updateCustomOrder(from apps: [Application]) {
        for (index, app) in apps.enumerated() {
            customOrder[app.path] = index
        }
        displayOrder = apps
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
    }

    // MARK: - Computed Properties & Display Helpers

    var visibleApplications: [Application] {
        displayOrder.filter { !hiddenAppPaths.contains($0.path) }
    }

    func getDisplayedApps() -> [Application] {
        // If inside a folder, only show the apps in that folder
        if let folderId = currentFolderId, let folder = folders.first(where: { $0.id == folderId }) {
            return folder.appPaths.compactMap { path -> Application? in
                visibleApplications.first { $0.path == path }
            }
        } else {
            // At root level: show all visible apps plus folder icons
            var currentApps = visibleApplications
            // Add folder applications
            for folder in folders {
                let containedApps = folder.appPaths.compactMap { path -> Application? in
                    visibleApplications.first { $0.path == path }
                }
                if !containedApps.isEmpty {
                    currentApps.append(getFolderApplication(folder))
                }
            }

            if !searchTerm.isEmpty {
                let lower = searchTerm.lowercased()
                currentApps = currentApps.filter { $0.lowercaseName.contains(lower) }
            }
            // Quick Win 3: Only sort by custom order if non-empty, otherwise use default sort
            if !customOrder.isEmpty {
                currentApps.sort { (a, b) in
                    (customOrder[a.path] ?? Int.max) < (customOrder[b.path] ?? Int.max)
                }
            } else {
                currentApps = sortedApplications(currentApps)
            }
            return currentApps
        }
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
