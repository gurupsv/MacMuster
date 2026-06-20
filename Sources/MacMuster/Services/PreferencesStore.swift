import Foundation
import SwiftUI

/// Handles persistence of application settings and preferences using UserDefaults.
@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()
    private let defaults = UserDefaults.standard
    
    private enum Keys: String {
        case hiddenAppPaths = "hiddenAppPaths"
        case columnCount = "columnCount"
        case currentFolderId = "currentFolderId"
        case customOrder = "customOrder"
        case sortOption = "sortOption"
        case iconSize = "iconSize"
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
        case folders = "appFolders"
     case pressFeedbackEnabled = "pressFeedbackEnabled"
     case recentAppsEnabled = "recentAppsEnabled"
    }
    
    private init() {
        // Set default for recentAppsEnabled if not present
        if defaults.object(forKey: Keys.recentAppsEnabled.rawValue) == nil {
            defaults.set(true, forKey: Keys.recentAppsEnabled.rawValue)
        }
        // Set default for pressFeedbackEnabled if not present
        if defaults.object(forKey: Keys.pressFeedbackEnabled.rawValue) == nil {
            defaults.set(true, forKey: Keys.pressFeedbackEnabled.rawValue)
        }
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
        defaults.bool(forKey: Keys.glowEnabled.rawValue)
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
        defaults.value(forKey: Keys.glowWidth.rawValue) as? Double
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
}
