import XCTest
@testable import MacMuster

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
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
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
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
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
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
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
            AppModel.Application(name: "App\(i)", path: "/Applications/App\(i).app", icon: nil, installationDate: Date())
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
}