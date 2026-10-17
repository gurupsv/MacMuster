import XCTest
import AppKit
@testable import MacMuster

/// Covers `SmartFoldersWizardWindow`'s open/close bookkeeping. Regression: `show()` used to build a
/// second panel on every call, orphaning the first; closing either one then cleared the references
/// to the survivor, so its Cancel/Done buttons (which call `close()`) could no longer close it.
@MainActor
final class SmartFoldersWizardWindowTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        appModel = AppModel()
        SmartFoldersWizardWindow.shared.close()
    }

    override func tearDown() async throws {
        SmartFoldersWizardWindow.shared.close()
        appModel = nil
    }

    private var openWizardPanels: [NSWindow] {
        NSApp.windows.filter { $0 is SmartFoldersWizardPanelWindow && $0.isVisible }
    }

    func testShowTwiceKeepsASinglePanel() {
        SmartFoldersWizardWindow.shared.show(appModel: appModel)
        SmartFoldersWizardWindow.shared.show(appModel: appModel)

        XCTAssertEqual(openWizardPanels.count, 1, "A second show() must reuse the open panel")
    }

    func testCloseAfterRepeatedShowActuallyClosesThePanel() {
        SmartFoldersWizardWindow.shared.show(appModel: appModel)
        SmartFoldersWizardWindow.shared.show(appModel: appModel)

        SmartFoldersWizardWindow.shared.close()

        XCTAssertFalse(SmartFoldersWizardWindow.shared.isVisible)
        XCTAssertEqual(openWizardPanels.count, 0, "Cancel/Done must close the panel even after a repeat open")
    }

    func testStaleWillCloseNotificationDoesNotClearTheLivePanel() {
        SmartFoldersWizardWindow.shared.show(appModel: appModel)

        let stranger = NSWindow()
        SmartFoldersWizardWindow.shared.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: stranger))

        XCTAssertTrue(SmartFoldersWizardWindow.shared.isVisible,
            "A close notification for some other window must not drop the live panel")
    }

    func testReopenAfterCloseShowsAFreshPanel() {
        SmartFoldersWizardWindow.shared.show(appModel: appModel)
        SmartFoldersWizardWindow.shared.close()
        SmartFoldersWizardWindow.shared.show(appModel: appModel)

        XCTAssertEqual(openWizardPanels.count, 1)
    }
}
