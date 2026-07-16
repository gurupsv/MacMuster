import Foundation
import SwiftUI
import Observation

/// Manages appearance, layout, and glow settings. Each setter hand-persists to UserDefaults.
@MainActor
@Observable
class SettingsAppearance {
    var fontFamily: String = "SF Pro" {
        didSet { PreferencesStore.shared.saveFontFamily(fontFamily) }
    }
    var fontSize: Double = 14.0 {
        didSet { PreferencesStore.shared.saveFontSize(fontSize) }
    }
    var fontWeight: String = "normal" {
        didSet { PreferencesStore.shared.saveFontWeight(fontWeight) }
    }
    var columnCount: Int = 4 {
        didSet { PreferencesStore.shared.saveColumnCount(columnCount) }
    }
    var iconSize: IconSize = .medium {
        didSet { PreferencesStore.shared.saveIconSize(iconSize.rawValue) }
    }
    var launchMode: LaunchMode = .window {
        didSet {
            PreferencesStore.shared.saveLaunchMode(launchMode)
            OverlayWindowManager.shared.applyCurrentMode()
        }
    }
    var glowEnabled: Bool = true {
        didSet { PreferencesStore.shared.saveGlowEnabled(glowEnabled) }
    }
    var glowColor: Color = .white {
        didSet { PreferencesStore.shared.saveGlowColor(getHexColorValue()) }
    }
    var glowIntensity: Double = 0.3 {
        didSet {
            if glowIntensity < 0 { glowIntensity = 0 }
            if glowIntensity > 1 { glowIntensity = 1 }
            PreferencesStore.shared.saveGlowIntensity(glowIntensity)
        }
    }
    var glowWidth: Double = 40.0 {
        didSet {
            if glowWidth < 5 { glowWidth = 5 }
            if glowWidth > 40 { glowWidth = 40 }
            PreferencesStore.shared.saveGlowWidth(glowWidth)
        }
    }
    var overlayOpacity: Double = GlowMetrics.overlayOpacityDefault {
        didSet {
            if overlayOpacity < GlowMetrics.overlayOpacityMin { overlayOpacity = GlowMetrics.overlayOpacityMin }
            if overlayOpacity > GlowMetrics.overlayOpacityMax { overlayOpacity = GlowMetrics.overlayOpacityMax }
            PreferencesStore.shared.saveOverlayOpacity(overlayOpacity)
        }
    }
    var showRecentApps: Bool = true {
        didSet { RecentAppsTracker.shared.isEnabled = showRecentApps; PreferencesStore.shared.saveRecentAppsEnabled(showRecentApps) }
    }
    var pressFeedbackEnabled: Bool = true {
        didSet { PreferencesStore.shared.savePressFeedbackEnabled(pressFeedbackEnabled) }
    }
    var shouldReduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var hasShownLauncher: Bool = false {
        didSet { PreferencesStore.shared.saveHasShownLauncher(hasShownLauncher) }
    }
    enum LaunchAnimationDirection: String, CaseIterable {
        case zoomOut = "zoomOut"
        case zoomIn = "zoomIn"

        var displayName: String {
            switch self {
            case .zoomOut: "Zoom Out (starts expanded, shrinks to normal)"
            case .zoomIn: "Zoom In (starts small, grows to normal)"
            }
        }
    }

    var launchAnimationDirection: LaunchAnimationDirection = .zoomOut {
        didSet { PreferencesStore.shared.saveLaunchAnimationDirection(launchAnimationDirection.rawValue) }
    }
    var launchAnimationEnabled: Bool = true {
        didSet { PreferencesStore.shared.saveLaunchAnimationEnabled(launchAnimationEnabled) }
    }
    var showFoldersFirst: Bool = false {
        didSet { PreferencesStore.shared.saveShowFoldersFirst(showFoldersFirst) }
    }
    var refreshInterval: TimeInterval = 300 {
        didSet { PreferencesStore.shared.saveRefreshInterval(refreshInterval) }
    }

    enum PresentationMode: String, CaseIterable {
        case glass = "Glass"
        case sheet = "Sheet"

        var displayName: String {
            switch self {
            case .glass: "Glass (frosted translucent blur)"
            case .sheet: "Sheet (opaque solid background)"
            }
        }
    }

    var presentationMode: PresentationMode = .glass {
        didSet { PreferencesStore.shared.savePresentationMode(presentationMode.rawValue) }
    }

