import Foundation

// MARK: - Scan Metrics

enum ScanMetrics {
    static let maxRecentApps = 8
    static let maxStoredRecentApps = 50
    static let recentAppsRetentionSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days
    static let searchDebounceNanoseconds: UInt64 = 150_000_000 // 150ms
    static let priorityIconLoadCount = 60
    static let newlyInstalledWindowSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    /// Fallback rescan interval when none has been stored. Named because it was previously
    /// spelled out at each use site and one of them drifted: the backup exporter defaulted to
    /// 30 s, so a backup taken before the user ever touched the setting recorded an interval ten
    /// times more aggressive than the app's own, and restoring it applied that.
    static let refreshIntervalDefault: TimeInterval = 300 // 5 minutes

    /// The bounds of the Settings picker's four options (5 min / 15 min / 30 min / 1 hour).
    /// A restored backup or a direct `PreferencesStore` write can carry any `TimeInterval` the
    /// picker itself never offers — clamping to this range at load keeps an interval like 0.001s
    /// (rescan timer firing ~1000×/sec) from ever reaching the live scan scheduler.
    static let refreshIntervalMin: TimeInterval = 300
    static let refreshIntervalMax: TimeInterval = 3600

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

    /// Ratio of the "recently updated" sparkles badge's point size to the app icon size, so the
    /// badge scales with the user's chosen icon size (Settings > Icon Size) instead of staying a
    /// fixed size that reads as tiny on Extra Large icons or oversized on Small ones. 0.21875
    /// matches the previous fixed 14pt badge at the Medium (64pt) icon size.
    static let recentlyUpdatedBadgeSymbolSizeRatio: CGFloat = 0.21875

    /// Ratio of the "running" indicator dot's diameter to the app icon size, same rationale as
    /// `recentlyUpdatedBadgeSymbolSizeRatio` above. 0.15625 matches the previous fixed 10pt dot
    /// at the Medium (64pt) icon size.
    static let runningDotSizeRatio: CGFloat = 0.15625
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
    /// How long the Settings "Apps refreshed" toast stays up: long enough to read a one-line
    /// confirmation, short enough not to linger over the controls beneath it.
    static let refreshToastNanoseconds: UInt64 = 2_000_000_000
    /// Drag-to-Dock pointer poll: 30 Hz tracks a hand-speed drag to the edge without a visible lag
    /// before the launcher fades, and the timer only runs while a drag is in flight.
    static let dragPollSeconds: TimeInterval = 1.0 / 30.0
    /// Pointer within this many points of a screen edge fades the launcher so the Dock underneath can
    /// take the drop (the Dock sits on the left, right or bottom edge).
    static let dockRevealEdgePoints: CGFloat = 6
    /// Back inside this distance the launcher returns. Wider than the reveal distance so the pointer
    /// riding the Dock's edge doesn't flicker the windows.
    static let dockRestoreEdgePoints: CGFloat = 120
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

// MARK: - Scroll Edge Effect Metrics

enum ScrollEdgeMetrics {
    /// Opacity of a row that has just reached the viewport edge. Not 0: the row is still partly
    /// on screen, and a fully transparent row looks like a rendering gap rather than a taper.
    static let minOpacity: Double = 0.25
    /// Scale at the edge. A ~12% shrink reads as the row receding without the neighbouring
    /// column gaps visibly opening up.
    static let minScale: Double = 0.88
    /// Blur radius (pt) at the edge. Kept small: the blur is an offscreen pass per affected cell,
    /// and only the one row inside each transition band pays it.
    static let maxBlurRadius: Double = 6
}

// MARK: - Drag Auto-Scroll Metrics

enum DragScrollMetrics {
    /// Height of the strip at the grid's top and bottom that scrolls while an icon is dragged there:
    /// about one icon row, so the pointer is near a row's worth of content it can't yet reach.
    static let edgeBandPoints: CGFloat = 110
    /// Top speed at the very edge: roughly three grid rows a second, fast enough to cross a long
    /// library in a few seconds without overshooting a folder on a short one.
    static let maxPointsPerSecond: CGFloat = 900
}

// MARK: - Icon Metrics

enum IconMetrics {
    static let iconSizeSmall: CGFloat = 48
    static let iconSizeMedium: CGFloat = 64
    static let iconSizeLarge: CGFloat = 80
    static let iconSizeExtraLarge: CGFloat = 100
    /// Pixel size icons are rasterized to, shared by every icon-size setting.
    ///
    /// Must cover the largest size at 2x or the biggest icons render soft: Extra Large is 100 pt,
    /// which is 200 px on a Retina display, and this was 160. Sized to the largest setting rather
    /// than per-setting because the on-disk cache is keyed by path and appearance, not by size —
    /// one bitmap serves every setting, and downscaling a larger source is free at draw time
    /// whereas upscaling a smaller one is what was visible.
    static let iconRasterPixelSizePx = Int(iconSizeExtraLarge * 2)

    /// Ceiling on concurrent icon decodes within one `loadMissingIcons` batch.
    ///
    /// Unbounded, a full-library batch (theme toggle, "Refresh Now") rasterizes every icon
    /// simultaneously — hundreds of 200×200×4-byte bitmaps plus ImageIO buffers at once, a
    /// transient multi-hundred-MB spike. Twelve in flight keeps first-launch icon fill fast
    /// (the performance tests require ≫serial) while bounding that spike.
    static let maxConcurrentIconDecodes = 12

