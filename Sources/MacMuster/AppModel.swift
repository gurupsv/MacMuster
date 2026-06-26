import Foundation
import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
class AppModel {
    // MARK: - Constants
    var refreshInterval: TimeInterval = 300 {
        didSet {
            PreferencesStore.shared.saveRefreshInterval(refreshInterval)
            setupRefreshTimer()
        }
    }

    // MARK: - State
    var isLoading = true
    var displayOrder: [Application] = []
    private var appPathIndex: [String: Application] = [:] // Optimization P2: Path -> App lookup index
    // Icons loaded by path, read directly by AppIconView. Application.== only compares `id`
    // (the path), so reassigning displayOrder with just icons filled in looks "unchanged" to
    // @Observable and won't reliably wake up views that captured an `Application` value before
    // its icon loaded. Views read icons from here instead, so they react independently of
    // whether displayOrder's own change notification fires.
    var loadedIconsByPath: [String: NSImage] = [:]
    private var dataVersion: Int = 0 // Track changes to displayOrder for cache invalidation

    // Optimization P1: Scan caching to avoid redundant disk I/O every 5 minutes
    private struct ScanCache {
        let dirMtimes: [String: Date]
        let timestamp: Date
    }
    private var scanCache: ScanCache?
    var hiddenAppPaths: Set<String> = [] {
        didSet {
            dataVersion += 1
            PreferencesStore.shared.saveHiddenApps(hiddenAppPaths)
            updateFilteredApps()
        }
    }
    var customDirectories: [String] = [] {
        didSet {
            allScanDirectories = ApplicationScanner.defaultScanDirectories + customDirectories
            PreferencesStore.shared.saveCustomDirectories(customDirectories)
        }
    }
    var allScanDirectories: [String] = [] {
        didSet {
            dataVersion += 1
        }
    }
    // F-4: security-scoped bookmarks for custom directories, keyed by path, plus the resolved
    // URLs currently holding active access. The app is unsandboxed today, so scanning works off
    // `customDirectories` paths alone regardless of these — they exist so a custom directory's
    // access survives relaunch if sandboxing is ever turned on, instead of silently breaking.
    private var customDirectoryBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURLs: [String: URL] = [:]

    // MARK: - Folders
    var folders: [AppFolder] = [] {
        didSet { FolderStore.shared.folders = folders }
    }
    var currentFolderId: String? = nil {
        didSet {
            dataVersion += 1
            PreferencesStore.shared.saveCurrentFolderId(currentFolderId)
        }
    }

    // MARK: - Recent Apps Tracking
    var _recentApps: [Application] = []

