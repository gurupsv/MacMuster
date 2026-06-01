import Foundation
import AppKit

// AppModel is @MainActor to ensure all @Published properties are accessed on main thread
@MainActor
class AppModel: ObservableObject {
    @Published var sortOption: ApplicationSorter.SortOption = .name
    @Published var customOrder: [String: Int] = [:]
    @Published var displayOrder: [Application] = []
    @Published var searchText: String = "" {
        didSet {
            updateFilteredApps()
        }
    }
    @Published var selectedCategory: AppCategory = .user {
        didSet {
            updateFilteredApps()
        }
    }
    @Published var refreshInterval: TimeInterval = 300 {
        didSet {
            saveRefreshInterval()
            if refreshTimer != nil {
                restartRefreshTimer()
            }
        }
    }
    
    // Font settings - configurable in Appearance
    @Published var fontFamily: String = "SF Pro Display"
    @Published var fontSize: Double = 18
    @Published var fontWeight: String = "normal"  // "normal" or "bold"
    
    // Layout settings - configurable in Appearance
    @Published var columnCount: Int = 8 {  // 4-10 columns
        didSet {
            saveColumnCount()
        }
    }
    @Published var iconSize: IconSize = .medium


    // Cached computed properties to avoid recomputation on every view update
    @Published private(set) var _filteredApplications: [Application] = []
    @Published private(set) var _recentApps: [Application] = []
    @Published private(set) var _visibleApplications: [Application] = []
    @Published private(set) var _displayedApplications: [Application] = []
    @Published private(set) var categoryCounts: [AppCategory: Int] = [:]
    