    /// Total-cost ceiling of `IconCacheManager`'s in-memory icon cache, in *pixels* of source
    /// bitmap (width × height), so the unit is appearance- and color-depth-independent.
    ///
    /// One rasterized icon is `iconRasterPixelSizePx²` = 40,000 units, so this holds every
    /// icon of a 500-app library in both light and dark variants (40,000 × 2 × 500 = 40M)
    /// with room to spare — an eviction is an exceptional event, not the normal mode. The
    /// real memory this maps to is bounded (≤ 40M pixels × 4 B ≈ 160 MB worst case, typically
    /// far less, since most app icons compress to a fraction of a full raster at rest).
    static let memoryCachePixelLimit = 40_000_000

    /// Total-cost ceiling of `IconService`'s folder-icon cache, in pixels. Folder icons are
    /// 120×120 = 14,400, so this holds ~340 folders — far beyond any realistic library — while
    /// still preventing unbounded growth if a library holds thousands of folders.
    static let folderIconCachePixelLimit = 5_000_000
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

// MARK: - Activation Metrics

enum ActivationMetrics {
    /// How close (in points) the pointer must be to a screen corner to count as "in the corner".
    /// Two points is what the system's own hot corners use in practice: the pointer physically
    /// cannot go past the display edge, so a thin zone is enough, and a wider one would fire while
    /// the user is just reaching for a menu-bar or Dock item near the corner.
    static let hotCornerZonePoints: CGFloat = 2

    /// Pointer must rest in the corner this long before the launcher opens, so sweeping across a
    /// corner on the way elsewhere doesn't trigger it. Long enough to filter flicks, short enough
    /// to feel immediate.
    static let hotCornerDwell: TimeInterval = 0.25

    /// How often the pointer is sampled while MacMuster is the active app. The global `mouseMoved`
    /// monitor delivers nothing in that state (macOS only reports events bound for *other* apps),
    /// and MacMuster stays active after its launcher hides, so the corner would go dead. 0.1 s is
    /// well under the dwell time, so detection is not noticeably delayed, and the poll runs only in
    /// that state: it is stopped as soon as another app is active and the monitor takes over.
    static let hotCornerPollInterval: TimeInterval = 0.1

    /// Default global shortcut: Control+Option+Space (virtual key code 49). Chosen because ⌘Space
    /// (Spotlight), ⌥⌘Space (Finder search) and ⌥Space (common third-party launchers) are taken.
    static let defaultHotkeyKeyCode = 49
    /// `NSEvent.ModifierFlags` raw bits for Control (1 << 18) | Option (1 << 19); spelled out because
    /// this file imports only Foundation.
    static let defaultHotkeyModifiers = (1 << 18) | (1 << 19)
}

// MARK: - Import Limits

/// Bounds on a backup or Launchie export the user opens (SEC-7). The file is untrusted: without
/// these a multi-gigabyte file is read whole, and an archive of millions of tiny valid icon keys
/// creates millions of cache files. Each is a multiple of what a very large real library produces
/// (a backup with ~900 icons is ~25 MB; a few thousand apps), so a legitimate file never trips one.
enum ImportLimits {
    /// Largest file read at all. ~5× a typical full backup with its icon pack.
    static let maxFileBytes = 128 * 1_048_576
    static let maxFolders = 2_000
    /// Applies to each of: total folder members, hidden apps, custom-order entries, known mtimes.
    static let maxAppPaths = 50_000
    /// Icon pack files (a PNG plus its `.meta` per app and appearance).
    static let maxIconPackEntries = 20_000
    static let maxIconPackBytes = 256 * 1_048_576
}

// MARK: - Wizard Metrics

enum WizardMetrics {
    /// Cap on how large an `Info.plist` the smart-folder bundle reader will load. Real Info.plist
    /// files are a few kilobytes at most; this exists only to refuse a pathologically large (or
    /// malicious) plist *before* reading it, so a hostile bundle can't force a multi-megabyte
    /// allocation during classification. A megabyte is far above anything legitimate, so it never
    /// truncates a real file — it is a guardrail, not a format constraint.
    static let maxInfoPlistReadBytes = 1_048_576 // 1 MiB

    // MARK: Window

    /// The wizard window is a fixed-size panel: large enough to list the 9 categories with their
    /// counts and a preview of assignments, but not resizable — the content is a simple, known
    /// set of steps, so a fixed footprint avoids layout thrash. 560×520 fits that comfortably on
    /// a 1280×800 display.
    static let windowWidth: CGFloat = 560
    static let windowHeight: CGFloat = 520

    // MARK: Animation

    /// The animation is only offered when the machine can spare the work: at least this many
    /// active cores and not thermally pressed. Four cores is the floor where animating a couple
    /// hundred lightweight dots off the main render path is comfortably cheap; below that the
    /// preview (which always shows) is the better use of the frame budget.
    static let minAnimatedCores = 4
    /// Cap on how many app dots actually animate. Beyond this the extras simply fade in after the
    /// animation; a few hundred animated dots is fine, but a full library of 2,000+ would not be.
    static let maxAnimatedApps = 120
    /// Per-app travel time once its (staggered) animation begins. Under a second keeps the whole
    /// sequence snappy even with the stagger across a large batch.
    static let animationDuration: Double = 0.9
    /// Per-app start offset, so the dots move in a wave rather than all at once. Small enough that
    /// the last of ~120 dots still finishes within a couple of seconds of the first.
    static let animationStagger: Double = 0.02
    /// Fraction of an app's travel spent moving from its loose position to its folder's cluster
    /// center; the rest settles it into its final slot. Splitting the motion reads as "grouping"
    /// rather than a single straight glide.
    static let animationClusterPhase: Double = 0.4
}
