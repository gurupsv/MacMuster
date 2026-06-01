import AppKit
import SwiftUI

// MARK: - AppModel Constants

let kIconCacheBatchSize = 12  // Reduced from 24 to distribute blocking over more batches
let kIconLoadDelay: TimeInterval = 0.01  // Reduced from 0.02 to minimize inter-batch delay
let kIconLoadDelayAfterInitial: TimeInterval = 0.0  // Removed 300ms delay; start icon loading immediately
let kMaxRecentApps = 8
let kMaxDirectoryScanSize = 5000

// MARK: - OverlayWindowManager Constants

let kWindowAnimationDelay: TimeInterval = 0.1
let kWindowMinWidth: CGFloat = 900
let kWindowMinHeight: CGFloat = 700
let kWindowPadding: CGFloat = 40

// MARK: - SettingsWindowManager Constants

let kSettingsWindowWidth: CGFloat = 820
let kSettingsWindowHeight: CGFloat = 560
let kSettingsWindowMinWidth: CGFloat = 700
let kSettingsWindowMinHeight: CGFloat = 480
let kSettingsWindowMaxWidth: CGFloat = 1400
let kSettingsWindowMaxHeight: CGFloat = 1000

// MARK: - ContentView Constants

let kGridColumnCount = 8
let kGridSpacing: CGFloat = 20
let kRecentColumnCount = 8
let kSearchMaxWidth: CGFloat = 320
let kAppIconSize: CGFloat = 64
let kAppIconPadding: CGFloat = 8
let kAppIconCornerRadius: CGFloat = 10
let kAppIconHoverScale: CGFloat = 1.08
let kAppIconSelectedScale: CGFloat = 1.08
let kAppIconShadowRadius: CGFloat = 8
let kAppIconShadowOffsetY: CGFloat = 4
let kSectionViewPadding: CGFloat = 10
let kSearchPadding: CGFloat = 10
let kSearchCornerRadius: CGFloat = 8
let kCategoryTabPaddingHorizontal: CGFloat = 10
let kCategoryTabPaddingVertical: CGFloat = 5
let kCategoryTabCornerRadius: CGFloat = 6
let kSortMenuPaddingHorizontal: CGFloat = 10
let kSortMenuPaddingVertical: CGFloat = 5
let kSortMenuCornerRadius: CGFloat = 6
let kSettingsButtonSize: CGFloat = 28
let kSettingsButtonCornerRadius: CGFloat = 14
let kSearchFocusDelay: TimeInterval = 0.1

// MARK: - Layout Constants

let kMinColumnCount = 4
let kMaxColumnCount = 10
let kColumnCountStep = 1
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
let kSettingsWindowPadding: CGFloat = 14
