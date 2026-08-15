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
        didSet {
            // Re-point the watcher at the new set and rescan, since the apps on offer just
            // changed. Skipped until the initial load has run, which is what starts the watcher
            // in the first place, and skipped when the value didn't actually change so redundant
            // assignments (e.g. re-saving the same custom directories) don't invalidate every
            // display cache for nothing. This only fires from a config change (`customDirectories`
            // add/remove) — a deliberate user action, not filesystem churn — so it schedules with
            // no settle delay rather than the 1s one FSEvents-driven calls use; a plain `.scheduled`
            // refresh would not do here either: adding or removing a directory moves no mtime, so
            // the staleness guard would skip the very rescan the change calls for.
            guard !isLoading, oldValue != allScanDirectories else { return }
            dataVersion += 1
            startWatchingScanDirectories()
            scheduleFileSystemRescan(delay: 0)
        }
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
    // INVARIANT: every writer of `customOrder` must go through this property (or bump
    // `dataVersion` separately). `DisplayQuery` does not include `customOrder` because it is a
    // dictionary, too costly to compare on every `getDisplayedApps` call. The cache stays correct
    // only because each mutation here bumps `dataVersion`, which invalidates `cachedDisplayedApps`.
    // Adding a new code path that mutates the drag order without this bump will silently serve a
    // stale grid.
    var customOrder: [String: Int] = [:] {
        didSet { dataVersion += 1; PreferencesStore.shared.saveCustomOrder(customOrder) }
    }
    var sortOption: ApplicationSorter.SortOption = .name {
        didSet { dataVersion += 1; PreferencesStore.shared.saveSortOption(sortOption.rawValue) }
    }

    private var cachedVisibleApps: (version: Int, apps: [Application])?
    /// Everything about a `getDisplayedApps` request that changes its answer.
    ///
    /// The cache used to key on `dataVersion` alone and ignore the arguments entirely. That held
    /// together only because every setter feeding those arguments also bumps `dataVersion` — an
    /// unwritten invariant spread across several files, where the penalty for breaking it is a
    /// silently stale grid rather than a failure. `customOrder` is still covered that way: it is
    /// a dictionary, too costly to compare per call, and its own observer bumps `dataVersion`.
    struct DisplayQuery: Equatable {
        let version: Int
        let searchTerm: String
        let showFoldersFirst: Bool
        let sortOption: ApplicationSorter.SortOption
        let selectedCategory: AppCategory
    }
    var cachedDisplayedApps: (query: DisplayQuery, apps: [Application])?
    var isScanning = false
    private var refreshTimer: Timer?
    private var cacheRefreshTimer: Timer?
    private var directoryWatcher: DirectoryWatcher?
    private var pendingRescanTask: Task<Void, Never>?
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
        self.startWatchingScanDirectories()
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

    /// Subscribes to filesystem changes in the scanned directories so a newly installed app shows
    /// up in seconds instead of waiting out the refresh interval. The periodic timer stays as a
    /// backstop for anything the watcher misses (a stream dropped across sleep, a directory that
    /// did not exist when the watcher started).
    private func startWatchingScanDirectories() {
        let watcher = directoryWatcher ?? DirectoryWatcher { [weak self] in
            Task { @MainActor in self?.scheduleFileSystemRescan() }
        }
        directoryWatcher = watcher
        watcher.start(paths: allScanDirectories)
    }

    /// Coalesces a burst of filesystem events into one rescan, after settling for `delay`.
    ///
    /// Installing an app is hundreds of writes over a noticeable stretch of time, and scanning
    /// partway through would surface a half-copied bundle. Each FSEvents-driven call pushes the
    /// rescan out, so the scan lands once the directory has been quiet for `delay`
    /// (`installSettleNanoseconds`). A directory add/remove is a deliberate user action rather
    /// than filesystem churn, so it passes `delay: 0` to skip that settle — but still goes
    /// through here rather than calling `refreshDisplayOrder` directly, so a scan already in
    /// flight gets queued behind instead of silently dropped.
    private func scheduleFileSystemRescan(delay: UInt64 = ScanMetrics.installSettleNanoseconds) {
        pendingRescanTask?.cancel()
        pendingRescanTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard let self, !Task.isCancelled else { return }

            // `refreshDisplayOrder` drops the request outright if a scan is already running, so
            // wait one out rather than losing the event that prompted this. Polls on
            // `scanCompletionPollNanoseconds`, not `delay`/`installSettleNanoseconds` — those are
            // burst-coalescing delays, unrelated to how quickly a finished scan should be noticed.
            while isScanning {
                try? await Task.sleep(nanoseconds: ScanMetrics.scanCompletionPollNanoseconds)
                if Task.isCancelled { return }
            }
            await refreshDisplayOrder(reason: .fileSystemEvent)
        }
    }

    func cleanupTimerAndObservers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = nil
        pendingRescanTask?.cancel()
        pendingRescanTask = nil
        directoryWatcher?.stop()
        directoryWatcher = nil
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

    /// Why a refresh is happening. "Always scan" and "rebuild icons" are independent decisions,
    /// and collapsing them into one `force` flag left no way to express the case the filesystem
    /// watcher needs: scan right now, but keep the icons we already decoded.
    enum RefreshReason {
        /// Periodic timer. Skips the scan entirely when no watched directory's mtime moved and
        /// the last scan is recent — the cheap, common case.
        case scheduled
        /// A watched directory changed on disk. Always scans: an app installed into an existing
        /// subdirectory (`/Applications/SomeVendor/Foo.app`) leaves `/Applications`'s own mtime
        /// untouched, so the staleness guard would otherwise skip precisely the install we were
        /// told about. Icons are preserved — nothing about an install invalidates them.
        case fileSystemEvent
        /// The "Refresh Now" button. Always scans, and wipes every cached icon so one that is
        /// rendering wrong gets re-decoded from scratch instead of being carried forward.
        case userRequested

        var bypassesStalenessCheck: Bool { self != .scheduled }
        var rebuildsIcons: Bool { self == .userRequested }
    }

    func refreshDisplayOrder(reason: RefreshReason = .scheduled) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let allDirs = allScanDirectories
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            if let mtime = try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date { currentMtimes[dir] = mtime }
        }
        if !reason.bypassesStalenessCheck, let cache = scanCache {
            let hasChanged = allDirs.contains { currentMtimes[$0] != cache.dirMtimes[$0] }
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < (settings?.refreshInterval ?? 300) * 2 { return }
        }
        let result = await Task.detached(priority: .utility) {
            ApplicationScanner.shared.scanDirectories(directories: allDirs)
        }.value
        scanCache = ScanCache(dirMtimes: currentMtimes, timestamp: Date())

        let freshApps: [Application]
        if reason.rebuildsIcons {
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

    /// Recomputes the launch-history lists and tab counts after "Show Recent Apps" is toggled.
    ///
    /// `RecentAppsTracker` starts or stops reporting history the instant the setting changes, but
    /// `_recentApps` and `_mostUsedApps` are snapshots — without this they stay stale until the
    /// next launch or scan, so re-enabling the setting would leave the tabs reading zero.
    func recentAppsAvailabilityChanged() {
        updateRecentApps()
        dataVersion += 1
        updateFilteredApps()
    }

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
        // The rescan is driven by `allScanDirectories`'s observer, which the mutation above trips.
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
