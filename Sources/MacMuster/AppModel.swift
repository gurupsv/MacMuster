import Foundation
import AppKit
import SwiftUI
import Observation

/// Thin wrapper combining SettingsAppearance, LibraryScanState, and NavigationSelection.
/// Existing code references AppModel; this delegates to the three smaller @Observable objects.
///
/// ## Migration Path (Issue #5)
/// The ~100 delegated properties/methods below are a maintenance tax. New code should access
/// the sub-objects directly:
///   `appModel.settings.glowEnabled`  instead of  `appModel.glowEnabled`
///   `appModel.library.folders`       instead of  `appModel.folders`
///   `appModel.navigation.searchTerm` instead of  `appModel.searchTerm`
///
/// The delegated properties remain for backward compatibility with existing callers.
/// Once all call sites are migrated, the delegation block (lines 28–257) can be removed.
@MainActor
@Observable
class AppModel {
    let settings = SettingsAppearance()
    let library = LibraryScanState()
    let navigation = NavigationSelection()

    init() {
        // Navigation needs displayed apps, categories, and counts for selection logic
        navigation.library = library
        // Navigation needs column count and font info for selected item display
        navigation.settings = settings
        // Library needs refresh interval and icon size preferences for sorting/load
        library.settings = settings
        // Library needs selectedAppIndex for sort-aware position tracking
        library.navigation = navigation
    }

    // MARK: - Delegated Properties

    var refreshInterval: TimeInterval {
        get { settings.refreshInterval }
        set { settings.refreshInterval = newValue }
    }
    var isLoading: Bool {
        get { library.isLoading }
        set { library.isLoading = newValue }
    }
    var displayOrder: [Application] {
        get { library.displayOrder }
        set { library.displayOrder = newValue }
    }
    var loadedIconsByPath: [String: NSImage] {
        get { library.loadedIconsByPath }
        set { library.loadedIconsByPath = newValue }
    }
    var hiddenAppPaths: Set<String> {
        get { library.hiddenAppPaths }
        set { library.hiddenAppPaths = newValue }
    }
    var customDirectories: [String] {
        get { library.customDirectories }
        set { library.customDirectories = newValue }
    }
    var allScanDirectories: [String] {
        get { library.allScanDirectories }
        set { library.allScanDirectories = newValue }
    }
    var folders: [AppFolder] {
        get { library.folders }
        set { library.folders = newValue }
    }
    var currentFolderId: String? {
        get { library.currentFolderId }
        set { library.currentFolderId = newValue }
    }
    var _recentApps: [Application] {
        get { library._recentApps }
        set { library._recentApps = newValue }
    }
    var _mostUsedApps: [Application] {
        get { library._mostUsedApps }
        set { library._mostUsedApps = newValue }
    }
    var customOrder: [String: Int] {
        get { library.customOrder }
        set { library.customOrder = newValue }
    }
    var sortOption: ApplicationSorter.SortOption {
        get { library.sortOption }
        set { library.sortOption = newValue }
    }
    var selectedAppIndex: Int {
        get { navigation.selectedAppIndex }
        set { navigation.selectedAppIndex = newValue }
    }
    var scrollTargetIndex: Int? {
        get { navigation.scrollTargetIndex }
        set { navigation.scrollTargetIndex = newValue }
    }
    var scrollTargetAnchor: ScrollAnchor? {
        get { navigation.scrollTargetAnchor }
        set { navigation.scrollTargetAnchor = newValue }
    }
    var launchingAppPath: String? {
        get { navigation.launchingAppPath }
        set { navigation.launchingAppPath = newValue }
    }
    var searchTerm: String {
        get { navigation.searchTerm }
        set { navigation.searchTerm = newValue }
    }
    var selectedCategory: AppCategory {
        get { navigation.selectedCategory }
        set { navigation.selectedCategory = newValue }
    }
    var categoryCounts: [AppCategory: Int] {
        get { navigation.categoryCounts }
        set { navigation.categoryCounts = newValue }
    }
    var fontFamily: String {
        get { settings.fontFamily }
        set { settings.fontFamily = newValue }
    }
    var fontSize: Double {
        get { settings.fontSize }
        set { settings.fontSize = newValue }
    }
    var fontWeight: String {
        get { settings.fontWeight }
        set { settings.fontWeight = newValue }
    }
    var columnCount: Int {
        get { settings.columnCount }
        set { settings.columnCount = newValue }
    }
    var iconSize: IconSize {
        get { settings.iconSize }
        set { settings.setIconSize(newValue) }
    }
    var launchMode: LaunchMode {
        get { settings.launchMode }
        set { settings.launchMode = newValue }
    }
    func setLaunchMode(_ mode: LaunchMode) { settings.launchMode = mode }
    var glowEnabled: Bool {
        get { settings.glowEnabled }
        set { settings.glowEnabled = newValue }
    }
    var glowColor: Color {
        get { settings.glowColor }
        set { settings.glowColor = newValue }
    }
    var glowIntensity: Double {
        get { settings.glowIntensity }
        set { settings.glowIntensity = newValue }
    }
    var glowWidth: Double {
        get { settings.glowWidth }
        set { settings.glowWidth = newValue }
    }
    var overlayOpacity: Double {
        get { settings.overlayOpacity }
        set { settings.overlayOpacity = newValue }
    }
    var visibleApplications: [Application] {
        get { library.visibleApplications }
    }
    var showRecentApps: Bool {
        get { settings.showRecentApps }
        set { settings.showRecentApps = newValue }
    }
    var pressFeedbackEnabled: Bool {
        get { settings.pressFeedbackEnabled }
        set { settings.pressFeedbackEnabled = newValue }
    }
    var shouldReduceMotion: Bool {
        get { settings.shouldReduceMotion }
    }
    var launchAnimationDirection: SettingsAppearance.LaunchAnimationDirection {
        get { settings.launchAnimationDirection }
        set { settings.launchAnimationDirection = newValue }
    }
    var launchAnimationEnabled: Bool {
        get { settings.launchAnimationEnabled }
        set { settings.launchAnimationEnabled = newValue }
    }
    var hasShownLauncher: Bool {
        get { settings.hasShownLauncher }
        set { settings.hasShownLauncher = newValue }
    }
    var showFoldersFirst: Bool {
        get { settings.showFoldersFirst }
        set { settings.showFoldersFirst = newValue; library.dataVersion += 1 }
    }
    var showHiddenApps: Bool {
        get { settings.showHiddenApps }
        set { settings.showHiddenApps = newValue; library.dataVersion += 1 }
    }

