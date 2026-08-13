import Foundation
import AppKit
import Observation

/// Manages the application library: scanning, folders, icon caching, smart categories, and display ordering.
@MainActor
@Observable
class LibraryScanState {
    var isLoading = true
    var displayOrder: [Application] = []
    var appPathIndex: [String: Application] = [:]
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
        didSet {
            let validated = customDirectories.filter { ApplicationScanner.isValidCustomDirectory($0) }
            allScanDirectories = Self.defaultScanDirectories + validated
            PreferencesStore.shared.saveCustomDirectories(customDirectories)
        }
    }
    var allScanDirectories: [String] = [] {
        didSet { dataVersion += 1 }
    }
    private var customDirectoryBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURLs: [String: URL] = [:]
    var folders: [AppFolder] = [] {
        didSet { FolderStore.shared.folders = folders; cachedAppsInAnyFolder = nil }
    }
    var cachedAppsInAnyFolder: Set<String>?
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
    var cachedDisplayedApps: (version: Int, apps: [Application])?
    var isScanning = false
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
        // Reclaim cache directories from superseded key schemes, which nothing else deletes.
        IconCacheManager.shared.removeSupersededCaches()
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
            Task { @MainActor in
                guard let self, !self.isScanning else { return }
                await self.refreshDisplayOrder()
            }
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

    /// Called when the system appearance (light/dark) changes. Re-decodes all cached icons
    /// under the new appearance so theme-aware icons pick up the correct variant.
    func handleAppearanceChange() {
        // Nil all app icons so they re-decode with the new appearance.
        displayOrder = displayOrder.map { app in
            var updated = app
            updated.icon = nil
            return updated
        }
        rebuildAppPathIndex()
        dataVersion += 1

        // Evict folder icons so they regenerate with the new app icons.
        IconService.shared.refreshFolderIcons(folders: folders, appPathIndex: appPathIndex, changedAppPaths: [])

        cachedVisibleApps = nil
        cachedDisplayedApps = nil

        // Re-load and decode all icons under the new appearance.
        Task { @MainActor in
            await self.loadMissingIcons()
        }
    }

    func loadMissingIcons() async {
        let priorityApps = Array(displayOrder.prefix(ScanMetrics.priorityIconLoadCount))
        let priorityIcons = await IconService.shared.loadMissingIcons(for: priorityApps)
        if !priorityIcons.isEmpty { applyLoadedIcons(priorityIcons) }
        let remainingApps = Array(displayOrder.dropFirst(ScanMetrics.priorityIconLoadCount))
        guard !remainingApps.isEmpty else { return }
        // Load remaining apps in chunks, applying each chunk immediately so icons fill progressively
        // instead of appearing in one late pop. Keeping chunk size at 60 (≈3 applies) balances
        // UI updates against the cost of `applyLoadedIcons` (index rebuild + folder re-generation).
        for start in stride(from: 0, to: remainingApps.count, by: ScanMetrics.priorityIconLoadCount) {
            let end = min(start + ScanMetrics.priorityIconLoadCount, remainingApps.count)
            let chunkIcons = await IconService.shared.loadMissingIcons(for: Array(remainingApps[start..<end]))
            if !chunkIcons.isEmpty { applyLoadedIcons(chunkIcons) }
        }
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
        let appPathIndex = self.appPathIndex
        // Resolved here, on the main actor — the detached task below must not read `NSApp`.
        let appearance = IconAppearance.current
        IconCacheManager.shared.pruneDeletedApps(currentAppPaths: currentPaths)

        // Move directory enumeration to a background task to avoid blocking the main thread
        // (measured at 32 ms warm / 194 ms cold on disk cache scan).
        let staleApps: [Application] = await Task.detached(priority: .utility) {
            let cachedApps = IconCacheManager.shared.cachedAppPaths(appearance: appearance)
            // `uniquingKeysWith` rather than `uniqueKeysWithValues`: this list is built from
            // whatever .meta files are on disk, and a duplicate path there must degrade to
            // "refresh it once", never trap the process. Keeping the newer mtime makes a
            // duplicate look as fresh as its freshest entry, so it isn't refreshed forever.
            let cachedByPath: [String: Date] = Dictionary(
                cachedApps.map { ($0.appPath, $0.cachedMtime) },
                uniquingKeysWith: { max($0, $1) }
            )
            var stale: [Application] = []
            for (appPath, cachedMtime) in cachedByPath {
                guard currentPaths.contains(appPath), let app = appPathIndex[appPath] else { continue }
                if let currentMtime = IconCacheManager.shared.cachedMtime(for: appPath) {
                    let cachedSec = Int(cachedMtime.timeIntervalSince1970)
                    let currentSec = Int(currentMtime.timeIntervalSince1970)
                    if cachedSec != currentSec { stale.append(app) }
                }
            }
            return stale
        }.value

        guard !staleApps.isEmpty else { return }
        let refreshedIcons = await IconService.shared.loadMissingIcons(for: staleApps, force: true)
        if !refreshedIcons.isEmpty { applyLoadedIcons(refreshedIcons) }
    }

    private func rebuildAppPathIndex() {
        appPathIndex.removeAll(keepingCapacity: true)
        for app in displayOrder { appPathIndex[app.path] = app }
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

    /// - Parameter force: when `true`, bypasses the staleness guard (so the scan always runs)
    ///   and wipes every cached icon — disk and memory — instead of preserving currently-loaded
    ///   ones, so an icon that's rendering wrong gets re-decoded from scratch rather than being
    ///   carried forward. Used by the manual "Refresh Now" button; the automatic background
    ///   refresh always passes `false` to stay cheap and incremental.
    func refreshDisplayOrder(force: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let allDirs = allScanDirectories
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            if let mtime = try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date { currentMtimes[dir] = mtime }
        }
        if !force, let cache = scanCache {
            let hasChanged = allDirs.contains { currentMtimes[$0] != cache.dirMtimes[$0] }
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < (settings?.refreshInterval ?? 300) * 2 { return }
        }
        let result = await Task.detached(priority: .utility) {
            ApplicationScanner.shared.scanDirectories(directories: allDirs)
        }.value
        scanCache = ScanCache(dirMtimes: currentMtimes, timestamp: Date())

        let freshApps: [Application]
        if force {
            IconCacheManager.shared.clearAll()
            loadedIconsByPath.removeAll()
            freshApps = result.apps
        } else {
            // Two entries for one path would mean the same icon twice, so either wins.
            let preservedIcons = Dictionary(
                displayOrder.compactMap { app -> (String, NSImage)? in
                    guard let icon = app.icon else { return nil }
                    return (app.path, icon)
                },
                uniquingKeysWith: { first, _ in first }
            )
            freshApps = IconService.shared.applicationsPreservingLoadedIcons(from: result.apps, loadedIconsByPath: preservedIcons)
        }
        self.displayOrder = self.sortedApplications(freshApps)
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
        let mostUsedPaths = RecentAppsTracker.shared.getMostUsedPaths(limit: ScanMetrics.maxRecentApps)
        _mostUsedApps = mostUsedPaths.compactMap { appPathIndex[$0] }
    }

    static let permanentlyHiddenAppPaths: Set<String> = [
        "/System/Applications/Launchpad.app",
        "/Applications/MacMuster.app",
        "/Applications/Launchie.app",
        "/Applications/Apps.app"
    ]

    func toggleHiddenApp(_ path: String) {
        guard !Self.permanentlyHiddenAppPaths.contains(path) else { return }
        if hiddenAppPaths.contains(path) { hiddenAppPaths.remove(path) } else { hiddenAppPaths.insert(path) }
        cachedDisplayedApps = nil
    }
    func toggleHiddenApp(_ app: Application) { toggleHiddenApp(app.path) }
    func isAppHidden(_ path: String) -> Bool {
        return hiddenAppPaths.contains(path) || Self.permanentlyHiddenAppPaths.contains(path)
    }

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
        let apps = displayOrder.filter {
            guard !Self.permanentlyHiddenAppPaths.contains($0.path) else { return false }
            if settings?.showHiddenApps ?? false { return true }
            return !hiddenAppPaths.contains($0.path)
        }
        cachedVisibleApps = (dataVersion, apps)
        return apps
    }

    func getFolderApplication(_ folder: AppFolder) -> Application {
        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        var app = FolderStore.shared.getFolderApplication(folder, containedApps: containedApps, displayCount: folder.appPaths.count)
        app.icon = IconService.shared.generateFolderIcon(containedApps, for: folder.id)
        return app
    }

    static var defaultScanDirectories: [String] { ApplicationScanner.defaultScanDirectories }

    @discardableResult
    func createFolder(name: String, appPaths: [String]) -> AppFolder? {
        guard currentFolderId == nil else { return nil }
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
    func moveAppToRoot(_ appPath: String, folderId: String) {
        removeAppFromFolder(appPath, folderId: folderId)
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
        let effectiveHiddenPaths: Set<String> = (settings?.showHiddenApps ?? false) ? [] : hiddenAppPaths
        let apps = FolderStore.shared.getAllAppsIncludingChildFolders(for: folderId, appPathIndex: appPathIndex, hiddenAppPaths: effectiveHiddenPaths, customOrder: customOrder, sortOption: sortOption)
        return apps.filter { !Self.permanentlyHiddenAppPaths.contains($0.path) }
    }
}
