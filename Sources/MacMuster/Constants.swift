import Foundation

// MARK: - App Metrics Constants

enum AppMetrics {
    // F-3: the Recent/Most Used UI never shows more than 8 entries, so retaining
    // up to 50 launch records for 14 days was far more launch history than the app ever needed —
    // trimmed to a small multiple of the display limit (room for ranking to stay stable as apps cycle
    // in/out) and a shorter retention window.
    static let maxRecentApps = 8
    static let maxStoredRecentApps = 50
    static let recentAppsRetentionSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days
    static let searchDebounceNanoseconds: UInt64 = 150_000_000 // 150ms

    // Roughly covers the largest first screenful (kMaxColumnCount=10 × ~6 visible rows) so the
    // initial icon batch finishes fast; the rest backfills afterward without blocking the grid.
    static let priorityIconLoadCount = 60
    static let newlyInstalledWindowSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    // MARK: - Overlay Window Metrics

    static let windowAnimationDelay: TimeInterval = 0.1
    static let windowMinWidth: CGFloat = 900
    static let windowMinHeight: CGFloat = 700

    // MARK: - Launch Animation Metrics

    static let launchZoomOutStartScale: CGFloat = 1.25
    static let launchZoomOutDuration: TimeInterval = 0.8

    // MARK: - Settings Window Metrics

    static let settingsWindowWidth: CGFloat = 820
    static let settingsWindowHeight: CGFloat = 560
    static let settingsWindowMinWidth: CGFloat = 700
    static let settingsWindowMinHeight: CGFloat = 480
    static let settingsWindowMaxWidth: CGFloat = 1400
    static let settingsWindowMaxHeight: CGFloat = 1000

    // MARK: - Glow Metrics

    static let glowEnabledDefault: Bool = true
    static let glowColorDefault: String = "#ffffff"
    static let glowIntensityDefault: Double = 0.3
    static let glowWidthDefault: Double = 40.0
    static let glowWidthMin: Double = 5.0
    static let glowWidthMax: Double = 40.0

    // MARK: - Opacity Metrics

    static let overlayOpacityDefault: Double = 0.95
    static let overlayOpacityMin: Double = 0.1
    static let overlayOpacityMax: Double = 1.0
    static let overlayOpacityStep: Double = 0.05

    // MARK: - ContentView Layout Metrics

    static let gridSpacing: CGFloat = 20
    static let appIconPadding: CGFloat = 8
    static let appIconCornerRadius: CGFloat = 10
    static let appIconHoverScale: CGFloat = 1.08
    static let sectionViewPadding: CGFloat = 10
    static let searchPadding: CGFloat = 10
    static let searchCornerRadius: CGFloat = 8
    static let categoryTabPaddingHorizontal: CGFloat = 10
    static let categoryTabPaddingVertical: CGFloat = 5
    static let categoryTabCornerRadius: CGFloat = 6
    static let settingsButtonSize: CGFloat = 28

    // MARK: - Layout Metrics

    static let minColumnCount = 4
    static let maxColumnCount = 10
    static let iconSizeSmall: CGFloat = 48
    static let iconSizeMedium: CGFloat = 64
    static let iconSizeLarge: CGFloat = 80
    static let iconRasterPixelSizePx = 160

    // MARK: - SettingsContentView Layout Metrics

    static let sidebarWidth: CGFloat = 200
    static let sidebarHeaderPaddingHorizontal: CGFloat = 20
    static let sidebarHeaderPaddingVertical: CGFloat = 16
    static let sidebarSectionPaddingHorizontal: CGFloat = 12
    static let sidebarSectionPaddingVertical: CGFloat = 7
    static let sidebarSectionCornerRadius: CGFloat = 6
    static let sidebarSectionSpacing: CGFloat = 4
    static let sidebarVersionPaddingHorizontal: CGFloat = 16
    static let sidebarVersionPaddingBottom: CGFloat = 12
    static let headerPaddingHorizontal: CGFloat = 28
    static let headerPaddingVertical: CGFloat = 18
    static let contentPaddingHorizontal: CGFloat = 28
    static let contentPaddingVertical: CGFloat = 20
    static let footerPaddingHorizontal: CGFloat = 28
    static let footerPaddingVertical: CGFloat = 14
    static let sectionSpacing: CGFloat = 28
    static let sectionContentSpacing: CGFloat = 14
    static let sectionContentPadding: CGFloat = 14
    static let sectionContentCornerRadius: CGFloat = 10
    static let togglePaddingTop: CGFloat = 14
    static let errorPaddingHorizontal: CGFloat = 14
    static let errorPaddingBottom: CGFloat = 14
    static let buttonSpacing: CGFloat = 6
    static let labelSpacing: CGFloat = 14
    static let labelSpacingVertical: CGFloat = 4
    static let hiddenAppsListPaddingVertical: CGFloat = 20
}
