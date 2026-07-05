import Foundation
import AppKit
import Observation

/// Manages the application library: scanning, folders, icon caching, smart categories, and display ordering.
@MainActor
@Observable
class LibraryScanState {
    var isLoading = true
    var displayOrder: [Application] = []
    private var appPathIndex: [String: Application] = [:]
    var loadedIconsByPath: [String: NSImage] = [:]
    var dataVersion: Int = 0

    private struct ScanCache {
        let dirMtimes: [String: Date]
        let timestamp: Date
    }
    private var scanCache: ScanCache?
    var hiddenAppPaths: Set<String> = [] {
        didSet { dataVersion += 1; PreferencesStore.shared.saveHiddenApps(hiddenAppPaths); updateFilteredApps() }
    }
    var customDirectories: [String] = [] {
        didSet { allScanDirectories = Self.defaultScanDirectories + customDirectories; PreferencesStore.shared.saveCustomDirectories(customDirectories) }
    }
    var allScanDirectories: [String] = [] {
        didSet { dataVersion += 1 }
    }
    private var customDirectoryBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURLs: [String: URL] = [:]
    var folders: [AppFolder] = [] {
        didSet { FolderStore.shared.folders = folders; cachedAppsInAnyFolder = nil }
    }
    private var cachedAppsInAnyFolder: Set<String>?
    var currentFolderId: String? = nil {
        didSet { dataVersion += 1; PreferencesStore.shared.saveCurrentFolderId(currentFolderId) }
    }
    var _recentApps: [Application] = []
    var _mostUsedApps: [Application] = []
    var customOrder: [String: Int] = [:] {
        didSet { dataVersion += 1; PreferencesStore.shared.saveCustomOrder(customOrder) }
    }
    var sortOption: ApplicationSorter.SortOption = .name {
        didSet { dataVersion += 1; PreferencesStore.shared.saveSortOption(sortOption.rawValue) }
    }

    private var cachedVisibleApps: (version: Int, apps: [Application])?
    private var cachedDisplayedApps: (version: Int, apps: [Application])?
    private var refreshTimer: Timer?
    private var cacheRefreshTimer: Timer?
    weak var settings: SettingsAppearance?
    weak var navigation: NavigationSelection?

    init() {
        loadHiddenApps()
        // Reset FolderStore singleton to ensure test isolation and fresh state on each initialization.
        if let savedFolders = PreferencesStore.shared.loadFolders() { folders = savedFolders } else { folders = []; FolderStore.shared.folders = [] }
        loadCustomOrder()
        loadCurrentFolderId()
        loadSortOption()
        loadCustomDirectories()
        loadRecentLaunchTimes()
    }

    private func loadCustomOrder() {
        if let order = PreferencesStore.shared.loadCustomOrder() { customOrder = order }
    }
    private func loadCurrentFolderId() {
        currentFolderId = PreferencesStore.shared.loadCurrentFolderId()
    }
    private func loadSortOption() {
        if let raw = PreferencesStore.shared.loadSortOption(), let option = ApplicationSorter.SortOption(rawValue: raw) { sortOption = option } else { sortOption = .name }
    }

    func startLoading() async {
        guard isLoading else { return }
        let allDirs = allScanDirectories
        let result = await Task.detached(priority: .userInitiated) {
            ApplicationScanner.shared.scanDirectories(directories: allDirs)
        }.value
        self.displayOrder = self.sortedApplications(result.apps)
        rebuildAppPathIndex()
        dataVersion += 1
        self.updateFilteredApps()
        self.setupRefreshTimer()
        isLoading = false
        await self.loadMissingIcons()
        self.updateRecentApps()
    }

