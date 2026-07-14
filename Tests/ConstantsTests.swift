import XCTest
@testable import MacMuster

@MainActor
final class ConstantsTests: XCTestCase {

    func testKeyConstantsHaveExpectedValues() {
        XCTAssertEqual(ScanMetrics.maxRecentApps, 8)
        XCTAssertEqual(WindowMetrics.windowAnimationDelay, 0.1)
        XCTAssertEqual(WindowMetrics.windowMinWidth, 900)
        XCTAssertEqual(WindowMetrics.windowMinHeight, 700)
        XCTAssertEqual(LayoutMetrics.minColumnCount, 4)
        XCTAssertEqual(LayoutMetrics.maxColumnCount, 10)
        XCTAssertEqual(WindowMetrics.settingsWindowWidth, 820)
        XCTAssertEqual(WindowMetrics.settingsWindowHeight, 560)
        XCTAssertEqual(SettingsLayoutMetrics.sidebarWidth, 200)
    }
}
