import Foundation
import SwiftUI

/// Handles persistence of application settings and preferences using UserDefaults.
@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()
    private let defaults = UserDefaults.standard
    
    private enum Keys: String {
        case schemaVersion = "schemaVersion"
        case hiddenAppPaths = "hiddenAppPaths"
        case columnCount = "columnCount"
        case currentFolderId = "currentFolderId"
        case customOrder = "customOrder"
        case sortOption = "sortOption"
        case iconSize = "iconSize"
        case launchMode = "launchMode"
        case refreshInterval = "refreshInterval"
        case showFoldersFirst = "showFoldersFirst"
        case hasShownLauncher = "hasShownLauncher"
        case glowEnabled = "glowEnabled"
        case glowColor = "glowColor"
        case glowIntensity = "glowIntensity"
        case glowWidth = "glowWidth"
        case fontFamily = "fontFamily"
        case fontSize = "fontSize"
        case fontWeight = "fontWeight"
        case customDirectories = "customDirectories"
        case customDirectoryBookmarks = "customDirectoryBookmarks"
        case folders = "appFolders"
        case pressFeedbackEnabled = "pressFeedbackEnabled"
        case recentAppsEnabled = "recentAppsEnabled"
        case overlayOpacity = "overlayOpacity"
        case showInDock = "showInDock"
        case launchAnimationDirection = "launchAnimationDirection"
        case launchAnimationEnabled = "launchAnimationEnabled"
        case presentationMode = "presentationMode"
        case tintColor = "tintColor"
        case tintStrength = "tintStrength"
        case showHiddenApps = "showHiddenApps"
    }

    /// Current schema version. Increment when adding/removing/changing preference keys.
    /// Used for future migrations (e.g., renaming keys, consolidating settings, etc.).
    private let currentSchemaVersion = 1
    
    private init() {
        // Migrate schema if needed
        let storedSchemaVersion = defaults.integer(forKey: Keys.schemaVersion.rawValue)
        if storedSchemaVersion == 0 {
            // First time or pre-versioning: set to current and run initialization
            defaults.set(currentSchemaVersion, forKey: Keys.schemaVersion.rawValue)
        } else if storedSchemaVersion < currentSchemaVersion {
            // Run any needed migrations here (future use)
            runMigrations(from: storedSchemaVersion, to: currentSchemaVersion)
            defaults.set(currentSchemaVersion, forKey: Keys.schemaVersion.rawValue)
        }

        // Set defaults for new keys if not already present
        if defaults.object(forKey: Keys.recentAppsEnabled.rawValue) == nil {
            defaults.set(true, forKey: Keys.recentAppsEnabled.rawValue)
        }
        if defaults.object(forKey: Keys.pressFeedbackEnabled.rawValue) == nil {
            defaults.set(true, forKey: Keys.pressFeedbackEnabled.rawValue)
        }
        if defaults.object(forKey: Keys.overlayOpacity.rawValue) == nil {
            defaults.set(GlowMetrics.overlayOpacityDefault, forKey: Keys.overlayOpacity.rawValue)
        }
        if defaults.object(forKey: Keys.launchAnimationDirection.rawValue) == nil {
            defaults.set("zoomOut", forKey: Keys.launchAnimationDirection.rawValue)
        }
        if defaults.object(forKey: Keys.launchAnimationEnabled.rawValue) == nil {
            defaults.set(true, forKey: Keys.launchAnimationEnabled.rawValue)
        }
        if defaults.object(forKey: Keys.showHiddenApps.rawValue) == nil {
            defaults.set(false, forKey: Keys.showHiddenApps.rawValue)
        }
    }

    /// Run any needed migrations when schema version changes.
    /// Add cases here as new schema versions are introduced.
    private func runMigrations(from oldVersion: Int, to newVersion: Int) {
        // Example: if oldVersion < 2 { /* migrate from v1 to v2 */ }
        // For now, this is a no-op as we're at schema version 1
    }
    
    // MARK: - General Preferences
    
    func loadColumnCount() -> Int? {
        defaults.value(forKey: Keys.columnCount.rawValue) as? Int
    }
    
    func saveColumnCount(_ count: Int) {
        defaults.set(count, forKey: Keys.columnCount.rawValue)
    }
    
    func loadCurrentFolderId() -> String? {
        defaults.string(forKey: Keys.currentFolderId.rawValue)
    }
    
    func loadCustomOrder() -> [String: Int]? {
        guard let data = defaults.data(forKey: Keys.customOrder.rawValue) else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }
    
    func loadSortOption() -> String? {
        defaults.string(forKey: Keys.sortOption.rawValue)
    }
    
    func loadIconSize() -> String? {
        defaults.string(forKey: Keys.iconSize.rawValue)
    }
    
    func saveLaunchMode(_ mode: LaunchMode) {
        defaults.set(mode.rawValue, forKey: Keys.launchMode.rawValue)
    }
    
    func loadLaunchMode() -> String? {
        defaults.string(forKey: Keys.launchMode.rawValue)
    }
    
    func loadRefreshInterval() -> Double? {
        defaults.value(forKey: Keys.refreshInterval.rawValue) as? Double
    }
    
    func loadShowFoldersFirst() -> Bool {
        defaults.bool(forKey: Keys.showFoldersFirst.rawValue)
    }
    
    func saveShowFoldersFirst(_ value: Bool) {
        defaults.set(value, forKey: Keys.showFoldersFirst.rawValue)
    }
    
    func loadHasShownLauncher() -> Bool {
        defaults.bool(forKey: Keys.hasShownLauncher.rawValue)
    }
    
    func saveHasShownLauncher(_ value: Bool) {
        defaults.set(value, forKey: Keys.hasShownLauncher.rawValue)
    }
    
    // MARK: - Glow Settings
    
    func saveGlowEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.glowEnabled.rawValue)
    }
    
    func loadGlowEnabled() -> Bool {
        if defaults.object(forKey: Keys.glowEnabled.rawValue) == nil { return true }
        return defaults.bool(forKey: Keys.glowEnabled.rawValue)
    }
    
    func saveGlowColor(_ hex: String) {
        defaults.set(hex, forKey: Keys.glowColor.rawValue)
    }
    
    func loadGlowColor() -> String? {
        defaults.string(forKey: Keys.glowColor.rawValue)
    }
    
    func saveGlowIntensity(_ intensity: Double) {
        defaults.set(intensity, forKey: Keys.glowIntensity.rawValue)
    }
    
    func loadGlowIntensity() -> Double? {
        defaults.value(forKey: Keys.glowIntensity.rawValue) as? Double
    }
    
    func saveGlowWidth(_ width: Double) {
        defaults.set(width, forKey: Keys.glowWidth.rawValue)
    }
    
    func loadGlowWidth() -> Double? {
        if defaults.object(forKey: Keys.glowWidth.rawValue) == nil { return GlowMetrics.glowWidthDefault }
        return defaults.value(forKey: Keys.glowWidth.rawValue) as? Double
    }
    
    func saveCurrentFolderId(_ folderId: String?) {
        defaults.set(folderId, forKey: Keys.currentFolderId.rawValue)
    }
    
    func saveRefreshInterval(_ interval: Double) {
        defaults.set(interval, forKey: Keys.refreshInterval.rawValue)
    }
    
    func saveIconSize(_ size: String) {
        defaults.set(size, forKey: Keys.iconSize.rawValue)
    }
    
    func saveSortOption(_ option: String) {
        defaults.set(option, forKey: Keys.sortOption.rawValue)
    }
    
    func saveCustomOrder(_ order: [String: Int]) {
        if let data = try? JSONEncoder().encode(order) {
            defaults.set(data, forKey: Keys.customOrder.rawValue)
        }
    }
    
    // MARK: - Font Settings
    
    func loadFontFamily() -> String? {
        defaults.string(forKey: Keys.fontFamily.rawValue)
    }
    
    func saveFontFamily(_ family: String) {
        defaults.set(family, forKey: Keys.fontFamily.rawValue)
    }
    
    func loadFontSize() -> Double? {
        defaults.value(forKey: Keys.fontSize.rawValue) as? Double
    }
    
    func saveFontSize(_ size: Double) {
        defaults.set(size, forKey: Keys.fontSize.rawValue)
    }
    
    func loadFontWeight() -> String? {
        defaults.string(forKey: Keys.fontWeight.rawValue)
    }
    
    func saveFontWeight(_ weight: String) {
        defaults.set(weight, forKey: Keys.fontWeight.rawValue)
    }
    
    // MARK: - App Management
    
    func loadHiddenApps() -> Set<String>? {
        guard let data = defaults.data(forKey: Keys.hiddenAppPaths.rawValue) else { return nil }
        return try? JSONDecoder().decode(Set<String>.self, from: data)
    }
    
    func saveHiddenApps(_ paths: Set<String>) {
        if let data = try? JSONEncoder().encode(paths) {
            defaults.set(data, forKey: Keys.hiddenAppPaths.rawValue)
        }
    }
    
    func loadCustomDirectories() -> [String]? {
        defaults.stringArray(forKey: Keys.customDirectories.rawValue)
    }
    
    func saveCustomDirectories(_ dirs: [String]) {
        defaults.set(dirs, forKey: Keys.customDirectories.rawValue)
    }

    /// F-4: security-scoped bookmarks for custom directories, keyed by the directory's `path` at
    /// the time it was added. The app is currently unsandboxed, so the plain path in
    /// `customDirectories` is sufficient on its own — these bookmarks exist so access survives if
    /// sandboxing is ever enabled later, instead of silently breaking on relaunch.
    func loadCustomDirectoryBookmarks() -> [String: Data]? {
        defaults.dictionary(forKey: Keys.customDirectoryBookmarks.rawValue) as? [String: Data]
    }

    func saveCustomDirectoryBookmarks(_ bookmarks: [String: Data]) {
        defaults.set(bookmarks, forKey: Keys.customDirectoryBookmarks.rawValue)
    }

    func loadFolders() -> [AppFolder]? {
        guard let data = defaults.data(forKey: Keys.folders.rawValue) else { return nil }
        return try? JSONDecoder().decode([AppFolder].self, from: data)
    }
    
    func saveFolders(_ folders: [AppFolder]) {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: Keys.folders.rawValue)
        }
     }
    
    func loadRecentAppsEnabled() -> Bool {
        if defaults.object(forKey: Keys.recentAppsEnabled.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.recentAppsEnabled.rawValue)
    }
    
    func saveRecentAppsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.recentAppsEnabled.rawValue)
    }
    
    func loadPressFeedbackEnabled() -> Bool {
        if defaults.object(forKey: Keys.pressFeedbackEnabled.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.pressFeedbackEnabled.rawValue)
    }

    func savePressFeedbackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.pressFeedbackEnabled.rawValue)
    }

    func loadShowHiddenApps() -> Bool {
        if defaults.object(forKey: Keys.showHiddenApps.rawValue) == nil {
            return false
        }
        return defaults.bool(forKey: Keys.showHiddenApps.rawValue)
    }

    func saveShowHiddenApps(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.showHiddenApps.rawValue)
    }
    
    // MARK: - Opacity Settings
    
    func saveOverlayOpacity(_ opacity: Double) {
        defaults.set(opacity, forKey: Keys.overlayOpacity.rawValue)
    }
    
    func loadOverlayOpacity() -> Double? {
        defaults.value(forKey: Keys.overlayOpacity.rawValue) as? Double
    }
    
    func loadLaunchAnimationDirection() -> String? {
        defaults.string(forKey: Keys.launchAnimationDirection.rawValue)
    }
    
    func saveLaunchAnimationDirection(_ direction: String) {
        defaults.set(direction, forKey: Keys.launchAnimationDirection.rawValue)
    }

    func loadLaunchAnimationEnabled() -> Bool {
        if defaults.object(forKey: Keys.launchAnimationEnabled.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.launchAnimationEnabled.rawValue)
    }
    
    func saveLaunchAnimationEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.launchAnimationEnabled.rawValue)
    }
    
    func loadShowInDock() -> Bool {
        if defaults.object(forKey: Keys.showInDock.rawValue) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.showInDock.rawValue)
    }
    
    func saveShowInDock(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.showInDock.rawValue)
    }

    // MARK: - Presentation Mode + Tint Settings

    func savePresentationMode(_ mode: String) {
        defaults.set(mode, forKey: Keys.presentationMode.rawValue)
    }

    func loadPresentationMode() -> String? {
        defaults.string(forKey: Keys.presentationMode.rawValue)
    }

    func saveTintColor(_ hex: String) {
        defaults.set(hex, forKey: Keys.tintColor.rawValue)
    }

    func loadTintColor() -> String? {
        defaults.string(forKey: Keys.tintColor.rawValue)
    }

    func saveTintStrength(_ strength: Double) {
        defaults.set(strength, forKey: Keys.tintStrength.rawValue)
    }

    func loadTintStrength() -> Double? {
        defaults.value(forKey: Keys.tintStrength.rawValue) as? Double
    }
}