    private func loadHiddenApps() {
        if let paths = PreferencesStore.shared.loadHiddenApps() { hiddenAppPaths = paths }
    }
    private func loadFolders() {
        if let savedFolders = PreferencesStore.shared.loadFolders() { folders = savedFolders }
    }
    private func loadCustomDirectories() {
        customDirectoryBookmarks = PreferencesStore.shared.loadCustomDirectoryBookmarks() ?? [:]
        if let dirs = PreferencesStore.shared.loadCustomDirectories() {
            customDirectories = dirs
            allScanDirectories = Self.defaultScanDirectories + dirs
            resolveCustomDirectoryAccess(for: dirs)
        } else {
            allScanDirectories = Self.defaultScanDirectories
        }
    }
    private func resolveCustomDirectoryAccess(for paths: [String]) {
        for path in paths {
            guard let bookmarkData = customDirectoryBookmarks[path] else { continue }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            if url.startAccessingSecurityScopedResource() { activeSecurityScopedURLs[path] = url }
        }
    }
    private func loadRecentLaunchTimes() {
        RecentAppsTracker.shared.loadRecentLaunchTimes()
        updateRecentApps()
    }

    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: settings?.refreshInterval ?? 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshDisplayOrder() }
        }
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCachedIcons() }
        }
    }

    func cleanupTimerAndObservers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func loadMissingIcons() async {
        let priorityApps = Array(displayOrder.prefix(AppMetrics.priorityIconLoadCount))
        let priorityIcons = await IconService.shared.loadMissingIcons(for: priorityApps)
        if !priorityIcons.isEmpty { applyLoadedIcons(priorityIcons) }
        let remainingApps = Array(displayOrder.dropFirst(AppMetrics.priorityIconLoadCount))
        guard !remainingApps.isEmpty else { return }
        var remainingIcons: [(String, NSImage)] = []
        for start in stride(from: 0, to: remainingApps.count, by: AppMetrics.priorityIconLoadCount) {
            let end = min(start + AppMetrics.priorityIconLoadCount, remainingApps.count)
            let chunkIcons = await IconService.shared.loadMissingIcons(for: Array(remainingApps[start..<end]))
            remainingIcons.append(contentsOf: chunkIcons)
        }
        if !remainingIcons.isEmpty { applyLoadedIcons(remainingIcons) }
    }

    private func applyLoadedIcons(_ loadedIcons: [(String, NSImage)]) {
        displayOrder = IconService.shared.updateIconsInPlace(for: displayOrder, with: loadedIcons)
        for (path, icon) in loadedIcons { loadedIconsByPath[path] = icon }
        rebuildAppPathIndex()
        dataVersion += 1
        cachedVisibleApps = nil
        cachedDisplayedApps = nil
        let changedPaths = Set(loadedIcons.map(\.0))
        IconService.shared.refreshFolderIcons(folders: folders, appPathIndex: appPathIndex, changedAppPaths: changedPaths)
    }

    func refreshCachedIcons() async {
        let currentPaths = Set(displayOrder.map(\.path))
        IconCacheManager.shared.pruneDeletedApps(currentAppPaths: currentPaths)
        let cachedApps = IconCacheManager.shared.cachedAppPaths()
        let cachedByPath: [String: Date] = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.appPath, $0.cachedMtime) })
        var staleApps: [Application] = []
        for (appPath, cachedMtime) in cachedByPath {
            guard currentPaths.contains(appPath), let app = appPathIndex[appPath] else { continue }
            if let currentMtime = IconCacheManager.shared.cachedMtime(for: appPath) {
                let cachedSec = Int(cachedMtime.timeIntervalSince1970)
                let currentSec = Int(currentMtime.timeIntervalSince1970)
                if cachedSec != currentSec { staleApps.append(app) }
            }
        }
        guard !staleApps.isEmpty else { return }
        let refreshedIcons = await IconService.shared.loadMissingIcons(for: staleApps)
        if !refreshedIcons.isEmpty { applyLoadedIcons(refreshedIcons) }
    }

    private func rebuildAppPathIndex() {
        appPathIndex.removeAll(keepingCapacity: true)
        for app in displayOrder { appPathIndex[app.path] = app }
    }

    func updateFilteredApps() {
        // dataVersion may not have been bumped yet (searchTerm changes debounce their bump), so the
        // getDisplayedApps cache could still hold a pre-change result. Invalidate it so this explicit
        // recompute reflects the current searchTerm/category rather than a stale cached list.
        cachedDisplayedApps = nil

        // Reset selectedAppIndex when display list becomes empty
        let displayedApps = getDisplayedApps(searchTerm: navigation?.searchTerm ?? "", showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: customOrder, sortOption: sortOption, selectedCategory: .all, columnCount: settings?.columnCount ?? 4)
        if displayedApps.isEmpty { navigation?.selectedAppIndex = -1 }

        var counts: [AppCategory: Int] = [:]
        let searchFilter = navigation?.searchTerm ?? ""
        let visible = visibleApplications
        let filtered = applySearchFilter(to: visible, searchTerm: searchFilter)
        for app in filtered {
            let cat = getCategory(for: app)
            counts[cat, default: 0] += 1
        }
        counts[.utilities] = 0
        counts[.all] = filtered.count
        let filteredPaths = Set(filtered.map(\.path))
        counts[.mostUsed] = _mostUsedApps.filter { filteredPaths.contains($0.path) }.count
        counts[.recentlyLaunched] = _recentApps.filter { filteredPaths.contains($0.path) }.count
        counts[.newlyInstalled] = filtered.filter { isNewlyInstalled($0) }.count
        navigation?.categoryCounts = counts
    }

    func sortedApplications(_ apps: [Application]) -> [Application] {
        if !customOrder.isEmpty {
            return apps.sorted {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av < bv }
            }
        }
        return ApplicationSorter.sort(apps, by: sortOption)
    }

    func refreshDisplayOrder() async {
        let allDirs = allScanDirectories
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            if let mtime = try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date { currentMtimes[dir] = mtime }
        }
        if let cache = scanCache {
            let hasChanged = allDirs.contains { currentMtimes[$0] != cache.dirMtimes[$0] }
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < (settings?.refreshInterval ?? 300) * 2 { return }
        }
        let result = await Task.detached(priority: .utility) {
            ApplicationScanner.shared.scanDirectories(directories: allDirs)
        }.value
        scanCache = ScanCache(dirMtimes: currentMtimes, timestamp: Date())
        let preservedIcons = Dictionary(uniqueKeysWithValues: displayOrder.compactMap { app -> (String, NSImage)? in
            guard let icon = app.icon else { return nil }
            return (app.path, icon)
        })
        let appsWithPreservedIcons = IconService.shared.applicationsPreservingLoadedIcons(from: result.apps, loadedIconsByPath: preservedIcons)
        self.displayOrder = self.sortedApplications(appsWithPreservedIcons)
        rebuildAppPathIndex()
        dataVersion += 1
        self.updateFilteredApps()
        await self.loadMissingIcons()
        let currentPaths = Set(displayOrder.map(\.path))
        loadedIconsByPath = loadedIconsByPath.filter { currentPaths.contains($0.key) }
        self.updateRecentApps()
    }

    func recordAppLaunch(at path: String) {
        RecentAppsTracker.shared.recordAppLaunch(at: path)
        updateRecentApps()
        dataVersion += 1
        updateFilteredApps()
    }

    func isRecentApp(_ path: String) -> Bool { return _recentApps.contains { $0.path == path } }
    func getRecentApps() -> [Application] { return _recentApps }
    private func updateRecentApps() {
        let recentPaths = RecentAppsTracker.shared.getRecentPaths()
        _recentApps = recentPaths.compactMap { appPathIndex[$0] }
        updateMostUsedApps()
    }
    private func updateMostUsedApps() {
        let mostUsedPaths = RecentAppsTracker.shared.getMostUsedPaths(limit: AppMetrics.maxRecentApps)
        _mostUsedApps = mostUsedPaths.compactMap { appPathIndex[$0] }
    }

    func toggleHiddenApp(_ path: String) {
        if hiddenAppPaths.contains(path) { hiddenAppPaths.remove(path) } else { hiddenAppPaths.insert(path) }
        cachedDisplayedApps = nil
    }
    func toggleHiddenApp(_ app: Application) { toggleHiddenApp(app.path) }
    func isAppHidden(_ path: String) -> Bool { return hiddenAppPaths.contains(path) }

    func setSortOption(_ option: ApplicationSorter.SortOption) {
        sortOption = option
        customOrder.removeAll()
        displayOrder = sortedApplications(displayOrder)
    }
    func setApplications(_ apps: [Application]) {
        displayOrder = sortedApplications(apps)
        dataVersion += 1
        rebuildAppPathIndex()
        updateRecentApps()
        updateFilteredApps()
    }
    func updateCustomOrder(from apps: [Application]) {
        for (index, app) in apps.enumerated() { customOrder[app.path] = index }
        displayOrder = apps
        dataVersion += 1
        updateFilteredApps()
        PreferencesStore.shared.saveCustomOrder(customOrder)
    }

    func getCategory(for app: Application) -> AppCategory {
        if app.path.hasPrefix("/System") { return .system }
        return .user
    }
    func isMostUsed(_ app: Application) -> Bool { return _mostUsedApps.contains { $0.path == app.path } }
    func isRecentlyLaunched(_ app: Application) -> Bool { return _recentApps.contains { $0.path == app.path } }
    func isNewlyInstalled(_ app: Application) -> Bool { Date().timeIntervalSince(app.installationDate) < AppMetrics.newlyInstalledWindowSeconds }
    func matchesSelectedCategory(_ app: Application, selectedCategory: AppCategory) -> Bool {
        switch selectedCategory {
        case .all: return true
        case .system, .utilities, .user: return getCategory(for: app) == selectedCategory
        case .mostUsed: return isMostUsed(app)
        case .recentlyLaunched: return isRecentlyLaunched(app)
        case .newlyInstalled: return isNewlyInstalled(app)
        }
    }

    func removeCustomDirectory(_ path: String) {
        customDirectories.removeAll { $0 == path }
        if let url = activeSecurityScopedURLs.removeValue(forKey: path) { url.stopAccessingSecurityScopedResource() }
        if customDirectoryBookmarks.removeValue(forKey: path) != nil { PreferencesStore.shared.saveCustomDirectoryBookmarks(customDirectoryBookmarks) }
        Task { await refreshDisplayOrder() }
    }
    func addCustomDirectory(_ path: String, bookmarkData: Data? = nil) {
        guard ApplicationScanner.isValidCustomDirectory(path), !customDirectories.contains(path) else { return }
        customDirectories.append(path)
        if let bookmarkData { customDirectoryBookmarks[path] = bookmarkData; PreferencesStore.shared.saveCustomDirectoryBookmarks(customDirectoryBookmarks) }
    }

    var visibleApplications: [Application] {
        if let c = cachedVisibleApps, c.version == dataVersion { return c.apps }
        let apps = displayOrder.filter { !hiddenAppPaths.contains($0.path) }
        cachedVisibleApps = (dataVersion, apps)
        return apps
    }

    func getDisplayedApps(searchTerm: String, showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory, columnCount: Int) -> [Application] {
        if let cached = cachedDisplayedApps, cached.version == dataVersion { return cached.apps }
        let baseApps = getBaseAppsForCurrentContext()
        let filtered = applySearchFilter(to: baseApps, searchTerm: searchTerm)
        let result = applyOrdering(to: filtered, searchTerm: searchTerm, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory)
        cachedDisplayedApps = (dataVersion, result)
        return result
    }

    private func getBaseAppsForCurrentContext() -> [Application] {
        let appsInAnyFolder: Set<String> = {
            if let cached = cachedAppsInAnyFolder { return cached }
            let set = folders.reduce(into: Set<String>()) { $0.formUnion($1.appPaths) }
            cachedAppsInAnyFolder = set
            return set
        }()
        if let folderId = currentFolderId { return getAllAppsIncludingChildFolders(for: folderId) }
        let looseApps = visibleApplications.filter { !appsInAnyFolder.contains($0.path) }
        let folderIcons: [Application] = folders.compactMap { folder in
            let hasVisible = folder.appPaths.contains { path in
                guard !hiddenAppPaths.contains(path), appPathIndex[path] != nil else { return false }
                return true
            }
            return hasVisible ? getFolderApplication(folder) : nil
        }
        return looseApps + folderIcons
    }

    private func applySearchFilter(to apps: [Application], searchTerm: String) -> [Application] {
        guard !searchTerm.isEmpty else { return apps }
        let lower = searchTerm.lowercased()
        if currentFolderId == nil { return rankedBySearchMatch(visibleApplications, query: lower) }
        return rankedBySearchMatch(apps, query: lower)
    }

    private func rankedBySearchMatch(_ apps: [Application], query: String) -> [Application] {
        apps.compactMap { app -> (Application, Int)? in
            guard let rank = app.searchMatchRank(query) else { return nil }
            return (app, rank)
        }
        .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.lowercaseName < rhs.0.lowercaseName }
        .map(\.0)
    }

    private func applyOrdering(to apps: [Application], searchTerm: String, showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        guard !searchTerm.isEmpty else { return applyNonSearchOrdering(to: apps, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory) }
        return apps
    }

    private func applyNonSearchOrdering(to apps: [Application], showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        var ordered = apps
        var folderFirstApplied = false
        if showFoldersFirst && !ordered.isEmpty {
            let folderApps = ordered.filter { $0.isFolder }
            let nonFolderApps = ordered.filter { !$0.isFolder }
            if !folderApps.isEmpty && !nonFolderApps.isEmpty { ordered = folderApps + nonFolderApps; folderFirstApplied = true }
        }
        if !customOrder.isEmpty {
            return ordered.sorted {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av < bv }
            }
        }
        if folderFirstApplied { return ordered }
        if selectedCategory == .recentlyLaunched {
            return ordered.sorted {
                let a = RecentAppsTracker.shared.recentAppLaunchTimes[$0.path], b = RecentAppsTracker.shared.recentAppLaunchTimes[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av > bv }
            }
        }
        if selectedCategory == .mostUsed {
            return ordered.sorted {
                let a = RecentAppsTracker.shared.appLaunchCounts[$0.path], b = RecentAppsTracker.shared.appLaunchCounts[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av > bv }
            }
        }
        return sortedApplications(ordered)
    }

    func getFolderApplication(_ folder: AppFolder) -> Application {
        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        var app = FolderStore.shared.getFolderApplication(folder, containedApps: containedApps, displayCount: folder.appPaths.count)
        app.icon = IconService.shared.generateFolderIcon(containedApps, for: folder.id)
        return app
    }

    static var defaultScanDirectories: [String] { ApplicationScanner.defaultScanDirectories }

    @discardableResult
    func createFolder(name: String, appPaths: [String]) -> AppFolder {
        let folder = FolderStore.shared.createFolder(name: name, appPaths: appPaths)
        folders = FolderStore.shared.folders
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
        return folder
    }
    func deleteFolder(folderId: String) {
        FolderStore.shared.deleteFolder(folderId: folderId)
        folders = FolderStore.shared.folders
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
    }
    func renameFolder(folderId: String, newName: String) {
        FolderStore.shared.renameFolder(folderId: folderId, newName: newName)
        folders = FolderStore.shared.folders
    }
    func addAppToFolder(_ appPath: String, folderId: String) {
        FolderStore.shared.addAppToFolder(appPath, folderId: folderId)
        folders = FolderStore.shared.folders
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
    }
    func removeAppFromFolder(_ appPath: String, folderId: String) {
        FolderStore.shared.removeAppFromFolder(appPath, folderId: folderId)
        folders = FolderStore.shared.folders
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
        if folderId == currentFolderId && currentFolder?.appPaths.isEmpty ?? true { currentFolderId = nil }
    }
    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) {
        FolderStore.shared.moveAppInFolder(appPath, from: folderId, to: toFolderId)
        folders = FolderStore.shared.folders
    }
    func openFolder(_ folderId: String) {
        currentFolderId = folderId
        PreferencesStore.shared.saveCurrentFolderId(folderId)
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
    }
    func closeFolder() {
        currentFolderId = nil
        PreferencesStore.shared.saveCurrentFolderId(nil)
        rebuildAppPathIndex()
        cachedDisplayedApps = nil
    }

    var currentFolder: AppFolder? {
        guard let folderId = currentFolderId else { return nil }
        return folders.first { $0.id == folderId }
    }

    func getAllAppsIncludingChildFolders(for folderId: String) -> [Application] {
        FolderStore.shared.getAllAppsIncludingChildFolders(for: folderId, appPathIndex: appPathIndex, hiddenAppPaths: hiddenAppPaths, customOrder: customOrder, sortOption: sortOption)
    }
}
