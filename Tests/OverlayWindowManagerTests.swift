import XCTest
@testable import MacMuster

@MainActor
final class OverlayWindowManagerTests: XCTestCase {

    var appModel: AppModel!
    var manager: OverlayWindowManager!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        appModel = AppModel()
        manager = OverlayWindowManager.shared
        manager.setup(appModel: appModel)
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
        appModel = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "appFolders")
        UserDefaults.standard.removeObject(forKey: "hiddenAppPaths")
        UserDefaults.standard.removeObject(forKey: "customDirectories")
        UserDefaults.standard.removeObject(forKey: "customDirectoryBookmarks")
        UserDefaults.standard.removeObject(forKey: "currentFolderId")
        UserDefaults.standard.removeObject(forKey: "customOrder")
        UserDefaults.standard.removeObject(forKey: "sortOption")
        UserDefaults.standard.removeObject(forKey: "columnCount")
        UserDefaults.standard.removeObject(forKey: "iconSize")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "fontFamily")
        UserDefaults.standard.removeObject(forKey: "fontSize")
        UserDefaults.standard.removeObject(forKey: "fontWeight")
        UserDefaults.standard.removeObject(forKey: "glowEnabled")
        UserDefaults.standard.removeObject(forKey: "glowColor")
        UserDefaults.standard.removeObject(forKey: "glowIntensity")
        UserDefaults.standard.removeObject(forKey: "glowWidth")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "showFoldersFirst")
        UserDefaults.standard.removeObject(forKey: "hasShownLauncher")
        UserDefaults.standard.removeObject(forKey: "recentAppsEnabled")
        UserDefaults.standard.removeObject(forKey: "pressFeedbackEnabled")
        UserDefaults.standard.removeObject(forKey: "recentAppLaunchTimes")
        UserDefaults.standard.removeObject(forKey: "appLaunchCounts")
    }

    // MARK: - Singleton Tests

    func testManagerIsSingleton() {
        let manager1 = OverlayWindowManager.shared
        let manager2 = OverlayWindowManager.shared
        XCTAssertIdentical(manager1, manager2)
    }

    // MARK: - Notification Tests

    func testNotificationNameExists() {
        let notificationName = Notification.Name.launcherDidShow
        XCTAssertEqual(notificationName.rawValue, "launcherDidShow")
    }

    // MARK: - Search Field Selection Collapse (first-keystroke fix)

    func testCollapseSelectionMovesCursorToEndClearingSelectAll() {
        // Reproduces AppKit auto-selecting all text when a populated field becomes first responder:
        // the whole string is highlighted, so the next keystroke would replace it.
        let fieldEditor = NSTextView()
        fieldEditor.string = "term"
        fieldEditor.selectedRange = NSRange(location: 0, length: 4)

        manager.collapseSelectionToEnd(of: fieldEditor)

        // Selection collapses to a zero-length cursor at the end, so the next keystroke appends
        // instead of replacing the pre-filled first character.
        XCTAssertEqual(fieldEditor.selectedRange, NSRange(location: 4, length: 0))
    }

    func testCollapseSelectionOnEmptyFieldIsNoOp() {
        let fieldEditor = NSTextView()
        fieldEditor.string = ""
        fieldEditor.selectedRange = NSRange(location: 0, length: 0)

        manager.collapseSelectionToEnd(of: fieldEditor)

        XCTAssertEqual(fieldEditor.selectedRange, NSRange(location: 0, length: 0))
    }

    // MARK: - Full-Selection Detection (first-keystroke fix)

    // The fix only intervenes when AppKit's auto-select-all has selected the *entire* string.
    // A manual cursor or partial selection must be left alone — only the auto-select-all state
    // should be collapsed.

    func testIsFullSelectionTrueWhenEntireStringSelected() {
        // "term" (length 4) fully selected from 0..<4 — this is AppKit's auto-select-all state.
        XCTAssertTrue(manager.isFullSelection(NSRange(location: 0, length: 4), fieldLength: 4))
    }

    func testIsFullSelectionFalseForPartialSelection() {
        // Only "er" (range 1..<3) selected — a user-made partial selection; do not touch.
        XCTAssertFalse(manager.isFullSelection(NSRange(location: 1, length: 2), fieldLength: 4))
    }

    func testIsFullSelectionFalseForCursorAtStart() {
        // Zero-length cursor at the beginning — a manual caret; do not touch.
        XCTAssertFalse(manager.isFullSelection(NSRange(location: 0, length: 0), fieldLength: 4))
    }

    func testIsFullSelectionFalseForCursorAtEnd() {
        // Zero-length cursor at the end — the desired append position; do not touch.
        XCTAssertFalse(manager.isFullSelection(NSRange(location: 4, length: 0), fieldLength: 4))
    }

    func testIsFullSelectionFalseForEmptyField() {
        // An empty field has nothing to auto-select; the guard on length > 0 skips it.
        XCTAssertFalse(manager.isFullSelection(NSRange(location: 0, length: 0), fieldLength: 0))
    }

    func testIsFullSelectionFalseWhenSelectionLengthExceedsField() {
        // Defensive: a range longer than the field is not the auto-select-all state.
        XCTAssertFalse(manager.isFullSelection(NSRange(location: 0, length: 5), fieldLength: 4))
    }
}