import XCTest
@testable import MacMuster

final class ConstantsTests: XCTestCase {

    // MARK: - Representative Constant Checks

    func testKeyConstantsHaveExpectedValues() {
        // AppModel
        XCTAssertEqual(kMaxRecentApps, 8)

        // OverlayWindowManager
        XCTAssertEqual(kWindowAnimationDelay, 0.1)
        XCTAssertEqual(kWindowMinWidth, 900)
        XCTAssertEqual(kWindowMinHeight, 700)

        // Layout
        XCTAssertEqual(kMinColumnCount, 4)
        XCTAssertEqual(kMaxColumnCount, 10)

        // Settings
        XCTAssertEqual(kSettingsWindowWidth, 820)
        XCTAssertEqual(kSettingsWindowHeight, 560)
        XCTAssertEqual(kSidebarWidth, 200)
    }
}