    var tintColor: Color = .blue {
        didSet { PreferencesStore.shared.saveTintColor(getHexColorValue()) }
    }

    var tintStrength: Double = 0.0 {
        didSet {
            if tintStrength < 0 { tintStrength = 0 }
            if tintStrength > 1 { tintStrength = 1 }
            PreferencesStore.shared.saveTintStrength(tintStrength)
        }
    }

    init() {
        loadPersistedPreferences()
        showRecentApps = PreferencesStore.shared.loadRecentAppsEnabled()
        pressFeedbackEnabled = PreferencesStore.shared.loadPressFeedbackEnabled()
        if let opacityRaw = PreferencesStore.shared.loadOverlayOpacity() {
            overlayOpacity = max(GlowMetrics.overlayOpacityMin, min(GlowMetrics.overlayOpacityMax, opacityRaw))
        }
        if let dirRaw = PreferencesStore.shared.loadLaunchAnimationDirection() {
            launchAnimationDirection = LaunchAnimationDirection(rawValue: dirRaw) ?? .zoomOut
        }
        launchAnimationEnabled = PreferencesStore.shared.loadLaunchAnimationEnabled()
    }

    private func loadPersistedPreferences() {
        if let cols = PreferencesStore.shared.loadColumnCount() { columnCount = max(1, cols) }
        if let font = PreferencesStore.shared.loadFontFamily() { fontFamily = font }
        if let size = PreferencesStore.shared.loadFontSize() {
            let validSizes: [Double] = [12.0, 14.0, 16.0, 18.0]
            fontSize = validSizes.contains(size) ? size : 14.0
        }
        if let weight = PreferencesStore.shared.loadFontWeight() { fontWeight = weight }
        if let iconRaw = PreferencesStore.shared.loadIconSize() { iconSize = IconSize(rawValue: iconRaw) ?? .medium }
        if let interval = PreferencesStore.shared.loadRefreshInterval() { refreshInterval = interval }
        showFoldersFirst = PreferencesStore.shared.loadShowFoldersFirst()
        hasShownLauncher = PreferencesStore.shared.loadHasShownLauncher()
        glowEnabled = PreferencesStore.shared.loadGlowEnabled()
        if let glowColorHex = PreferencesStore.shared.loadGlowColor() { glowColor = parseColor(from: glowColorHex) }
        if let glowIntensityRaw = PreferencesStore.shared.loadGlowIntensity() { glowIntensity = max(0, min(1, glowIntensityRaw)) }
        if let glowWidthRaw = PreferencesStore.shared.loadGlowWidth() { glowWidth = max(GlowMetrics.glowWidthMin, min(GlowMetrics.glowWidthMax, glowWidthRaw)) }
        if let modeRaw = PreferencesStore.shared.loadPresentationMode() { presentationMode = PresentationMode(rawValue: modeRaw) ?? .glass }
        if let tintHex = PreferencesStore.shared.loadTintColor() { tintColor = parseColor(from: tintHex) }
        if let strengthRaw = PreferencesStore.shared.loadTintStrength() { tintStrength = max(0, min(1, strengthRaw)) }
        if let launchRaw = PreferencesStore.shared.loadLaunchMode() { launchMode = LaunchMode(rawValue: launchRaw) ?? .window }
    }

    private func parseColor(from hexString: String) -> Color {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "white": return .white
        case "black": return .black
        default: break
        }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
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

    func setFontFamily(_ family: String) { fontFamily = family }
    func setFontWeight(_ weight: String) { fontWeight = weight }
    func setColumnCount(_ count: Int) { columnCount = count }
    func setIconSize(_ size: IconSize) { iconSize = size }
    func setRefreshInterval(_ interval: TimeInterval) { refreshInterval = interval }

    func tintedBackgroundColor() -> NSColor {
        guard tintStrength > 0 else { return NSColor.black.withAlphaComponent(overlayOpacity) }
        let nsTint = NSColor(tintColor)
        guard let rgb = nsTint.usingColorSpace(.sRGB) else { return NSColor.black.withAlphaComponent(overlayOpacity) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return NSColor(red: r * tintStrength, green: g * tintStrength, blue: b * tintStrength, alpha: a * tintStrength)
    }

    private func getHexColorValue() -> String {
        let nsColor = NSColor(glowColor)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#ffffff" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
