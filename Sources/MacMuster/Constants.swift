import Foundation

// MARK: - App Version

enum AppVersion {
    static let current = "1.0.0"
    static let build: Int = {
        let n = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
        return n ?? 0
    }()
}

// MARK: - Scan Metrics

enum ScanMetrics {
    static let maxRecentApps = 8
    static let maxStoredRecentApps = 50
    static let recentAppsRetentionSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days
    static let searchDebounceNanoseconds: UInt64 = 150_000_000 // 150ms
    static let priorityIconLoadCount = 60
    static let newlyInstalledWindowSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    /// How long a watched directory must stay quiet before a filesystem-triggered rescan runs.
    /// An install is a long burst of writes; scanning mid-copy would surface a partial bundle.
    /// Long enough to let a copy finish, short enough that a new app appears while the user is
    /// still looking at the installer.
    static let installSettleNanoseconds: UInt64 = 1_000_000_000 // 1 s

    /// How often `scheduleFileSystemRescan` re-checks `isScanning` when a rescan it wants to run
    /// finds one already in flight. Deliberately much shorter than `installSettleNanoseconds` —
    /// that constant is a burst-coalescing delay, unrelated to how quickly a finished scan should
    /// be noticed, and a directory add/remove reuses this wait to stay snappy rather than being
    /// dropped outright.
    static let scanCompletionPollNanoseconds: UInt64 = 100_000_000 // 100 ms
}

// MARK: - Update Metrics

enum UpdateMetrics {
    /// How long an app stays badged as "recently updated" after its bundle mtime jumped.
    /// Matches the `newlyInstalledWindowSeconds` window so the two badges (newly installed vs
    /// recently updated) retire on the same cadence — a user who notices one expects the other
    /// to behave the same way.
    static let recentlyUpdatedBadgeSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    /// A mtime delta below this is ignored as noise (subsecond churn from filesystem metadata
    /// touching that isn't a real update). Mirrors `IconCacheManager.datesEqualIgnoringSubsecond`,
    /// which compares mtimes at second granularity for the same reason.
    static let mtimeDeltaEpsilonSeconds: TimeInterval = 1.0

    /// Point size of the "recently updated" sparkles badge overlay.
    static let recentlyUpdatedBadgeSymbolSize: CGFloat = 11

    /// Diameter of the "running" indicator dot overlay.
    static let runningDotSize: CGFloat = 8
}

// MARK: - Launch Metrics

enum LaunchMetrics {
    /// Duration between press feedback and dismissal. Long enough for the 0.2 s press animation
    /// to read, short enough to feel instant. Set to 0 when shouldReduceMotion is on.
    static let dismissFeedbackNanoseconds: UInt64 = 120_000_000 // 120 ms
}

// MARK: - Window Metrics

enum WindowMetrics {
    // Overlay window
    static let windowAnimationDelay: TimeInterval = 0.1
    static let windowMinWidth: CGFloat = 900
    static let windowMinHeight: CGFloat = 700

    // Launch animation
    static let launchZoomOutStartScale: CGFloat = 2.0
    static let launchZoomInEndScale: CGFloat = 0.5
    static let launchZoomOutDuration: TimeInterval = 0.5

    // Settings window
    static let settingsWindowWidth: CGFloat = 820
    static let settingsWindowHeight: CGFloat = 560
    static let settingsWindowMinWidth: CGFloat = 700
    static let settingsWindowMinHeight: CGFloat = 480
    static let settingsWindowMaxWidth: CGFloat = 1400
    static let settingsWindowMaxHeight: CGFloat = 1000
}

// MARK: - Glow Metrics

enum GlowMetrics {
    static let glowEnabledDefault: Bool = true
    static let glowColorDefault: String = "#ffffff"
    static let glowIntensityDefault: Double = 0.3
    static let glowWidthDefault: Double = 40.0
    static let glowWidthMin: Double = 5.0
    static let glowWidthMax: Double = 40.0
    
    static let overlayOpacityDefault: Double = 0.95
    static let overlayOpacityMin: Double = 0.1
    static let overlayOpacityMax: Double = 1.0
    static let overlayOpacityStep: Double = 0.05
}

// MARK: - Icon Metrics

enum IconMetrics {
    static let iconSizeSmall: CGFloat = 48
    static let iconSizeMedium: CGFloat = 64
    static let iconSizeLarge: CGFloat = 80
    static let iconSizeExtraLarge: CGFloat = 100
    static let iconRasterPixelSizePx = 160
}

// MARK: - Layout Metrics

enum LayoutMetrics {
    static let minColumnCount = 4
    static let maxColumnCount = 10
    
    // ContentView layout
    static let gridSpacing: CGFloat = 20
    static let appIconPadding: CGFloat = 1
    static let appIconCornerRadius: CGFloat = 10
    static let appIconHoverScale: CGFloat = 1.2
    static let folderTileCornerRadiusRatio: CGFloat = 0.22
    static let folderTileInsetRatio: CGFloat = 0.10
    static let folderTileStrokeWidth: CGFloat = 1
    static let sectionViewPadding: CGFloat = 1
    static let searchPadding: CGFloat = 1
    static let searchCornerRadius: CGFloat = 8
    // Category tabs sit directly on the launcher background, and that background dismisses the
    // window when clicked. A near-miss therefore costs the user the whole launcher, so these are
    // sized for a forgiving target rather than the tightest pill that fits the text.
    static let categoryTabPaddingHorizontal: CGFloat = 14
    static let categoryTabPaddingVertical: CGFloat = 7
    static let categoryTabCornerRadius: CGFloat = 6
    /// Dead band around the tab strip that absorbs clicks instead of letting them dismiss.
    static let categoryTabStripHitPadding: CGFloat = 6

    // Hover/active feedback shared by the category tabs and the top-right icon buttons, so the
    // launcher's controls all respond to the pointer in the same visual language.
    /// Tint under the pointer for a control that is not already highlighted.
    static let controlHoverOpacity: Double = 0.12
    /// Tint for a control in a persistent "on" state, e.g. search while the field is open.
    static let controlActiveOpacity: Double = 0.15
    static let controlHoverAnimationDuration: TimeInterval = 0.12
    static let settingsButtonSize: CGFloat = 32
}

// MARK: - SettingsContentView Layout Metrics

enum SettingsLayoutMetrics {
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
