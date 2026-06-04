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
    var hiddenAppPaths: Set<String> = []
    var customDirectories: [String] = []
    var allScanDirectories: [String] = []
    
    // MARK: - Recent Apps Tracking
    var _recentApps: [Application] = []
    private var recentAppLaunchTimes: [String: Date] = [:]
    private let maxRecentApps = 8
    
    // MARK: - UI & Navigation State
    var selectedAppIndex: Int = 0
    var scrollTargetIndex: Int?  // Set to trigger scrolling to index
    var searchTerm: String = ""
    var fontFamily: String = "SF Pro"
    var fontSize: Double = 14.0
    var fontWeight: String = "normal"
    var columnCount: Int = 4
    var iconSize: IconSize = .medium
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
        loadPersistedPreferences()
        loadCustomDirectories()
        loadFontFamily()

        Task {
            let hiddenPaths = hiddenAppPaths
            let allDirs = allScanDirectories
            let workspace = NSWorkspace.shared // Capture on main to avoid Sendable issues
            
            let result = await Self.scanApplications(directories: allDirs, hiddenPaths: hiddenPaths, workspace: workspace)
            
            self.appMetadataCache = result.metadata
            self.displayOrder = self.sortedApplications(result.apps)
            self.isLoading = false
            self.updateFilteredApps()
            self.setupRefreshTimer()
            await self.loadMissingIcons()
        }
    }
    
    // MARK: - Persistence & Setup
    private func loadHiddenApps() {
        if let data = UserDefaults.standard.data(forKey: "hiddenAppPaths"),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data) {
            hiddenAppPaths = paths
        }
    }
    
    private func loadPersistedPreferences() {
        if let cols = UserDefaults.standard.value(forKey: "columnCount") as? Int {
            columnCount = max(1, cols)
        }
        // Load sortOption, iconSize, etc.
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
    
    private static let defaultScanDirectories = ["/Applications", "/System/Applications"]
    
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
        
        let workspace = NSWorkspace.shared
        let icons = await Task.detached { [workspace] in
            var icons: [String: NSImage?] = [:]
            for path in missingPaths {
                icons[path] = workspace.icon(forFile: path)
            }
            return icons
        }.value
        
        for (path, icon) in icons {
            if let index = self.displayOrder.firstIndex(where: { $0.path == path }) {
                self.displayOrder[index] = Application(
                    id: self.displayOrder[index].id,
                    name: self.displayOrder[index].name,
                    path: path,
                    icon: icon,
                    installationDate: self.displayOrder[index].installationDate,
                    isFolder: self.displayOrder[index].isFolder,
                    containedApps: self.displayOrder[index].containedApps,
                    appSize: self.displayOrder[index].appSize,
                    bundleDescription: self.displayOrder[index].bundleDescription,
                    isHidden: self.displayOrder[index].isHidden
                )
            }
        }
    }
    
    private func updateFilteredApps() {
        updateRecentApps()
    }
    
    // MARK: - Background Scanning
    static func scanApplications(directories: [String], hiddenPaths: Set<String>, workspace: NSWorkspace) async -> AppScanResult {
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
                let name = bundle?.infoDictionary?["CFBundleName"] as? String ?? item
                let date = attributes?[.modificationDate] as? Date ?? Date()
                let size = attributes?[.size] as? Int
                
                // Determine if this is a folder containing multiple apps
                // Check for contained apps both for regular folders and .app bundles (like Xcode)
                let containedApps = Self.findContainedApps(in: fullPath, workspace: workspace)
                let isFolder = (containedApps?.isEmpty == false)
                
                apps.append(Application(
                    id: fullPath,
                    name: name,
                    path: fullPath,
                    icon: workspace.icon(forFile: fullPath),
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
    private static func findContainedApps(in directoryPath: String, workspace: NSWorkspace) -> [String]? {
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
        let workspace = NSWorkspace.shared
        
        let result = await Self.scanApplications(directories: allDirs, hiddenPaths: hiddenPaths, workspace: workspace)
        
        self.appMetadataCache = result.metadata
        self.displayOrder = self.sortedApplications(result.apps)
        self.updateFilteredApps()
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
        let sortedLaunchTimes = recentAppLaunchTimes.sorted { $0.value > $1.value }
        let recentPaths = Set(sortedLaunchTimes.prefix(maxRecentApps).map { $0.key })
        _recentApps = displayOrder.filter { recentPaths.contains($0.path) }
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
        } else {
            selectedAppIndex -= columnCount
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
        } else {
            selectedAppIndex += columnCount
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
            }
        } else {
            selectedAppIndex -= 1
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
            }
        } else {
            selectedAppIndex += 1
        }
        scrollTargetIndex = selectedAppIndex
    }
    
    /// Clears the scroll target after scrolling has been performed
    func clearScrollTarget() {
        scrollTargetIndex = nil
    }
    
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
    func toggleHiddenApp(_ app: Application) {
        if hiddenAppPaths.contains(app.path) {
            hiddenAppPaths.remove(app.path)
        } else {
            hiddenAppPaths.insert(app.path)
        }
        saveHiddenApps()
    }
    
    func toggleHiddenApp(_ path: String) {
        if hiddenAppPaths.contains(path) {
            hiddenAppPaths.remove(path)
        } else {
            hiddenAppPaths.insert(path)
        }
        saveHiddenApps()
    }
    
    func isAppHidden(_ path: String) -> Bool {
        return hiddenAppPaths.contains(path)
    }
    
    func getCategory(for app: Application) -> AppCategory {
        if app.path.hasPrefix("/System") {
            return .system
        } else if app.path.hasPrefix("/Applications") || app.path.hasPrefix("/Users") {
            return .user
        }
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
        applyFontSettings()
    }
    
    func applyFontSettings() {
        // Placeholder for font application logic
    }
    
    func setColumnCount(_ count: Int) {
        columnCount = count
        UserDefaults.standard.set(count, forKey: "columnCount")
    }
    
    func setSortOption(_ option: ApplicationSorter.SortOption) {
        sortOption = option
    }
    
    func setApplications(_ apps: [Application]) {
        displayOrder = apps
        updateFilteredApps()
    }
    
    func updateCustomOrder(from apps: [Application]) {
        for (index, app) in apps.enumerated() {
            customOrder[app.path] = index
        }
        displayOrder = apps
        updateFilteredApps()
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
    
    // MARK: - Computed Properties & Display Helpers
    var visibleApplications: [Application] {
        displayOrder.filter { !$0.isHidden }
    }
    
    func getDisplayedApps() -> [Application] {
        var apps = visibleApplications
        if !searchTerm.isEmpty {
            let lower = searchTerm.lowercased()
            apps = apps.filter { $0.lowercaseName.contains(lower) }
        }
        apps = sortedApplications(apps)
        if !customOrder.isEmpty {
            apps.sort { (a, b) in
                (customOrder[a.path] ?? Int.max) < (customOrder[b.path] ?? Int.max)
            }
        }
        return apps
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
    
    struct Application: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let icon: NSImage?
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
}