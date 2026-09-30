import Foundation
import AppKit
import Observation

/// The icon one grid cell draws, observable on its own.
///
/// `@Observable` tracks whole properties, so a cell that reads its icon out of `appPathIndex`
/// depends on the *entire* index: every icon batch that lands — about seven on a cold launch of
/// a 400-app library — invalidated and re-rendered every visible cell, not just the ones whose
/// icons arrived. One slot per path narrows that dependency to the cell's own icon.
@MainActor
@Observable
final class IconSlot {
    var icon: NSImage?
    init(icon: NSImage?) { self.icon = icon }
}

/// Manages the application library: scanning, folders, icon caching, smart categories, and display ordering.
@MainActor
@Observable
class LibraryScanState {
    var isLoading = true
    var displayOrder: [Application] = []
    var appPathIndex: [String: Application] = [:]
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
    /// App paths currently flagged as recently updated (bundle mtime jumped since the previous
    /// scan). Driven by `RecentlyUpdatedTracker`; read by `AppIconView` to show a sparkles
    /// badge. `@Observable` propagates changes to the UI without manual `dataVersion` bumps.
    var recentlyUpdatedPaths: Set<String> = [] {
        didSet { dataVersion += 1 }
    }
    /// Filesystem paths of currently-running app bundles. Driven by `RunningAppTracker`
    /// (NSWorkspace launch/terminate notifications); read by `AppIconView` to show a running
    /// dot. `@Observable` propagates changes to the UI. Folder entries (synthetic) are never
    /// added here — they aren't launchable processes.
    ///
    /// Deliberately does **not** bump `dataVersion`. That counter invalidates
    /// `cachedDisplayedApps`, and no display decision reads this set — which apps are shown, in
    /// what order, and under which category are all independent of whether an app is running.
    /// The badge is read straight from this property in `AppIconView`, so `@Observable` already
    /// re-renders the affected cells. Bumping here would recompute the whole grid (filter +
    /// category + sort over every app) every time *any* app on the system launches or quits.
    var runningAppPaths: Set<String> = []
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
    /// Per-path icon holders read by `AppIconView`; see `IconSlot`. One per indexed app, kept in
    /// step by `rebuildAppPathIndex`; folder tiles get theirs on first request. Ignored by
    /// Observation itself — the slots are the observable part, and handing one out must not
    /// count as a mutation.
    @ObservationIgnored private var iconSlots: [String: IconSlot] = [:]
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
        // Load the persisted mtime baseline and any surviving "recently updated" entries before
        // the first scan runs, so the first `detectUpdatedApps` call measures deltas against the
        // pre-relaunch baseline rather than treating every app as freshly updated.
        RecentlyUpdatedTracker.shared.loadFromDefaults()
        recentlyUpdatedPaths = Set(RecentlyUpdatedTracker.shared.recentlyUpdated.keys)
    }

    /// Re-reads the persisted library state into this live object, then rebuilds the derived
    /// views that depend on it.
    ///
    /// Used after a backup restore. `BackupManager.apply` writes to `PreferencesStore` and
    /// `FolderStore`, neither of which feeds back into this object — `folders`' observer pushes
    /// *to* `FolderStore`, not from it — so the restored library sat on disk while the grid went
    /// on showing the pre-restore folders, ordering and hidden apps until the next launch.
    ///
    /// Does not rescan: a restore changes how the apps on disk are organised, not which apps
    /// exist. `customDirectories` is the exception — its observer re-points the watcher and
    /// triggers a rescan on its own when the directory set actually changed.
    func reloadFromPersistence() {
        hiddenAppPaths = PreferencesStore.shared.loadHiddenApps() ?? []
        folders = PreferencesStore.shared.loadFolders() ?? []
        customOrder = PreferencesStore.shared.loadCustomOrder() ?? [:]
        currentFolderId = PreferencesStore.shared.loadCurrentFolderId()
        loadSortOption()
        loadCustomDirectories()

        cachedAppsInAnyFolder = nil
        cachedDisplayedApps = nil
        dataVersion += 1
        rebuildAppPathIndex()
        updateRecentApps()
        updateFilteredApps()
        // Folder icons are composited from member icons, and membership just changed wholesale.
        regenerateFolderIcons(changedAppPaths: [])
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
        let allDirs = currentScanDirectories
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
        updateRecentlyUpdatedBadges()
    }

    private func loadHiddenApps() {
        if let paths = PreferencesStore.shared.loadHiddenApps() { hiddenAppPaths = paths }
    }
    private func loadCustomDirectories() {
        customDirectoryBookmarks = PreferencesStore.shared.loadCustomDirectoryBookmarks() ?? [:]
        if let dirs = PreferencesStore.shared.loadCustomDirectories() {
            // `customDirectories`'s own `didSet` already computes `allScanDirectories` as
            // `defaultScanDirectories + validated` — assigning it again here with the raw,
            // unvalidated `dirs` overwrote that with whatever was persisted, unchecked. A crafted
            // backup archive (or a directory that became invalid since it was saved, e.g. turned
            // into a symlink) would reach `DirectoryWatcher` and every scan with no validation at
            // all, even though `currentScanDirectories` re-validates on every read elsewhere.
            customDirectories = dirs
            resolveCustomDirectoryAccess(for: dirs)
        } else {
            allScanDirectories = Self.defaultScanDirectories
        }
    }
    /// The directories to scan *right now*, with the custom entries re-validated against the
    /// filesystem as it currently is.
    ///
    /// `allScanDirectories` holds the configured set, validated when it was last assigned — on
    /// add, on remove, and at launch. Scans run every few minutes and on every filesystem event,
    /// so between assignments a validated directory could be replaced with a symlink and every
    /// subsequent scan would follow it. Re-filtering here closes that window.
    ///
    /// The default directories are never re-validated, deliberately. They are the OS-owned
    /// install locations, and a check that somehow rejected one would silently empty the
    /// launcher — a far worse outcome than the narrow case this guards against.
    var currentScanDirectories: [String] {
        Self.defaultScanDirectories + customDirectories.filter { ApplicationScanner.isValidCustomDirectory($0) }
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
        rescheduleRefreshTimer()
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCachedIcons() }
        }
    }

    /// (Re)builds the periodic scan timer at the currently configured interval.
    ///
    /// Separate from the six-hourly icon-cache timer so changing the scan interval does not also
    /// restart that one. Called on initial load and again whenever the user changes the interval
    /// in Settings — the timer was previously built once and never rebuilt, so a changed interval
    /// was persisted and then ignored until the next launch.
    func rescheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: settings?.refreshInterval ?? ScanMetrics.refreshIntervalDefault, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isScanning else { return }
                await self.refreshDisplayOrder()
            }
        }
    }

    /// The interval the live scan timer is currently firing at, or nil when it is not scheduled.
    /// Exposed so a test can assert the timer really was rebuilt rather than just the value stored.
    var activeRefreshTimerInterval: TimeInterval? { refreshTimer?.timeInterval }

    /// When the six-hourly icon-cache timer next fires. Exposed so a test can assert that
    /// rescheduling the scan timer leaves this one alone — they used to be rebuilt together, so
    /// every interval change pushed the cache refresh out by another six hours.
    var activeCacheRefreshTimerFireDate: Date? { cacheRefreshTimer?.fireDate }

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
        // Flush any pending badge state so a quit right after a detected update doesn't lose it.
        RecentlyUpdatedTracker.shared.persist()
        RunningAppTracker.shared.stop()
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
        // The icons now being discarded were rendered under the *previous* appearance, whose
        // memory-cache entries nothing will serve again until the theme toggles back. Evict
        // them rather than leaving their bitmaps resident alongside the new variants (the
        // on-disk copies stay, so toggling back re-reads instead of re-rasterizing).
        let current = IconAppearance.current
        IconCacheManager.shared.evictMemoryVariants(
            for: displayOrder.map(\.path),
            appearance: current == .dark ? .light : .dark
        )
        rebuildAppPathIndex()
        dataVersion += 1

        // Evict folder icons so they regenerate with the new app icons.
        regenerateFolderIcons(changedAppPaths: [])

        cachedDisplayedApps = nil

        // Re-load and decode all icons under the new appearance.
        Task { @MainActor in
            await self.loadMissingIcons()
        }
    }

    /// The apps to decode icons for first, ahead of the rest of `displayOrder`.
    ///
    /// `displayOrder`'s own prefix is the raw scan order, which includes every app tucked away
    /// inside a folder — invisible until that folder is opened. On a library with folders, those
    /// hidden members can fill most of the priority batch, pushing the loose apps actually on
    /// screen into a later, sequentially-awaited chunk: blank icons on first launch until
    /// something (e.g. opening and leaving a folder) forces enough of the background loop to
    /// catch up. Prioritize by what `getDisplayedApps()` would put on the root page right now
    /// instead, topping up with raw scan order if that page has fewer apps than the batch size.
    func priorityIconLoadOrder() -> [Application] {
        let rootApps = getDisplayedApps(searchTerm: "", showFoldersFirst: settings?.showFoldersFirst ?? false,
                                        customOrder: customOrder, sortOption: sortOption,
                                        selectedCategory: .all, columnCount: settings?.columnCount ?? 4)
        let visiblePaths = Set(rootApps.prefix(ScanMetrics.priorityIconLoadCount).map(\.path))
        var priorityApps = displayOrder.filter { visiblePaths.contains($0.path) }
        if priorityApps.count < ScanMetrics.priorityIconLoadCount {
            let claimed = Set(priorityApps.map(\.path))
            priorityApps.append(contentsOf: displayOrder.lazy
                .filter { !claimed.contains($0.path) }
                .prefix(ScanMetrics.priorityIconLoadCount - priorityApps.count))
        }
        return priorityApps
    }

    func loadMissingIcons() async {
        let priorityApps = priorityIconLoadOrder()
        let priorityIcons = await IconService.shared.loadMissingIcons(for: priorityApps)
        if !priorityIcons.isEmpty { applyLoadedIcons(priorityIcons) }
        let prioritizedPaths = Set(priorityApps.map(\.path))
        let remainingApps = displayOrder.filter { !prioritizedPaths.contains($0.path) }
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

    /// Lands a batch of decoded icons without disturbing anything else.
    ///
    /// Only icons changed, so only icons are touched: the index entries for the batch are patched
    /// rather than the index rebuilt, each affected cell is signalled through its own `IconSlot`,
    /// and a warm `getDisplayedApps` result is patched in place instead of being thrown away.
    /// `dataVersion` deliberately does not move — which apps are shown, and in what order, is
    /// independent of their icons, and bumping it recomputed the whole display (filter, folder
    /// composites, sort) once per batch.
    private func applyLoadedIcons(_ loadedIcons: [(String, NSImage)]) {
        displayOrder = IconService.shared.updateIconsInPlace(for: displayOrder, with: loadedIcons)
        // Duplicate paths carry the same decoded icon, so either wins.
        let iconsByPath = Dictionary(loadedIcons, uniquingKeysWith: { first, _ in first })
        var index = appPathIndex
        for (path, icon) in iconsByPath where index[path] != nil {
            index[path]?.icon = icon
            publishIcon(icon, for: path)
        }
        appPathIndex = index
        let folderIcons = regenerateFolderIcons(changedAppPaths: Set(iconsByPath.keys))
        patchCachedDisplayedIcons(appIcons: iconsByPath, folderIcons: folderIcons)
    }

    /// Regenerates folder composites and pushes each to its tile's `IconSlot`. Every composite
    /// regeneration goes through here, so a folder tile's slot never lags the composite cache.
    @discardableResult
    private func regenerateFolderIcons(changedAppPaths: Set<String>) -> [String: NSImage] {
        let folderIcons = IconService.shared.refreshFolderIcons(
            folders: folders, appPathIndex: appPathIndex, changedAppPaths: changedAppPaths)
        for (folderId, icon) in folderIcons { publishIcon(icon, for: folderId) }
        return folderIcons
    }

    /// Carries freshly-loaded icons into a warm `getDisplayedApps` result, so a batch of icons
    /// does not cost a full display recompute. Folder tiles are matched by folder id, real apps
    /// by path.
    private func patchCachedDisplayedIcons(appIcons: [String: NSImage], folderIcons: [String: NSImage]) {
        guard var cached = cachedDisplayedApps else { return }
        var patched = false
        for i in cached.apps.indices {
            let app = cached.apps[i]
            let icon = app.isFolder ? app.folderId.flatMap { folderIcons[$0] } : appIcons[app.path]
            guard let icon else { continue }
            cached.apps[i].icon = icon
            patched = true
        }
        if patched { cachedDisplayedApps = cached }
    }

    /// The observable icon holder for `path`. A path absent from `appPathIndex` (a folder tile,
    /// or an app not scanned yet) gets an empty one, and `AppIconView` falls back to its own
    /// `app.icon`. Never reads an observed property, so calling this from a view body adds no
    /// dependency beyond the slot itself.
    func iconSlot(for path: String) -> IconSlot {
        if let slot = iconSlots[path] { return slot }
        let slot = IconSlot(icon: nil)
        iconSlots[path] = slot
        return slot
    }

    /// Pushes `icon` to the cell showing `path`, if any cell has asked for it. Writes only on an
    /// actual change so an unchanged icon never invalidates its cell.
    private func publishIcon(_ icon: NSImage?, for path: String) {
        guard let slot = iconSlots[path], slot.icon !== icon else { return }
        slot.icon = icon
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
                // Read the bundle's mtime from disk rather than from the in-memory record. The
                // record is written *when an icon is cached*, so comparing it against the .meta
                // file — which stores that same value — compared a number with itself and found
                // nothing stale, ever. This is the comparison the job exists to make, and it is
                // on a background thread precisely so the syscalls are affordable.
                guard let currentMtime = IconCacheManager.shared.currentBundleModificationTime(for: appPath) else {
                    continue // Bundle vanished between the scan and now; pruning will collect it.
                }
                let cachedSec = Int(cachedMtime.timeIntervalSince1970)
                let currentSec = Int(currentMtime.timeIntervalSince1970)
                if cachedSec != currentSec { stale.append(app) }
            }
            return stale
        }.value

        guard !staleApps.isEmpty else { return }
        let refreshedIcons = await IconService.shared.loadMissingIcons(for: staleApps, force: true)
        if !refreshedIcons.isEmpty { applyLoadedIcons(refreshedIcons) }
    }

    private func rebuildAppPathIndex() {
        var index: [String: Application] = [:]
        index.reserveCapacity(displayOrder.count)
        for app in displayOrder { index[app.path] = app }
        appPathIndex = index
        // Keep every indexed path's slot in step with the rebuilt index. Paths no longer indexed
        // are left alone: folder tiles' slots are fed by `publishIcon` from the folder
        // composites, not from here.
        for (path, app) in index {
            if let slot = iconSlots[path] {
                if slot.icon !== app.icon { slot.icon = app.icon }
            } else {
                iconSlots[path] = IconSlot(icon: app.icon)
            }
        }
    }

    /// Runs recently-updated detection against the current `displayOrder` and pushes the
    /// resulting path set into `recentlyUpdatedPaths` so `AppIconView` can badge apps.
    /// Called after each scan completes (both initial load and refresh). The mtime reads
    /// are batched here rather than in the scanner so the scanner stays pure of stateful
    /// cross-scan tracking — it returns apps with their current mtime, and this method
    /// compares that against the persisted baseline.
    private func updateRecentlyUpdatedBadges() {
        var currentMtimes: [String: Date] = [:]
        for app in displayOrder where !app.isFolder {
            currentMtimes[app.path] = app.installationDate
        }
        RecentlyUpdatedTracker.shared.detectUpdatedApps(currentMtimesByPath: currentMtimes)
        let updated = Set(RecentlyUpdatedTracker.shared.recentlyUpdated.keys)
        if updated != recentlyUpdatedPaths {
            recentlyUpdatedPaths = updated
        }
    }

    func sortedApplications(_ apps: [Application]) -> [Application] {
        ApplicationSorter.sort(apps, by: sortOption, customOrder: customOrder)
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
        let allDirs = currentScanDirectories
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            if let mtime = try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date { currentMtimes[dir] = mtime }
        }
        if !reason.bypassesStalenessCheck, let cache = scanCache {
            let hasChanged = allDirs.contains { currentMtimes[$0] != cache.dirMtimes[$0] }
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < (settings?.refreshInterval ?? ScanMetrics.refreshIntervalDefault) * 2 { return }
        }
        let result = await Task.detached(priority: .utility) {
            ApplicationScanner.shared.scanDirectories(directories: allDirs)
        }.value
        scanCache = ScanCache(dirMtimes: currentMtimes, timestamp: Date())

        let freshApps: [Application]
        if reason.rebuildsIcons {
            IconCacheManager.shared.clearAll()
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
        self.updateRecentApps()
        updateRecentlyUpdatedBadges()
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
    /// Records a new drag order for the apps in `apps`, and only those apps.
    ///
    /// `apps` is deliberately *not* assumed to be the full catalog — unlike `setApplications`,
    /// which this otherwise resembles. Every call site hands this the apps that were on screen
    /// at drop time: the root grid's loose apps + folder icons, or one open folder's contents,
    /// never the whole library. Writing that subset into `displayOrder` — which every other part
    /// of the app (`visibleApplications`, `appPathIndex`, icon-load priority, the Hidden Apps
    /// panel) treats as the complete scanned catalog — used to silently discard every app not on
    /// screen at drop time, until the next rescan rebuilt it. The fix is simply not touching
    /// `displayOrder` here: `getDisplayedApps` already recomputes from `customOrder` against the
    /// untouched full catalog, which is all a reorder needs.
    ///
    /// Builds the new order in a local copy and assigns it once. Writing `customOrder[path]`
    /// per app fired the property's observer — a `dataVersion` bump plus a full-dictionary encode
    /// and `UserDefaults` write — once per app on screen, stalling each drop for tens to hundreds
    /// of milliseconds on a large grid. The single assignment runs the observer exactly once,
    /// which covers both the `dataVersion` bump and the persist.
    func updateCustomOrder(from apps: [Application]) {
        var updated = customOrder
        for (index, app) in apps.enumerated() { updated[app.path] = index }
        customOrder = updated
        updateFilteredApps()
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

    /// The catalog with permanently-hidden and user-hidden apps filtered out.
    ///
    /// Deliberately **not** cached (a cache used to sit here): the work is one linear pass over
    /// `displayOrder` with O(1) set lookups, and it only runs on a `getDisplayedApps` cache miss
    /// or a handful of model mutations — never per icon. The cache it replaced retained a second
    /// full-array copy of the library (each entry carrying its `NSImage`) purely to skip that
    /// pass, which is a poor trade for the memory it held. Correctness is keyed on `dataVersion`,
    /// which `hiddenAppPaths` and `showHiddenApps` (via `AppModel`) both bump, so nothing needs
    /// the extra invalidation the cache demanded either.
    var visibleApplications: [Application] {
        displayOrder.filter {
            guard !Self.permanentlyHiddenAppPaths.contains($0.path) else { return false }
            if settings?.showHiddenApps ?? false { return true }
            return !hiddenAppPaths.contains($0.path)
        }
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

    func appsInFolder(for folderId: String) -> [Application] {
        let effectiveHiddenPaths: Set<String> = (settings?.showHiddenApps ?? false) ? [] : hiddenAppPaths
        let apps = FolderStore.shared.appsInFolder(for: folderId, appPathIndex: appPathIndex, hiddenAppPaths: effectiveHiddenPaths, customOrder: customOrder, sortOption: sortOption)
        return apps.filter { !Self.permanentlyHiddenAppPaths.contains($0.path) }
    }
}
