import XCTest
@testable import MacMuster

@MainActor
final class OverlayWindowManagerTests: XCTestCase {

    var appModel: AppModel!
    var manager: OverlayWindowManager!

    override func setUp() async throws {
        appModel = AppModel()
        manager = OverlayWindowManager.shared
        manager.setup(appModel: appModel)
    }

    override func tearDown() async throws {
        appModel = nil
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

    // MARK: - Key Handling Tests

    func testUpArrowMovesUpByColumnCount() {
        // Setup: 8 column grid with 16 apps
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Select app at index 9 (second row, second column)
        appModel.selectedAppIndex = 9

        // Simulate Up arrow — should move to index 1 (first row, second column)
        let event = NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126) ?? NSEvent()

        let handled = manager.handleKeyDown(event)
        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.selectedAppIndex, 1)
    }

    func testDownArrowMovesDownByColumnCount() {
        let apps = (0..<16).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Select app at index 1 (first row, second column)
        appModel.selectedAppIndex = 1

        // Simulate Down arrow — should move to index 9 (second row, second column)
        let event = NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125) ?? NSEvent()

        let handled = manager.handleKeyDown(event)
        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.selectedAppIndex, 9)
    }

    func testLeftArrowMovesLeft() {
        let apps = (0..<8).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Select app at index 3
        appModel.selectedAppIndex = 3

        // Simulate Left arrow — should move to index 2
        let event = NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123) ?? NSEvent()

        let handled = manager.handleKeyDown(event)
        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.selectedAppIndex, 2)
    }

    func testRightArrowMovesRight() {
        let apps = (0..<8).map { i in
            Application(id: "/Applications/App\(i).app", name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        }
        appModel.setApplications(apps)
        appModel.columnCount = 8

        // Select app at index 2
        appModel.selectedAppIndex = 2

        // Simulate Right arrow — should move to index 3
        let event = NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124) ?? NSEvent()

        let handled = manager.handleKeyDown(event)
        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.selectedAppIndex, 3)
    }

    func testEscapeWhenSearchNotFocusedHidesLauncher() {
        let event = NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{001B}",
            charactersIgnoringModifiers: "\u{001B}",
            isARepeat: false,
            keyCode: 53) ?? NSEvent()

        // Escape when search is not focused should hide launcher (handled)
        let handled = manager.handleKeyDown(event)
        XCTAssertTrue(handled)
    }

    // MARK: - Folder Escape/Backspace Tests (B-1/B-2)

    private func escapeEvent() -> NSEvent {
        NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{001B}",
            charactersIgnoringModifiers: "\u{001B}",
            isARepeat: false,
            keyCode: 53) ?? NSEvent()
    }

    private func backspaceEvent() -> NSEvent {
        NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{0008}",
            charactersIgnoringModifiers: "\u{0008}",
            isARepeat: false,
            keyCode: 51) ?? NSEvent()
    }

    func testEscapeInsideFolderClosesFolderInsteadOfHidingLauncher() {
        let folder = appModel.createFolder(name: "Dev", appPaths: [])
        appModel.openFolder(folder.id)
        XCTAssertNotNil(appModel.currentFolderId)

        let handled = manager.handleKeyDown(escapeEvent())

        XCTAssertTrue(handled)
        // Escape should navigate back to the root grid, not dismiss the whole launcher.
        XCTAssertNil(appModel.currentFolderId)
    }

    func testBackspaceInsideFolderClosesFolder() {
        let folder = appModel.createFolder(name: "Dev", appPaths: [])
        appModel.openFolder(folder.id)
        XCTAssertNotNil(appModel.currentFolderId)

        let handled = manager.handleKeyDown(backspaceEvent())

        XCTAssertTrue(handled)
        XCTAssertNil(appModel.currentFolderId)
    }

    func testBackspaceAtRootIsNotHandled() {
        XCTAssertNil(appModel.currentFolderId)

        let handled = manager.handleKeyDown(backspaceEvent())

        // At root level, Backspace isn't a launcher shortcut — let it fall through.
        XCTAssertFalse(handled)
        XCTAssertNil(appModel.currentFolderId)
    }

    // MARK: - Type-to-Search Tests

    private func letterKeyEvent(_ character: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent(keyType: .keyDown,
            location: NSPoint.zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode) ?? NSEvent()
    }

    func testTypingALetterWithNoModifierStartsSearchImmediately() {
        XCTAssertEqual(appModel.searchTerm, "")

        let handled = manager.handleKeyDown(letterKeyEvent("t", keyCode: 17)) // kVK_ANSI_T

        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.searchTerm, "t")
    }

    func testTypingAppendsToAnyExistingSearchTerm() {
        appModel.searchTerm = "te"

        let handled = manager.handleKeyDown(letterKeyEvent("s", keyCode: 1)) // kVK_ANSI_S

        XCTAssertTrue(handled)
        XCTAssertEqual(appModel.searchTerm, "tes")
    }

    func testCommandModifiedKeyIsNotTreatedAsTypeToSearch() {
        let handled = manager.handleKeyDown(letterKeyEvent("q", keyCode: 12, modifiers: [.command])) // ⌘Q

        XCTAssertFalse(handled)
        XCTAssertEqual(appModel.searchTerm, "")
    }

    func testControlModifiedKeyIsNotTreatedAsTypeToSearch() {
        let handled = manager.handleKeyDown(letterKeyEvent("a", keyCode: 0, modifiers: [.control]))

        XCTAssertFalse(handled)
        XCTAssertEqual(appModel.searchTerm, "")
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