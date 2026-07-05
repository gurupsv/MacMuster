import XCTest
@testable import MacMuster

@MainActor
final class ConstantsTests: XCTestCase {

    // MARK: - Representative Constant Checks

    func testKeyConstantsHaveExpectedValues() {
        // AppModel
        XCTAssertEqual(AppMetrics.maxRecentApps, 8)

        // OverlayWindowManager
        XCTAssertEqual(AppMetrics.windowAnimationDelay, 0.1)
        XCTAssertEqual(AppMetrics.windowMinWidth, 900)
        XCTAssertEqual(AppMetrics.windowMinHeight, 700)

        // Layout
        XCTAssertEqual(AppMetrics.minColumnCount, 4)
        XCTAssertEqual(AppMetrics.maxColumnCount, 10)

        // Settings
        XCTAssertEqual(AppMetrics.settingsWindowWidth, 820)
        XCTAssertEqual(AppMetrics.settingsWindowHeight, 560)
        XCTAssertEqual(AppMetrics.sidebarWidth, 200)
    }
}