    // MARK: - UI & Navigation State
    var selectedAppIndex: Int = -1
    var scrollTargetIndex: Int?
    var scrollTargetAnchor: ScrollAnchor?
    var searchTerm: String = "" {
        didSet {
            guard searchTerm != oldValue else { return }
            searchDebounceTask?.cancel()
            if searchTerm.isEmpty {
                // Clearing the search should feel instant rather than waiting out the debounce.
                dataVersion += 1
            } else {
                searchDebounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: kSearchDebounceNanoseconds)
                    guard !Task.isCancelled, let self else { return }
                    self.dataVersion += 1
                }
            }
        }
    }
    private var searchDebounceTask: Task<Void, Never>?
    var fontFamily: String = "SF Pro" {
        didSet {
            PreferencesStore.shared.saveFontFamily(fontFamily)
        }
    }
    var fontSize: Double = 14.0 {
        didSet {
            PreferencesStore.shared.saveFontSize(fontSize)
        }
    }
    var fontWeight: String = "normal" {
        didSet {
            PreferencesStore.shared.saveFontWeight(fontWeight)
        }
    }
    var columnCount: Int = 4 {
        didSet {
            PreferencesStore.shared.saveColumnCount(columnCount)
        }
    }
    var iconSize: IconSize = .small {
        didSet {
            PreferencesStore.shared.saveIconSize(iconSize.rawValue)
        }
    }
    var selectedCategory: AppCategory = .all {
        didSet {
            dataVersion += 1
            selectedAppIndex = -1
        }
    }
    var categoryCounts: [AppCategory: Int] = [:]
    var _mostUsedApps: [Application] = []
    var customOrder: [String: Int] = [:] {
        didSet {
            dataVersion += 1
            PreferencesStore.shared.saveCustomOrder(customOrder)
        }
    }
    var sortOption: ApplicationSorter.SortOption = .name {
        didSet {
            dataVersion += 1
            PreferencesStore.shared.saveSortOption(sortOption.rawValue)
        }
    }

    // MARK: - Glow Effect Settings (for overlay window edges)
    var glowEnabled: Bool = true {
        didSet {
            PreferencesStore.shared.saveGlowEnabled(glowEnabled)
        }
    }
    var glowColor: Color = .white {
        didSet {
            PreferencesStore.shared.saveGlowColor(getHexColorValue())
        }
    }
    var glowIntensity: Double = 0.3 {
        didSet {
            // Clamp intensity between 0 and 1
            if glowIntensity < 0 { glowIntensity = 0 }
            if glowIntensity > 1 { glowIntensity = 1 }
            PreferencesStore.shared.saveGlowIntensity(glowIntensity)
        }
    }
    var glowWidth: Double = 40.0 {
        didSet {
            // Clamp width between 5 and 40
            if glowWidth < 5 { glowWidth = 5 }
            if glowWidth > 40 { glowWidth = 40 }
            PreferencesStore.shared.saveGlowWidth(glowWidth)
        }
    }

    // MARK: - Settings
    var showFoldersFirst: Bool = false {
        didSet {
            dataVersion += 1
            PreferencesStore.shared.saveShowFoldersFirst(showFoldersFirst)
        }
    }
    var hasShownLauncher: Bool = false {
        didSet {
            PreferencesStore.shared.saveHasShownLauncher(hasShownLauncher)
        }
    }
    var showRecentApps: Bool = true {
        didSet {
            RecentAppsTracker.shared.isEnabled = showRecentApps
            PreferencesStore.shared.saveRecentAppsEnabled(showRecentApps)
        }
    }
    var pressFeedbackEnabled: Bool = true {
        didSet {
            PreferencesStore.shared.savePressFeedbackEnabled(pressFeedbackEnabled)
        }
    }

    // MARK: - Overlay Opacity Settings
    var overlayOpacity: Double = kOverlayOpacityDefault {
        didSet {
            if overlayOpacity < kOverlayOpacityMin { overlayOpacity = kOverlayOpacityMin }
            if overlayOpacity > kOverlayOpacityMax { overlayOpacity = kOverlayOpacityMax }
            PreferencesStore.shared.saveOverlayOpacity(overlayOpacity)
        }
    }

    // MARK: - Accessibility Settings
    var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Timer & Observers
    private var refreshTimer: Timer?

    // MARK: - Initialization
    init() {
        loadHiddenApps()
        loadFolders()
        loadPersistedPreferences()
        loadRecentLaunchTimes()
        showRecentApps = PreferencesStore.shared.loadRecentAppsEnabled()
        pressFeedbackEnabled = PreferencesStore.shared.loadPressFeedbackEnabled()
        loadCustomDirectories()
        loadFontFamily()
        if let opacityRaw = PreferencesStore.shared.loadOverlayOpacity() {
            overlayOpacity = max(kOverlayOpacityMin, min(kOverlayOpacityMax, opacityRaw))
        }
    }

    /// Start loading applications asynchronously. Called from the view's `.task` modifier
    /// so it's tied to the SwiftUI lifecycle and ensures proper observation setup.
    @MainActor
    func startLoading() async {
        guard isLoading else { return }

        let allDirs = allScanDirectories

        let result = ApplicationScanner.shared.scanDirectories(directories: allDirs)

        self.displayOrder = self.sortedApplications(result.apps)

        rebuildAppPathIndex()

        dataVersion += 1
        self.updateFilteredApps()
        self.setupRefreshTimer()
        // Show the grid now (with placeholder icons) instead of blocking on every icon decode —
        // loadMissingIcons() below fills them in afterward, prioritizing the first screenful.
        isLoading = false
        await self.loadMissingIcons()
        // Refresh recent apps so _recentApps gets icon-populated Application structs
        self.updateRecentApps()
    }

    // MARK: - Persistence & Setup
    private func loadHiddenApps() {
        if let paths = PreferencesStore.shared.loadHiddenApps() {
            hiddenAppPaths = paths
        }
    }
    
    private func loadFolders() {
        if let savedFolders = PreferencesStore.shared.loadFolders() {
            folders = savedFolders
        }
    }
    
    private func loadPersistedPreferences() {
        if let cols = PreferencesStore.shared.loadColumnCount() {
            columnCount = max(1, cols)
        }
        if let folderId = PreferencesStore.shared.loadCurrentFolderId() {
            currentFolderId = folderId
        }
        if let order = PreferencesStore.shared.loadCustomOrder() {
            customOrder = order
        }
        if let sortRaw = PreferencesStore.shared.loadSortOption() {
            sortOption = ApplicationSorter.SortOption(rawValue: sortRaw) ?? .name
        }
        if let iconRaw = PreferencesStore.shared.loadIconSize() {
            iconSize = IconSize(rawValue: iconRaw) ?? .small
        }
        if let interval = PreferencesStore.shared.loadRefreshInterval() {
            refreshInterval = interval
        }
        // Load showFoldersFirst setting
        showFoldersFirst = PreferencesStore.shared.loadShowFoldersFirst()
        // Load first-launch flag
        hasShownLauncher = PreferencesStore.shared.loadHasShownLauncher()
        
        // Load recent apps setting
        showRecentApps = PreferencesStore.shared.loadRecentAppsEnabled()
        
        // Load glow effect settings
        glowEnabled = PreferencesStore.shared.loadGlowEnabled()
        if let glowColorHex = PreferencesStore.shared.loadGlowColor() {
            glowColor = parseColor(from: glowColorHex)
        }
        if let glowIntensityRaw = PreferencesStore.shared.loadGlowIntensity() {
            glowIntensity = max(0, min(1, glowIntensityRaw))
        }
        if let glowWidthRaw = PreferencesStore.shared.loadGlowWidth() {
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
        customDirectoryBookmarks = PreferencesStore.shared.loadCustomDirectoryBookmarks() ?? [:]
        if let dirs = PreferencesStore.shared.loadCustomDirectories() {
            let validDirs = dirs.filter { ApplicationScanner.isValidCustomDirectory($0) }
            customDirectories = validDirs
            allScanDirectories = Self.defaultScanDirectories + validDirs
            resolveCustomDirectoryAccess(for: validDirs)
        } else {
            allScanDirectories = Self.defaultScanDirectories
        }
    }

    /// F-4: resolve each custom directory's security-scoped bookmark (if one was recorded) and
    /// start access. Best-effort — a missing or stale bookmark just falls back to today's existing
    /// behavior of scanning the plain path directly, which is all that's needed while unsandboxed.
    private func resolveCustomDirectoryAccess(for paths: [String]) {
        for path in paths {
            guard let bookmarkData = customDirectoryBookmarks[path] else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                activeSecurityScopedURLs[path] = url
            }
        }
    }

    private func loadFontFamily() {
        if let font = PreferencesStore.shared.loadFontFamily() {
            fontFamily = font
        }
        if let size = PreferencesStore.shared.loadFontSize() {
            let validSizes: [Double] = [12.0, 14.0, 16.0, 18.0]
            fontSize = validSizes.contains(size) ? size : 14.0
        }
        if let weight = PreferencesStore.shared.loadFontWeight() {
            fontWeight = weight
        }
    }

    // MARK: - Folder Methods

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
        if folderId == currentFolderId && currentFolder?.appPaths.isEmpty ?? true {
            currentFolderId = nil
        }
    }
    
    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) {
        FolderStore.shared.moveAppInFolder(appPath, from: folderId, to: toFolderId)
        folders = FolderStore.shared.folders
    }

    func openFolder(_ folderId: String) {
        currentFolderId = folderId
        PreferencesStore.shared.saveCurrentFolderId(folderId)
        // Critical fix Issue 2: rebuild appPathIndex on folder state changes
        rebuildAppPathIndex()
        // Critical fix Issue 1: explicit cache invalidation on folder state changes
        cachedDisplayedApps = nil
    }
    
    func closeFolder() {
        currentFolderId = nil
        PreferencesStore.shared.saveCurrentFolderId(nil)
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
        let containedApps = folder.appPaths.compactMap { appPathIndex[$0] }
        var app = FolderStore.shared.getFolderApplication(folder, containedApps: containedApps)
        app.icon = IconService.shared.generateFolderIcon(containedApps, for: folder.id)
        return app
    }

    static var defaultScanDirectories: [String] { ApplicationScanner.defaultScanDirectories }

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

    /// Loads icons in two passes: the first screenful's worth of apps first (so the grid looks
    /// fully populated almost immediately), then the remainder in the background.
    private func loadMissingIcons() async {
        let priorityApps = Array(displayOrder.prefix(kPriorityIconLoadCount))
        let priorityIcons = await IconService.shared.loadMissingIcons(for: priorityApps)
        if !priorityIcons.isEmpty {
            applyLoadedIcons(priorityIcons)
        }

        let remainingApps = Array(displayOrder.dropFirst(kPriorityIconLoadCount))
        guard !remainingApps.isEmpty else { return }
        let remainingIcons = await IconService.shared.loadMissingIcons(for: remainingApps)
        if !remainingIcons.isEmpty {
            applyLoadedIcons(remainingIcons)
        }
    }

    private func applyLoadedIcons(_ loadedIcons: [(String, NSImage)]) {
        // Mutate displayOrder in-place (icon is var) — no full array rebuild
        displayOrder = IconService.shared.updateIconsInPlace(for: displayOrder, with: loadedIcons)
        for (path, icon) in loadedIcons {
            loadedIconsByPath[path] = icon
        }

        rebuildAppPathIndex()
        dataVersion += 1
        cachedVisibleApps = nil
        cachedDisplayedApps = nil
        // Refresh folder icons now that app icons are available
        IconService.shared.refreshFolderIcons(folders: folders, appPathIndex: appPathIndex)
    }

    private func rebuildAppPathIndex() {
        appPathIndex.removeAll(keepingCapacity: true)
        for app in displayOrder {
            appPathIndex[app.path] = app
        }
    }

    // internal (not private) so AppModelTests can trigger a recompute directly via @testable import.
    func updateFilteredApps() {
        var counts: [AppCategory: Int] = [:]
        let visible = visibleApplications
        for app in visible {
            let cat = getCategory(for: app)
            counts[cat, default: 0] += 1
        }
        // .utilities is intentionally folded into .user by getCategory (see AppModelTests) — always 0.
        counts[.utilities] = 0
        counts[.all] = visible.count
        // Smart categories are independent memberships, counted against the visible set.
        let visiblePaths = Set(visible.map(\.path))
        counts[.mostUsed] = _mostUsedApps.filter { visiblePaths.contains($0.path) }.count
        counts[.recentlyLaunched] = _recentApps.filter { visiblePaths.contains($0.path) }.count
        counts[.newlyInstalled] = visible.filter { isNewlyInstalled($0) }.count
        categoryCounts = counts
    }

    // MARK: - Sorting
    func sortedApplications(_ apps: [Application]) -> [Application] {
        ApplicationSorter.sort(apps, by: sortOption)
    }

    // MARK: - Refresh & Updates
    // Changed from private to internal so AppDelegate/Views can trigger manual refreshes if needed
    func refreshDisplayOrder() async {
        let allDirs = allScanDirectories
        
        // P6: Stat every directory exactly once; reuse the result for both the staleness check
        // and building the new cache entry (previously the code did two full passes).
        var currentMtimes: [String: Date] = [:]
        for dir in allDirs {
            if let mtime = try? FileManager.default.attributesOfItem(atPath: dir)[.modificationDate] as? Date {
                currentMtimes[dir] = mtime
            }
            // If stat fails, omit the entry — the cache comparison below will treat it as changed,
            // which is the safe/correct behaviour (directory may have been removed).
        }
        
        if let cache = scanCache {
            let hasChanged = allDirs.contains { currentMtimes[$0] != cache.dirMtimes[$0] }
            if !hasChanged && Date().timeIntervalSince(cache.timestamp) < refreshInterval * 2 {
                return
            }
        }
        
        let result = ApplicationScanner.shared.scanDirectories(directories: allDirs)

        scanCache = ScanCache(dirMtimes: currentMtimes, timestamp: Date())
        
        let preservedIcons = Dictionary(uniqueKeysWithValues: displayOrder.compactMap { app -> (String, NSImage)? in
            guard let icon = app.icon else { return nil }
            return (app.path, icon)
        })
        
        let appsWithPreservedIcons = IconService.shared.applicationsPreservingLoadedIcons(from: result.apps, loadedIconsByPath: preservedIcons)
        self.displayOrder = self.sortedApplications(appsWithPreservedIcons)
        
        // Update the path index for O(1) lookups in folders and other methods
        rebuildAppPathIndex()
        
        dataVersion += 1
        self.updateFilteredApps()
        await self.loadMissingIcons()
        // Prune icons for apps no longer present (uninstalled since last scan).
        let currentPaths = Set(displayOrder.map(\.path))
        loadedIconsByPath = loadedIconsByPath.filter { currentPaths.contains($0.key) }
        // Refresh recent apps so _recentApps gets icon-populated Application structs
        self.updateRecentApps()
    }

    // MARK: - Recent Apps Tracking
    func recordAppLaunch(at path: String) {
        RecentAppsTracker.shared.recordAppLaunch(at: path)
        updateRecentApps()
        dataVersion += 1
        updateFilteredApps()
    }
    
    private func loadRecentLaunchTimes() {
        RecentAppsTracker.shared.loadRecentLaunchTimes()
        updateRecentApps()
    }

    func isRecentApp(_ path: String) -> Bool {
        return _recentApps.contains { $0.path == path }
    }

    func getRecentApps() -> [Application] {
        return _recentApps
    }

    private func updateRecentApps() {
        let recentPaths = RecentAppsTracker.shared.getRecentPaths()
        _recentApps = recentPaths.compactMap { appPathIndex[$0] }
        updateMostUsedApps()
    }

    private func updateMostUsedApps() {
        let mostUsedPaths = RecentAppsTracker.shared.getMostUsedPaths(limit: kMaxRecentApps)
        _mostUsedApps = mostUsedPaths.compactMap { appPathIndex[$0] }
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
        if app.isFolder, let folderId = app.folderId {
            openFolder(folderId)
            return true
        }
        ApplicationService.shared.launchApplication(at: app.path, appModel: self)
        return true
    }

    func clearSearchState() {
        searchTerm = ""
        selectedAppIndex = -1
    }

    // MARK: - App Management
    // Quick Win 6: Consolidate toggleHiddenApp - single source of truth
    func toggleHiddenApp(_ path: String) {
        if hiddenAppPaths.contains(path) {
            hiddenAppPaths.remove(path)
        } else {
            hiddenAppPaths.insert(path)
        }
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

    // MARK: - Smart Category Membership
    // These are independent of getCategory(for:) since an app can belong to a smart
    // category (e.g. Most Used) in addition to its base System/User category.

    func isMostUsed(_ app: Application) -> Bool {
        _mostUsedApps.contains { $0.path == app.path }
    }

    func isRecentlyLaunched(_ app: Application) -> Bool {
        _recentApps.contains { $0.path == app.path }
    }

    func isNewlyInstalled(_ app: Application) -> Bool {
        Date().timeIntervalSince(app.installationDate) < kNewlyInstalledWindowSeconds
    }

    /// Whether `app` matches the currently selected category tab (base or smart).
    func matchesSelectedCategory(_ app: Application) -> Bool {
        switch selectedCategory {
        case .all:
            return true
        case .system, .utilities, .user:
            return getCategory(for: app) == selectedCategory
        case .mostUsed:
            return isMostUsed(app)
        case .recentlyLaunched:
            return isRecentlyLaunched(app)
        case .newlyInstalled:
            return isNewlyInstalled(app)
        }
    }

    func removeCustomDirectory(_ path: String) {
        customDirectories.removeAll { $0 == path }
        if let url = activeSecurityScopedURLs.removeValue(forKey: path) {
            url.stopAccessingSecurityScopedResource()
        }
        if customDirectoryBookmarks.removeValue(forKey: path) != nil {
            PreferencesStore.shared.saveCustomDirectoryBookmarks(customDirectoryBookmarks)
        }
        Task { await refreshDisplayOrder() }
    }

    /// `bookmarkData` is an F-4 security-scoped bookmark for `path`, created by the caller from the
    /// `URL` the file picker returned (a plain path string can't be turned into a bookmark after the
    /// fact). Optional and best-effort — if bookmark creation failed or wasn't provided, the
    /// directory is still added and scanned by its plain path exactly as before.
    func addCustomDirectory(_ path: String, bookmarkData: Data? = nil) {
        guard ApplicationScanner.isValidCustomDirectory(path), !customDirectories.contains(path) else { return }
        customDirectories.append(path)
        if let bookmarkData {
            customDirectoryBookmarks[path] = bookmarkData
            PreferencesStore.shared.saveCustomDirectoryBookmarks(customDirectoryBookmarks)
        }
    }

    func setFontFamily(_ family: String) {
        fontFamily = family
    }

    func setFontWeight(_ weight: String) {
        fontWeight = weight
    }

    func setColumnCount(_ count: Int) {
        columnCount = count
    }

    func setSortOption(_ option: ApplicationSorter.SortOption) {
        sortOption = option
    }

    func setIconSize(_ size: IconSize) {
        iconSize = size
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
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
        PreferencesStore.shared.saveCustomOrder(customOrder)
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

    // Placeholder functions removed (Code Review Fix 1): These categories (mostUsed, recentlyLaunched, newlyInstalled)
    // are not yet implemented. The AppCategory enum retains these cases for future implementation.
    // When the logic is implemented, these functions should be restored with real sorting logic.

    private func getHexColorValue() -> String {
        let nsColor = NSColor(glowColor)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#ffffff" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }


    // MARK: - Computed Properties & Display Helpers

    var visibleApplications: [Application] {
        if let c = cachedVisibleApps, c.version == dataVersion { return c.apps }
        let apps = displayOrder.filter { !hiddenAppPaths.contains($0.path) }
        cachedVisibleApps = (dataVersion, apps)
        return apps
    }

    // P2: Cache visibleApplications — recomputed only when dataVersion changes
    private var cachedVisibleApps: (version: Int, apps: [Application])?
    
    private var cachedDisplayedApps: (version: Int, apps: [Application])?
    
    func getDisplayedApps() -> [Application] {
        if let cached = cachedDisplayedApps, cached.version == dataVersion {
            return cached.apps
        }

        let baseApps = getBaseAppsForCurrentContext()
        let filtered = applySearchFilter(to: baseApps)
        let result = applyOrdering(to: filtered)

        cachedDisplayedApps = (dataVersion, result)
        return result
    }

    /// Build the initial app list based on folder context (root vs inside folder) and category filter.
    private func getBaseAppsForCurrentContext() -> [Application] {
        // Collect all app paths that belong to user-created folders.
        let appsInAnyFolder: Set<String> = folders.reduce(into: Set()) { $0.formUnion($1.appPaths) }

        if let folderId = currentFolderId {
            // Inside a folder: show only apps from this folder (and its child folders)
            return getAllAppsIncludingChildFolders(for: folderId)
        }

        // At root level: loose apps (not in any folder) + folder icons
        var looseApps = visibleApplications.filter { !appsInAnyFolder.contains($0.path) }
        looseApps = looseApps.filter { matchesSelectedCategory($0) }

        let folderIcons: [Application] = folders.compactMap { folder in
            let hasVisible = folder.appPaths.contains { path in
                guard !hiddenAppPaths.contains(path), let app = appPathIndex[path] else { return false }
                return matchesSelectedCategory(app)
            }
            return hasVisible ? getFolderApplication(folder) : nil
        }

        return looseApps + folderIcons
    }

    /// Apply search filter to a list of apps. Logic differs based on folder context.
    private func applySearchFilter(to apps: [Application]) -> [Application] {
        guard !searchTerm.isEmpty else { return apps }
        let lower = searchTerm.lowercased()

        if currentFolderId == nil {
            // Root-level search: match against ALL visible apps (loose + inside folders), not just the current view.
            // This lets users find an app regardless of which folder it's in.
            return sortedApplications(visibleApplications.filter { $0.matchesSearch(lower) })
        }

        // Inside a folder: filter only the current folder's apps.
        let filtered = apps.filter { $0.matchesSearch(lower) }
        return sortedApplications(filtered)
    }

    /// Apply ordering (folder-first, custom, or default sort) to a list of apps.
    private func applyOrdering(to apps: [Application]) -> [Application] {
        guard !searchTerm.isEmpty else {
            // When search is active, search filter already sorted; don't re-sort.
            return applyNonSearchOrdering(to: apps)
        }
        return apps
    }

    /// Apply non-search ordering: folder-first grouping, custom order, or default sort.
    private func applyNonSearchOrdering(to apps: [Application]) -> [Application] {
        var ordered = apps
        var folderFirstApplied = false

        if showFoldersFirst && !ordered.isEmpty {
            let folderApps = ordered.filter { $0.isFolder }
            let nonFolderApps = ordered.filter { !$0.isFolder }
            if !folderApps.isEmpty && !nonFolderApps.isEmpty {
                ordered = folderApps + nonFolderApps
                folderFirstApplied = true
            }
        }

        if !customOrder.isEmpty {
            return ordered.sorted {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) {
                case (nil, nil): return false
                case (nil, _):   return false
                case (_, nil):   return true
                case (let av?, let bv?): return av < bv
                }
            }
        }

        if folderFirstApplied {
            return ordered
        }

        // Preserve recency ordering for recently launched apps category
        if selectedCategory == .recentlyLaunched {
            return ordered.sorted { 
                let a = RecentAppsTracker.shared.recentAppLaunchTimes[$0.path], b = RecentAppsTracker.shared.recentAppLaunchTimes[$1.path]
                switch (a, b) {
                case (nil, nil): return false
                case (nil, _):   return false
                case (_, nil):   return true
                case (let av?, let bv?): return av > bv
                }
            }
        }

        // Preserve most-used ordering for most used apps category
        if selectedCategory == .mostUsed {
            return ordered.sorted { 
                let a = RecentAppsTracker.shared.appLaunchCounts[$0.path], b = RecentAppsTracker.shared.appLaunchCounts[$1.path]
                switch (a, b) {
                case (nil, nil): return false
                case (nil, _):   return false
                case (_, nil):   return true
                case (let av?, let bv?): return av > bv
                }
            }
        }

        return sortedApplications(ordered)
    }
    
    // MARK: - Recursive Child Folder Search
    
    /// Get all apps from a folder and its child folders (recursively).
    /// A child folder is one that contains at least one app from the parent folder's appPaths.
    private func getAllAppsIncludingChildFolders(for folderId: String) -> [Application] {
        FolderStore.shared.getAllAppsIncludingChildFolders(
            for: folderId,
            appPathIndex: appPathIndex,
            hiddenAppPaths: hiddenAppPaths,
            customOrder: customOrder,
            sortOption: sortOption
        )
    }
}