    var presentationMode: SettingsAppearance.PresentationMode {
        get { settings.presentationMode }
        set { settings.presentationMode = newValue }
    }

    var tintColor: Color {
        get { settings.tintColor }
        set { settings.tintColor = newValue }
    }

    var tintStrength: Double {
        get { settings.tintStrength }
        set { settings.tintStrength = newValue }
    }

    // MARK: - Delegated Methods

    func startLoading() async { await library.startLoading() }
    func refreshDisplayOrder(force: Bool = false) async { await library.refreshDisplayOrder(force: force) }
    func loadMissingIcons() async { await library.loadMissingIcons() }
    func refreshCachedIcons() async { await library.refreshCachedIcons() }
    func cleanupTimerAndObservers() { library.cleanupTimerAndObservers() }
    func updateFilteredApps() { library.updateFilteredApps() }
    func sortedApplications(_ apps: [Application]) -> [Application] { library.sortedApplications(apps) }
    func recordAppLaunch(at path: String) { library.recordAppLaunch(at: path) }
    func isRecentApp(_ path: String) -> Bool { library.isRecentApp(path) }
    func getRecentApps() -> [Application] { library.getRecentApps() }
    func toggleHiddenApp(_ path: String) { library.toggleHiddenApp(path) }
    func toggleHiddenApp(_ app: Application) { library.toggleHiddenApp(app) }
    func isAppHidden(_ path: String) -> Bool { library.isAppHidden(path) }
    func setFontFamily(_ family: String) { settings.setFontFamily(family) }
    func setFontWeight(_ weight: String) { settings.setFontWeight(weight) }
    func setColumnCount(_ count: Int) { settings.setColumnCount(count) }
    func setIconSize(_ size: IconSize) { settings.setIconSize(size) }
    func setRefreshInterval(_ interval: TimeInterval) { settings.setRefreshInterval(interval) }
    func setSortOption(_ option: ApplicationSorter.SortOption) { library.setSortOption(option) }
    func setApplications(_ apps: [Application]) { library.setApplications(apps) }
    func updateCustomOrder(from apps: [Application]) { library.updateCustomOrder(from: apps) }
    func getCategory(for app: Application) -> AppCategory { library.getCategory(for: app) }
    func isMostUsed(_ app: Application) -> Bool { library.isMostUsed(app) }
    func isRecentlyLaunched(_ app: Application) -> Bool { library.isRecentlyLaunched(app) }
    func isNewlyInstalled(_ app: Application) -> Bool { library.isNewlyInstalled(app) }
    func matchesSelectedCategory(_ app: Application) -> Bool { library.matchesSelectedCategory(app, selectedCategory: selectedCategory) }
    func removeCustomDirectory(_ path: String) { library.removeCustomDirectory(path) }
    func addCustomDirectory(_ path: String, bookmarkData: Data? = nil) { library.addCustomDirectory(path, bookmarkData: bookmarkData) }
    func getDisplayedApps() -> [Application] { library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory, columnCount: columnCount) }
    func getFolderApplication(_ folder: AppFolder) -> Application { library.getFolderApplication(folder) }
    func createFolder(name: String, appPaths: [String]) -> AppFolder? { library.createFolder(name: name, appPaths: appPaths) }
    func deleteFolder(folderId: String) { library.deleteFolder(folderId: folderId) }
    func renameFolder(folderId: String, newName: String) { library.renameFolder(folderId: folderId, newName: newName) }
    func addAppToFolder(_ appPath: String, folderId: String) { library.addAppToFolder(appPath, folderId: folderId) }
    func removeAppFromFolder(_ appPath: String, folderId: String) { library.removeAppFromFolder(appPath, folderId: folderId) }
    func moveAppInFolder(_ appPath: String, from folderId: String, to toFolderId: String) { library.moveAppInFolder(appPath, from: folderId, to: toFolderId) }
    func moveAppToRoot(_ appPath: String, folderId: String) { library.moveAppToRoot(appPath, folderId: folderId) }
    func openFolder(_ folderId: String) { library.openFolder(folderId) }
    func closeFolder() { library.closeFolder() }
    var currentFolder: AppFolder? { library.currentFolder }
    func getAllAppsIncludingChildFolders(for folderId: String) -> [Application] { library.getAllAppsIncludingChildFolders(for: folderId) }
    func selectAppUp() { navigation.selectAppUp() }
    func selectAppDown() { navigation.selectAppDown() }
    func selectAppLeft() { navigation.selectAppLeft() }
    func selectAppRight() { navigation.selectAppRight() }
    func clearScrollTarget() { navigation.clearScrollTarget() }
    func launchSelectedApp() -> Bool { navigation.launchSelectedApp() }
    func clearSearchState() { navigation.clearSearchState() }
    func selectFirstApp() { navigation.selectFirstApp() }
    func selectLastApp() { navigation.selectLastApp() }
    func selectNextApp() { navigation.selectNextApp() }
    func selectPreviousApp() { navigation.selectPreviousApp() }
    func selectApp(at index: Int) { navigation.selectApp(at: index) }

    /// Launches an app with immediate visual feedback and dismisses the launcher on a fixed timer.
    ///
    /// Order: set feedback state → hand off to the async launcher → dismiss after the feedback beat.
    ///
    /// The dismissal deliberately runs on its **own** task rather than inside the launch completion
    /// handler. That handler fires only once LaunchServices has finished starting the target app
    /// (measured: 146 ms for Calculator, 235 ms for Books, seconds for large apps), so hanging the
    /// hide off it reintroduces exactly the freeze this is meant to remove. Time-to-dismiss must be
    /// a constant, independent of which app was clicked.
    func launchAndDismiss(_ app: Application) {
        launchingAppPath = app.path

        let feedbackDuration: UInt64 = shouldReduceMotion ? 0 : LaunchMetrics.dismissFeedbackNanoseconds
        let dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: feedbackDuration)
            guard !Task.isCancelled else { return }
            launchingAppPath = nil
            StatusBarManager.shared.hideWindow()
        }

        ApplicationService.shared.launchApplication(at: app.path, appModel: self) { success in
            guard !success else { return }
            // A launch that fails fast can beat the dismissal — cancel it so the launcher doesn't
            // flicker shut and straight back open. If it already fired, showWindow() restores it.
            dismissTask.cancel()
            self.launchingAppPath = nil
            StatusBarManager.shared.showWindow()
            NSAlert.showError(String(localized: "Launch Failed"), String(localized: "Could not launch \(app.name)."))
        }
    }

    static var defaultScanDirectories: [String] { LibraryScanState.defaultScanDirectories }
}
