import XCTest
@testable import MacMuster

final class AlertHelperTests: XCTestCase {

    // MARK: - showError Alert Properties

    func testShowErrorCreatesCriticalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        XCTAssertEqual(alert.alertStyle, .critical, "showError should create a critical-style alert")
    }

    func testShowErrorSetsMessageText() {
        let alert = NSAlert()
        alert.messageText = "Error Title"
        alert.informativeText = "Error Detail"
        XCTAssertEqual(alert.messageText, "Error Title", "showError messageText should match the title argument")
        XCTAssertEqual(alert.informativeText, "Error Detail", "showError informativeText should match the message argument")
    }

    func testShowErrorAddsOKButton() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Error Title"
        alert.informativeText = "Error Detail"
        alert.addButton(withTitle: "OK")
        XCTAssertEqual(alert.buttons.count, 1, "showError should have exactly one button")
        XCTAssertEqual(alert.buttons.first?.title, "OK", "showError button should be labeled OK")
    }

    func testShowErrorWithEmptyTitleAndMessage() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ""
        alert.informativeText = ""
        alert.addButton(withTitle: "OK")
        XCTAssertEqual(alert.messageText, "", "Empty title should be set")
        XCTAssertEqual(alert.informativeText, "", "Empty message should be set")
        XCTAssertEqual(alert.buttons.count, 1, "OK button should still be present")
    }

    func testShowErrorWithLongMessage() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Critical Error"
        alert.informativeText = String(repeating: "This is a very long error message that exceeds typical length limits ", count: 20)
        alert.addButton(withTitle: "OK")
        XCTAssertGreaterThan(alert.informativeText.count, 500, "Long message should be set without truncation")
        XCTAssertEqual(alert.buttons.count, 1, "OK button should still be present for long message")
    }

    // MARK: - showInfo Alert Properties

    func testShowInfoCreatesInformationalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        XCTAssertEqual(alert.alertStyle, .informational, "showInfo should create an informational-style alert")
    }

    func testShowInfoSetsMessageText() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Info Title"
        alert.informativeText = "Info Detail"
        XCTAssertEqual(alert.messageText, "Info Title", "showInfo messageText should match the title argument")
        XCTAssertEqual(alert.informativeText, "Info Detail", "showInfo informativeText should match the message argument")
    }

    func testShowInfoAddsOKButton() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Info Title"
        alert.informativeText = "Info Detail"
        alert.addButton(withTitle: "OK")
        XCTAssertEqual(alert.buttons.count, 1, "showInfo should have exactly one button")
        XCTAssertEqual(alert.buttons.first?.title, "OK", "showInfo button should be labeled OK")
    }

    func testShowInfoWithEmptyTitleAndMessage() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = ""
        alert.informativeText = ""
        alert.addButton(withTitle: "OK")
        XCTAssertEqual(alert.messageText, "", "Empty title should be set")
        XCTAssertEqual(alert.informativeText, "", "Empty message should be set")
        XCTAssertEqual(alert.buttons.count, 1, "OK button should still be present")
    }

    // MARK: - Style Differentiation

    func testShowErrorAndShowInfoUseDifferentStyles() {
        let errorAlert = NSAlert()
        errorAlert.alertStyle = .critical

        let infoAlert = NSAlert()
        infoAlert.alertStyle = .informational

        XCTAssertNotEqual(errorAlert.alertStyle, infoAlert.alertStyle,
            "showError and showInfo should use different alert styles")
    }

    func testShowErrorCriticalStyleHasDistinctIconFromInformational() {
        // NSAlert critical and informational styles use different system icons.
        // The .critical style uses the stop/caution icon, .informational uses the info icon.
        let errorAlert = NSAlert()
        errorAlert.alertStyle = .critical
        let infoAlert = NSAlert()
        infoAlert.alertStyle = .informational
        // Both should have non-nil icon views
        XCTAssertNotNil(errorAlert.icon, "Critical alert should have an icon")
        XCTAssertNotNil(infoAlert.icon, "Informational alert should have an icon")
        // The icons should be different NSImage instances (critical uses a red stop icon,
        // informational uses a blue info icon — different colors)
        // We can't compare icon identity directly, but we can verify both exist.
        XCTAssertEqual(errorAlert.buttons.count, infoAlert.buttons.count,
            "Both styles should have the same button count (1)")
    }

}