    // Cache for app icons using NSCache for automatic memory management
    private lazy var iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return cache
    }()
    
    // Cache for app metadata (modification date) to detect changes
    private var appMetadataCache: [String: Date] = [:]
    
    // Pre-computed lowercase names for efficient search
    private var lowercaseNameCache: [String: String] = [:]
    
    // Hidden apps - apps that the user wants to hide from the launcher
    @Published private var hiddenAppPaths: Set<String> = []
    
    // Recently launched apps (path -> last launch time)
    // Limited to 8 to fit in one row with the 8-column grid layout
    private var recentApps: [String: Date] = [:]
    private let maxRecentApps = 8
    
    // -1 means no selection (dot not shown); becomes 0 on first arrow key press
    @Published private(set) var selectedAppIndex: Int = -1
    
    // Persisted preferences
    private static let kSortOption = "preferredSortOption"
    private static let kCustomOrder = "customAppOrder"
    private static let kRefreshInterval = "refreshInterval"
    private static let kFontFamily = "fontFamily"
    private static let kFontSize = "fontSize"
    private static let kFontWeight = "fontWeight"
    private static let kColumnCount = "columnCount"
    private static let kIconSize = "iconSize"

    // Timer and observer management
    private var refreshTimer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var isRefreshingApplications = false
    private var iconLoadGeneration = 0
    
    // Dirty flags to avoid redundant computation
    private var filterDirty = true
    private var displayOrderVersion = 0  // Monotonically increasing version counter
    private var lastFilterVersion: Int = 0
    private var lastSortVersion = 0
    private var cachedSortedApps: [Application] = []
    
    /// Filtered view of displayOrder based on current search text (cached)
    var filteredApplications: [Application] {
        return _filteredApplications
    }
    
    /// Visible applications (hidden apps filtered out)
    var visibleApplications: [Application] {
        _visibleApplications
    }

    var displayedApplications: [Application] {
        _displayedApplications
    }
    
    @Published private(set) var isLoading: Bool = true
    
    init() {
        loadHiddenApps()
        loadPersistedPreferences()

        let hiddenPaths = hiddenAppPaths
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.scanApplications(hiddenPaths: hiddenPaths)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.appMetadataCache = result.metadata
                self.displayOrder = self.sortedApplications(result.apps)
                self.isLoading = false
                self.updateFilteredApps()
                // Don't rebuild recent apps yet — icons aren't loaded, so no visual benefit
                // Will rebuild after all icons load (line 687)
                self.setupRefreshTimer()
                // Start icon loading immediately; small batch size (12) keeps frame rates smooth
                self.loadMissingIcons()
            }
        }
    }
    
    // MARK: - Persisted Preferences
    
    private func loadPersistedPreferences() {
        // Load sort option
        if let sortOptionRaw = UserDefaults.standard.string(forKey: Self.kSortOption),
           let loadedOption = ApplicationSorter.SortOption(rawValue: sortOptionRaw) {
            self.sortOption = loadedOption
        }
        
        // Load custom order
        if let customOrderData = UserDefaults.standard.data(forKey: Self.kCustomOrder),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: customOrderData) {
            customOrder = decoded
        }
        
        let storedRefreshInterval = UserDefaults.standard.double(forKey: Self.kRefreshInterval)
        if storedRefreshInterval >= 30 {
            refreshInterval = storedRefreshInterval
        }
        
        // Load font settings
        if let storedFamily = UserDefaults.standard.string(forKey: Self.kFontFamily) {
            fontFamily = storedFamily
        }
        let storedSize = UserDefaults.standard.double(forKey: Self.kFontSize)
        if storedSize > 0 {
            fontSize = storedSize
        }
        if let storedWeight = UserDefaults.standard.string(forKey: Self.kFontWeight) {
            fontWeight = storedWeight
        }
        
        // Load layout settings
        let storedColumnCount = UserDefaults.standard.integer(forKey: Self.kColumnCount)
        if storedColumnCount >= 4 && storedColumnCount <= 10 {
            columnCount = storedColumnCount
        }
        if let storedIconSize = UserDefaults.standard.string(forKey: Self.kIconSize),
           let loadedIconSize = IconSize(rawValue: storedIconSize) {
            iconSize = loadedIconSize
        }

    }
    
    private func saveSortOption() {
        UserDefaults.standard.set(sortOption.rawValue, forKey: Self.kSortOption)
    }
    
    private func saveCustomOrder() {
        do {
            let encoded = try JSONEncoder().encode(customOrder)
            UserDefaults.standard.set(encoded, forKey: Self.kCustomOrder)
        } catch {
            #if DEBUG
            print("Failed to save custom order: \(error)")
            #endif
        }
    }
    
    private func saveRefreshInterval() {
        UserDefaults.standard.set(refreshInterval, forKey: Self.kRefreshInterval)
    }
    
    private func saveFontSettings() {
        UserDefaults.standard.set(fontFamily, forKey: Self.kFontFamily)
        UserDefaults.standard.set(fontSize, forKey: Self.kFontSize)
        UserDefaults.standard.set(fontWeight, forKey: Self.kFontWeight)
    }
    
    private func saveColumnCount() {
        UserDefaults.standard.set(columnCount, forKey: Self.kColumnCount)
    }
    
    private func saveIconSize() {
        UserDefaults.standard.set(iconSize.rawValue, forKey: Self.kIconSize)
    }

    
    func applyFontSettings() {
        objectWillChange.send()
    }
    
    // MARK: - Keyboard Navigation
    
    func selectApp(at index: Int) {
        let apps = displayedApplications
        guard index >= 0 && index < apps.count else { return }
        selectedAppIndex = index
    }
    
    func selectNextApp() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }
        // Initialize selection to first item on first navigation
        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else {
            selectedAppIndex = (selectedAppIndex + 1) % apps.count
        }
    }
    
    func selectPreviousApp() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }
        // Initialize selection to last item on first navigation
        if selectedAppIndex < 0 {
            selectedAppIndex = apps.count - 1
        } else {
            selectedAppIndex = (selectedAppIndex - 1 + apps.count) % apps.count
        }
    }

    func selectAppUp() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }

        if selectedAppIndex < 0 {
            // Initialize to first app
            selectedAppIndex = 0
        } else {
            // Move up by columnCount (to previous row)
            let newIndex = selectedAppIndex - columnCount
            if newIndex >= 0 {
                selectedAppIndex = newIndex
            } else {
                // Wrap to bottom row
                let rowsCount = (apps.count + columnCount - 1) / columnCount
                let lastRowIndex = ((rowsCount - 1) * columnCount) + (selectedAppIndex % columnCount)
                selectedAppIndex = min(lastRowIndex, apps.count - 1)
            }
        }
    }

    func selectAppDown() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }

        if selectedAppIndex < 0 {
            // Initialize to first app
            selectedAppIndex = 0
        } else {
            // Move down by columnCount (to next row)
            let newIndex = selectedAppIndex + columnCount
            if newIndex < apps.count {
                selectedAppIndex = newIndex
            } else {
                // Wrap to top row, same column
                selectedAppIndex = selectedAppIndex % columnCount
            }
        }
    }

    func selectAppLeft() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }

        if selectedAppIndex < 0 {
            selectedAppIndex = apps.count - 1
        } else {
            // Move left by 1, but wrap to end of previous row
            if selectedAppIndex % columnCount == 0 {
                // At start of row, wrap to end of previous row
                let newIndex = selectedAppIndex - 1
                selectedAppIndex = newIndex < 0 ? apps.count - 1 : newIndex
            } else {
                // Not at start of row, just move left
                selectedAppIndex = selectedAppIndex - 1
            }
        }
    }

    func selectAppRight() {
        let apps = displayedApplications
        guard !apps.isEmpty else { return }

        if selectedAppIndex < 0 {
            selectedAppIndex = 0
        } else {
            // Move right by 1, but wrap to start of next row
            if (selectedAppIndex + 1) % columnCount == 0 || selectedAppIndex == apps.count - 1 {
                // At end of row or last item, wrap to start of next row (or beginning)
                selectedAppIndex = (selectedAppIndex + 1) % apps.count
            } else {
                // Not at end of row, just move right
                selectedAppIndex = selectedAppIndex + 1
            }
        }
    }
    
    func selectFirstApp() {
        guard !displayedApplications.isEmpty else { return }
        selectedAppIndex = 0
    }
    
    func selectLastApp() {
        guard !displayedApplications.isEmpty else { return }
        selectedAppIndex = displayedApplications.count - 1
    }
    
    @discardableResult
    func launchSelectedApp() -> Bool {
        let apps = displayedApplications
        guard selectedAppIndex >= 0 && selectedAppIndex < apps.count else { return false }
        let app = apps[selectedAppIndex]
        return ApplicationService.shared.launchApplication(at: app.path, appModel: self)
    }
    
    // MARK: - Cached Computed Properties
    
    /// Update filtered apps cache when search or display order changes.
    /// Uses dirty-flag optimization: skips full re-filter if displayOrder hasn't
    /// changed since the last filter (e.g. when only searchText changes, we still
    /// re-filter but skip the visible-apps scan).
    func updateFilteredApps() {
        let prevSelectedCategory = selectedCategory
        let prevSearchText = searchText
        
        // Increment display order version so downstream code knows the source changed
        displayOrderVersion += 1
        
        // Step 1: Compute visible apps (hidden filtered out) — only if displayOrder changed
        if filterDirty || displayOrderVersion != lastFilterVersion {
            let visible = displayOrder.filter { !$0.isHidden }
            _visibleApplications = visible
            
            // Step 2: Filter by search text
            if prevSearchText.isEmpty {
                _filteredApplications = visible
            } else {
                let searchLower = prevSearchText.lowercased()
                _filteredApplications = visible.filter {
                    $0.lowercaseName.contains(searchLower)
                }
            }
            
            // Step 3: Build category counts from filtered apps
            var counts = Dictionary(uniqueKeysWithValues: AppCategory.allCases.map { ($0, 0) })
            for app in _filteredApplications {
                counts[getCategory(for: app), default: 0] += 1
            }
            categoryCounts = counts
            
            // Step 4: Filter by selected category
            _displayedApplications = _filteredApplications.filter {
                getCategory(for: $0) == prevSelectedCategory
            }
            
            lastFilterVersion = displayOrderVersion
            filterDirty = false
        } else {
            // displayOrder hasn't changed — only re-filter search/category
            let visible = _visibleApplications
            
            if prevSearchText.isEmpty {
                _filteredApplications = visible
            } else {
                let searchLower = prevSearchText.lowercased()
                _filteredApplications = visible.filter {
                    $0.lowercaseName.contains(searchLower)
                }
            }
            
            var counts = Dictionary(uniqueKeysWithValues: AppCategory.allCases.map { ($0, 0) })
            for app in _filteredApplications {
                counts[getCategory(for: app), default: 0] += 1
            }
            categoryCounts = counts
            
            _displayedApplications = _filteredApplications.filter {
                getCategory(for: $0) == prevSelectedCategory
            }
        }
        
        // Reset selection to -1 when no apps are displayed; otherwise clamp to the new range
        if _displayedApplications.isEmpty {
            selectedAppIndex = -1
        } else if selectedAppIndex >= _displayedApplications.count {
            selectedAppIndex = _displayedApplications.count - 1
        }
    }
    
    /// Update recent apps cache
    func updateRecentAppsCache() {
        _recentApps = getRecentAppsInternal()
    }
    
    func getRecentApps() -> [Application] {
        _recentApps
    }
    
    // MARK: - Application Model
    
    struct Application: Identifiable, Equatable, Hashable {
        /// Use path as stable identity so SwiftUI doesn't recreate views on refresh
        var id: String { path }
        let name: String
        let path: String
        let icon: NSImage?
        let installationDate: Date
        
        // App display properties
        let isFolder: Bool
        let containedApps: [String]?
        let appSize: String?
        let bundleDescription: String?
        var isHidden: Bool = false
        
        // Pre-computed lowercase name for efficient search
        let lowercaseName: String

        init(
            name: String,
            path: String,
            icon: NSImage?,
            installationDate: Date,
            isFolder: Bool = false,
            containedApps: [String]? = nil,
            appSize: String? = nil,
            bundleDescription: String? = nil,
            isHidden: Bool = false
        ) {
            self.name = name
            self.path = path
            self.icon = icon
            self.installationDate = installationDate
            self.isFolder = isFolder
            self.containedApps = containedApps
            self.appSize = appSize
            self.bundleDescription = bundleDescription
            self.isHidden = isHidden
            self.lowercaseName = name.lowercased()
        }
        
        static func == (lhs: Application, rhs: Application) -> Bool {
            return lhs.path == rhs.path
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(path)
        }
    }

    private struct AppScanResult {
        let apps: [Application]
        let metadata: [String: Date]
    }
    
    // MARK: - App Directories
    
    nonisolated private static let appDirectories: [String] = {
        var dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]
        // Add user-local Applications directory if it exists
        let homeApps = NSHomeDirectory() + "/Applications"
        if FileManager.default.fileExists(atPath: homeApps) {
            dirs.append(homeApps)
        }
        return dirs
    }()
    
    // MARK: - Loading Applications
    
    nonisolated private static func scanApplications(hiddenPaths: Set<String>) -> AppScanResult {
        let fileManager = FileManager.default
        var apps: [Application] = []
        var seenPaths = Set<String>()
        var metadata: [String: Date] = [:]
        
        for directory in appDirectories {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory) {
                for item in contents where item.hasSuffix(".app") {
                    let fullPath = "\(directory)/\(item)"
                    
                    // Deduplicate across directories
                    guard !seenPaths.contains(fullPath) else { continue }
                    seenPaths.insert(fullPath)
                    
                    // Get modification date (lightweight)
                    let attr = try? fileManager.attributesOfItem(atPath: fullPath)
                    let modDate = attr?[.modificationDate] as? Date ?? Date()
                    
                    metadata[fullPath] = modDate
                    
                    let name = item.replacingOccurrences(of: ".app", with: "")
                    
                    // Mark hidden apps
                    let isHidden = hiddenPaths.contains(fullPath)
                    
                    apps.append(Application(
                        name: name,
                        path: fullPath,
                        icon: nil,
                        installationDate: modDate,
                        isFolder: false,
                        containedApps: nil,
                        appSize: nil,  // Defer size calculation
                        bundleDescription: nil,  // Defer bundle description
                        isHidden: isHidden
                    ))
                }
            }
        }
        
        return AppScanResult(apps: apps, metadata: metadata)
    }
    
    // MARK: - Hidden Apps Management
    
    func toggleHiddenApp(_ appPath: String) {
        if hiddenAppPaths.contains(appPath) {
            hiddenAppPaths.remove(appPath)
        } else {
            hiddenAppPaths.insert(appPath)
        }
        saveHiddenApps()
        
        // Update the app's hidden state in display order
        if let index = displayOrder.firstIndex(where: { $0.path == appPath }) {
            var updatedApp = displayOrder[index]
            updatedApp.isHidden = hiddenAppPaths.contains(appPath)
            displayOrder[index] = updatedApp
            updateFilteredApps()
        }
    }
    
    func isAppHidden(_ appPath: String) -> Bool {
        return hiddenAppPaths.contains(appPath)
    }
    
    private func saveHiddenApps() {
        do {
            let encoded = try JSONEncoder().encode(Array(hiddenAppPaths))
            UserDefaults.standard.set(encoded, forKey: "hiddenAppPaths")
        } catch {
            #if DEBUG
            print("Failed to save hidden apps: \(error)")
            #endif
        }
    }
    
    private func loadHiddenApps() {
        if let data = UserDefaults.standard.data(forKey: "hiddenAppPaths") {
            do {
                let paths = try JSONDecoder().decode(Set<String>.self, from: data)
                hiddenAppPaths = paths
            } catch {
                #if DEBUG
                print("Failed to load hidden apps: \(error)")
                #endif
            }
        }
    }
    
    func refreshApplications(current: [Application]) -> [Application] {
        let currentByPath = Dictionary(uniqueKeysWithValues: current.map { ($0.path, $0) })
        let previousMetadata = appMetadataCache
        let result = Self.scanApplications(hiddenPaths: hiddenAppPaths)
        appMetadataCache = result.metadata
        return mergeScannedApplications(result, currentByPath: currentByPath, previousMetadata: previousMetadata)
    }

    private func mergeScannedApplications(
        _ result: AppScanResult,
        currentByPath: [String: Application],
        previousMetadata: [String: Date]
    ) -> [Application] {
        result.apps.map { scannedApp in
            if var existing = currentByPath[scannedApp.path],
               previousMetadata[scannedApp.path] == result.metadata[scannedApp.path] {
                existing.isHidden = scannedApp.isHidden
                return existing
            }

            if let cachedIcon = getIconFromCache(scannedApp.path) {
                return Application(
                    name: scannedApp.name,
                    path: scannedApp.path,
                    icon: cachedIcon,
                    installationDate: scannedApp.installationDate,
                    isFolder: scannedApp.isFolder,
                    containedApps: scannedApp.containedApps,
                    appSize: scannedApp.appSize,
                    bundleDescription: scannedApp.bundleDescription,
                    isHidden: scannedApp.isHidden
                )
            }

            return scannedApp
        }
    }
    
    // MARK: - Icon Cache Management (NSCache for automatic memory management)
    
    private func addIconToCache(_ path: String, icon: NSImage?) {
        guard let icon = icon else { return }
        // Use declared pixel dimensions as a cheap cost proxy — avoids calling
        // tiffRepresentation which forces synchronous XPC rasterisation via IconServices.
        let cost = Int(icon.size.width * icon.size.height) * 4
        iconCache.setObject(icon, forKey: path as NSString, cost: cost)
    }
    
    private func getIconFromCache(_ path: String) -> NSImage? {
        return iconCache.object(forKey: path as NSString)
    }
    
    private func removeIconFromCache(_ path: String) {
        iconCache.removeObject(forKey: path as NSString)
    }

    private func loadMissingIcons() {
        let paths = displayOrder
            .filter { $0.icon == nil }
            .map { $0.path }

        guard !paths.isEmpty else { return }
        iconLoadGeneration += 1
        loadIcons(paths: paths, batchSize: kIconCacheBatchSize, startIndex: 0, generation: iconLoadGeneration)
    }

    private func loadIcons(paths: [String], batchSize: Int, startIndex: Int, generation: Int) {
        guard generation == iconLoadGeneration, startIndex < paths.count else { return }

        let endIndex = min(startIndex + batchSize, paths.count)
        let batch = Array(paths[startIndex..<endIndex])

        // Load each icon from cache or from NSWorkspace (main-thread-only API).
        // Smaller batches (12 icons) distribute blocking over more intervals.
        var iconsToApply: [String: NSImage] = [:]
        for path in batch {
            if let cached = getIconFromCache(path) {
                iconsToApply[path] = cached
            } else {
                let icon = NSWorkspace.shared.icon(forFile: path)
                addIconToCache(path, icon: icon)
                iconsToApply[path] = icon
            }
        }
        applyIcons(iconsToApply, shouldNotify: endIndex >= paths.count)

        let isLastBatch = endIndex >= paths.count
        if isLastBatch {
            // Recent apps reference Application structs; rebuild once after all icons are loaded.
            updateRecentAppsCache()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + kIconLoadDelay) { [weak self] in
            self?.loadIcons(paths: paths, batchSize: batchSize, startIndex: endIndex, generation: generation)
        }
    }

    /// Apply icons to displayOrder using in-place mutation — avoids copying the
    /// entire array when only a subset of icons change.
    /// Only sends objectWillChange on the final batch to reduce SwiftUI recomputation.
    private func applyIcons(_ iconsByPath: [String: NSImage], shouldNotify: Bool = false) {
        guard !iconsByPath.isEmpty else { return }

        // Build one shared index dictionary from displayOrder
        let indexByPath = Dictionary(uniqueKeysWithValues: displayOrder.enumerated()
            .map { ($0.element.path, $0.offset) })

        var didUpdate = false

        for (path, icon) in iconsByPath {
            guard let appIndex = indexByPath[path] else { continue }
            guard displayOrder[appIndex].icon == nil else { continue }

            let app = displayOrder[appIndex]
            displayOrder[appIndex] = Application(
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
            didUpdate = true
        }

        if didUpdate {
            // Propagate updated icons into each cached filtered array directly —
            // icons don't affect filter predicates or order, so re-running the full
            // filter pipeline per batch is unnecessary.
            patchIconsInFilteredArrays(iconsByPath)
            // Only notify SwiftUI observers on final batch to avoid 13 render passes;
            // icons appear progressively as batches complete anyway.
            if shouldNotify {
                objectWillChange.send()
            }
        }
    }

    /// Patch icons into all cached filtered arrays using O(1) path lookup.
    /// Pre-builds index dictionaries to avoid O(n) firstIndex(where:) per icon.
    private func patchIconsInFilteredArrays(_ iconsByPath: [String: NSImage]) {
        guard !iconsByPath.isEmpty else { return }

        func patch(_ arr: inout [Application]) {
            // Pre-build path→index map: O(n) once, then O(1) per icon
            let indexByPath = Dictionary(uniqueKeysWithValues: arr.enumerated()
                .map { ($0.element.path, $0.offset) })

            for (path, icon) in iconsByPath {
                guard let i = indexByPath[path], arr[i].icon == nil else { continue }
                let a = arr[i]
                arr[i] = Application(
                    name: a.name, path: a.path, icon: icon,
                    installationDate: a.installationDate,
                    isFolder: a.isFolder, containedApps: a.containedApps,
                    appSize: a.appSize, bundleDescription: a.bundleDescription,
                    isHidden: a.isHidden
                )
            }
        }
        patch(&_visibleApplications)
        patch(&_filteredApplications)
        patch(&_displayedApplications)
        patch(&_recentApps)
    }
    
    // MARK: - Recent Apps Management
    
    func recordAppLaunch(at path: String) {
        recentApps[path] = Date()
        
        // Evict oldest entries if cache is full
        while recentApps.count > maxRecentApps, let oldestPath = recentApps.min(by: { $0.value < $1.value })?.key {
            recentApps.removeValue(forKey: oldestPath)
        }
        
        // Update cached recent apps
        updateRecentAppsCache()
    }
    
    /// Internal recent apps retrieval — uses a cached index for O(1) path→app lookups.
    private func getRecentAppsInternal() -> [Application] {
        let recentPaths = Set(recentApps.keys)
        
        // Fast path: if no recent apps tracked, return empty immediately
        guard !recentPaths.isEmpty else { return [] }
        
        // Build a path→Application map from displayOrder once
        let appByPath: [String: Application] = Dictionary(
            uniqueKeysWithValues: displayOrder.map { ($0.path, $0) }
        )
        
        // Collect matching apps from recentPaths (O(k) where k = number of recent paths)
        var result: [Application] = []
        result.reserveCapacity(min(recentPaths.count, displayOrder.count))
        for path in recentPaths {
            if let app = appByPath[path] {
                result.append(app)
            }
        }
        
        // Sort by launch time (most recent first)
        result.sort { lhs, rhs in
            guard let lhsTime = recentApps[lhs.path], let rhsTime = recentApps[rhs.path] else {
                return false
            }
            return lhsTime > rhsTime
        }
        return result
    }
    
    func isRecentApp(_ path: String) -> Bool {
        return recentApps[path] != nil
    }
    
    // MARK: - App Categories
    
    // MARK: - Icon Size
    
    enum IconSize: String, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        
        var id: String { rawValue }
        
        var value: CGFloat {
            switch self {
            case .small: return 48
            case .medium: return 64
            case .large: return 80
            }
        }
    }
    

    enum AppCategory: String, CaseIterable, Identifiable {
        case system = "System"
        case utilities = "Utilities"
        case user = "User"
        
        var id: String { rawValue }
        
        static func category(for path: String) -> AppCategory {
            if path.hasPrefix("/System/Applications") || path.hasPrefix("/System/Volumes/Preboot") {
                return .system
            } else if path.contains("/Utilities/") {
                return .utilities
            } else {
                return .user
            }
        }
    }
    
    func getCategory(for app: Application) -> AppCategory {
        return AppCategory.category(for: app.path)
    }
    
    // MARK: - Sorting & Ordering
    
    func updateCustomOrder(from newOrder: [Application]) {
        customOrder = [:]
        for (index, app) in newOrder.enumerated() {
            customOrder[app.path] = index
        }
        saveCustomOrder()
        updateDisplayOrder()
    }
    
    func setSortOption(_ option: ApplicationSorter.SortOption) {
        sortOption = option
        saveSortOption()
        customOrder = [:]
        updateDisplayOrder()
    }
    
    // MARK: - Font Settings
    
    func setFontFamily(_ family: String) {
        fontFamily = family
        saveFontSettings()
        applyFontSettings()
    }
    
    func setFontSize(_ size: Double) {
        fontSize = size
        saveFontSettings()
        applyFontSettings()
    }
    
    func setFontWeight(_ weight: String) {
        fontWeight = weight
        saveFontSettings()
        applyFontSettings()
    }
    
    func setColumnCount(_ count: Int) {
        columnCount = count
        saveColumnCount()
        objectWillChange.send()
    }
    
    func setIconSize(_ size: IconSize) {
        iconSize = size
        saveIconSize()
        objectWillChange.send()
    }

    
    func setApplications(_ apps: [Application]) {
        displayOrder = sortedApplications(apps)
        updateFilteredApps()
        updateRecentAppsCache()
    }
    
    private func updateDisplayOrder() {
        displayOrder = sortedApplications(displayOrder)
        updateFilteredApps()  // Update cached filtered apps
        updateRecentAppsCache()  // Update cached recent apps
    }
    
    /// Sorted applications with caching — returns cached result if sortOption and
    /// customOrder haven't changed since the last call for the same input array.
    func sortedApplications(_ applications: [Application]) -> [Application] {
        // Compute a simple hash of the input to detect changes
        let inputKey = applications.count
        
        // Check if we can return the cached result
        let currentSortKey = customOrder.isEmpty ? sortOption.rawValue : "custom:\(customOrder.count)"
        if cachedSortKey == currentSortKey,
           cachedSortInputCount == inputKey,
           !cachedSortedApps.isEmpty,
           cachedSortedApps.count == applications.count {
            return cachedSortedApps
        }
        
        var result: [Application]
        if !customOrder.isEmpty {
            result = applications.sorted { lhs, rhs in
                let lhsIndex = customOrder[lhs.path] ?? Int.max
                let rhsIndex = customOrder[rhs.path] ?? Int.max
                return lhsIndex < rhsIndex
            }
        } else {
            switch sortOption {
            case .name:
                result = applications.sorted { $0.lowercaseName < $1.lowercaseName }
            case .installationDate:
                result = applications.sorted { $0.installationDate > $1.installationDate }
            }
        }
        
        // Cache the result
        cachedSortedApps = result
        cachedSortKey = currentSortKey
        cachedSortInputCount = inputKey
        
        return result
    }
    
    // Cache for sorted results
    private var cachedSortKey: String?
    private var cachedSortInputCount: Int = 0
    
    /// Refresh the application list by scanning directories.
    /// Skips the full rescan if no app metadata has changed since last scan.
    func refreshDisplayOrder() {
        guard !isRefreshingApplications else { return }
        
        // Quick check: if metadata hasn't changed, skip the full rescan
        let hiddenPaths = hiddenAppPaths
        var hasChanges = false
        var newMetadata: [String: Date] = [:]
        
        // Lightweight check on main thread before spawning work
        for directory in Self.appDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = "\(directory)/\(item)"
                guard let attr = try? FileManager.default.attributesOfItem(atPath: fullPath),
                      let modDate = attr[.modificationDate] as? Date else { continue }
                newMetadata[fullPath] = modDate
                if let previousDate = appMetadataCache[fullPath], previousDate != modDate {
                    hasChanges = true
                }
            }
        }
        
        // If nothing changed, just update the metadata cache and bail
        guard hasChanges || newMetadata.count != appMetadataCache.count else {
            appMetadataCache = newMetadata
            return
        }
        
        isRefreshingApplications = true

        let currentByPath = Dictionary(uniqueKeysWithValues: displayOrder.map { ($0.path, $0) })
        let previousMetadata = appMetadataCache

        DispatchQueue.global(qos: .utility).async {
            let result = Self.scanApplications(hiddenPaths: hiddenPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let merged = self.mergeScannedApplications(
                    result,
                    currentByPath: currentByPath,
                    previousMetadata: previousMetadata
                )
                self.appMetadataCache = result.metadata
                self.displayOrder = self.sortedApplications(merged)
                self.updateFilteredApps()
                self.updateRecentAppsCache()
                self.loadMissingIcons()
                self.isRefreshingApplications = false
            }
        }
    }
    
    // MARK: - State Management
    
    /// Clear transient launcher state when hiding the overlay.
    func clearSearchState() {
        searchText = ""
        updateFilteredApps()  // Recalculate filtered apps
        updateRecentAppsCache()  // Recalculate recent apps
    }
    
    // MARK: - Timer Management
    
    func setupRefreshTimer() {
        cleanupTimerAndObservers()
        
        startTimer(interval: refreshInterval)
        
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTimer?.invalidate()
                self?.startTimer(interval: self?.refreshInterval ?? 300)
            }
        }
        
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTimer?.invalidate()
                // Slow down refresh when in background
                self?.startTimer(interval: 900)
            }
        }
    }
    
    func cleanupTimerAndObservers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let obs = activeObserver {
            NotificationCenter.default.removeObserver(obs)
            activeObserver = nil
        }
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
    }
    
    private func startTimer(interval: TimeInterval) {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplayOrder()
            }
        }
    }
    
    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        startTimer(interval: refreshInterval)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        cleanupTimerAndObservers()
    }
    
    deinit {
        // AppModel is @MainActor so deinit always runs on the main thread.
        MainActor.assumeIsolated {
            cleanupTimerAndObservers()
        }
        #if DEBUG
        print("AppModel deinitialized")
        #endif
    }
}
