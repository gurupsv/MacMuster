import AppKit
import SwiftUI

// MARK: - AppModel Constants

let kMaxRecentApps = 8
// F-3: the Recent/Most Used UI never shows more than `kMaxRecentApps` (8) entries, so retaining
// up to 500 launch records for 30 days was far more launch history than the app ever needed —
// trimmed to a small multiple of the display limit (room for ranking to stay stable as apps cycle
// in/out) and a shorter retention window.
let kMaxStoredRecentApps = 50
let kRecentAppsRetentionSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days
let kSearchDebounceNanoseconds: UInt64 = 150_000_000 // 150ms
// Roughly covers the largest first screenful (kMaxColumnCount=10 × ~6 visible rows) so the
// initial icon batch finishes fast; the rest backfills afterward without blocking the grid.
let kPriorityIconLoadCount = 60
let kNewlyInstalledWindowSeconds: TimeInterval = 14 * 24 * 60 * 60 // 14 days

// MARK: - OverlayWindowManager Constants

let kWindowAnimationDelay: TimeInterval = 0.1
let kWindowMinWidth: CGFloat = 900
let kWindowMinHeight: CGFloat = 700

// MARK: - Launch Animation Constants

let kLaunchZoomOutStartScale: CGFloat = 1.25
let kLaunchZoomOutDuration: TimeInterval = 0.8

// MARK: - SettingsWindowManager Constants

let kSettingsWindowWidth: CGFloat = 820
let kSettingsWindowHeight: CGFloat = 560
let kSettingsWindowMinWidth: CGFloat = 700
let kSettingsWindowMinHeight: CGFloat = 480
let kSettingsWindowMaxWidth: CGFloat = 1400
let kSettingsWindowMaxHeight: CGFloat = 1000

// MARK: - Opacity Constants

let kOverlayOpacityDefault: Double = 0.95

// MARK: - ContentView Constants

let kGridSpacing: CGFloat = 20
let kAppIconPadding: CGFloat = 8
let kAppIconCornerRadius: CGFloat = 10
let kAppIconHoverScale: CGFloat = 1.08
let kSectionViewPadding: CGFloat = 10
let kSearchPadding: CGFloat = 10
let kSearchCornerRadius: CGFloat = 8
let kCategoryTabPaddingHorizontal: CGFloat = 10
let kCategoryTabPaddingVertical: CGFloat = 5
let kCategoryTabCornerRadius: CGFloat = 6
let kSettingsButtonSize: CGFloat = 28

// MARK: - Layout Constants

let kMinColumnCount = 4
let kMaxColumnCount = 10
let kIconSizeSmall: CGFloat = 48
let kIconSizeMedium: CGFloat = 64
let kIconSizeLarge: CGFloat = 80

// MARK: - SettingsContentView Constants

let kSidebarWidth: CGFloat = 200
let kSidebarHeaderPaddingHorizontal: CGFloat = 20
let kSidebarHeaderPaddingVertical: CGFloat = 16
let kSidebarSectionPaddingHorizontal: CGFloat = 12
let kSidebarSectionPaddingVertical: CGFloat = 7
let kSidebarSectionCornerRadius: CGFloat = 6
let kSidebarSectionSpacing: CGFloat = 4
let kSidebarVersionPaddingHorizontal: CGFloat = 16
let kSidebarVersionPaddingBottom: CGFloat = 12
let kHeaderPaddingHorizontal: CGFloat = 28
let kHeaderPaddingVertical: CGFloat = 18
let kContentPaddingHorizontal: CGFloat = 28
let kContentPaddingVertical: CGFloat = 20
let kFooterPaddingHorizontal: CGFloat = 28
let kFooterPaddingVertical: CGFloat = 14
let kSectionSpacing: CGFloat = 28
let kSectionContentSpacing: CGFloat = 14
let kSectionContentPadding: CGFloat = 14
let kSectionContentCornerRadius: CGFloat = 10
let kTogglePaddingTop: CGFloat = 14
let kErrorPaddingHorizontal: CGFloat = 14
let kErrorPaddingBottom: CGFloat = 14
let kButtonSpacing: CGFloat = 6
let kLabelSpacing: CGFloat = 14
let kLabelSpacingVertical: CGFloat = 4
let kHiddenAppsListPaddingVertical: CGFloat = 20
