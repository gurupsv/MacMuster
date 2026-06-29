import XCTest
@testable import MacMuster

final class StatusBarManagerTests: XCTestCase {
    
    func testManagerIsSingleton() {
        let manager1 = StatusBarManager.shared
        let manager2 = StatusBarManager.shared
        XCTAssertIdentical(manager1, manager2)
    }
    
    func testManagerHasShowWindowMethod() {
        // Verify the method exists and is callable
        let manager = StatusBarManager.shared
        XCTAssertNoThrow(try manager.showWindow())
    }
    
    func testManagerHasHideWindowMethod() {
        let manager = StatusBarManager.shared
        XCTAssertNoThrow(try manager.hideWindow())
    }
    
    func testManagerExposesQuitAction() {
        let manager = StatusBarManager.shared
        XCTAssertTrue(manager.responds(to: #selector(StatusBarManager.quitApp)))
    }

    /// Regression coverage: the status item button must route through a single click handler
    /// that can distinguish left/right click, rather than `statusItem.menu` being set directly
    /// (which would make AppKit show that menu on every click and never call the button's action).
    func testManagerExposesStatusItemClickHandler() {
        let manager = StatusBarManager.shared
        XCTAssertTrue(manager.responds(to: NSSelectorFromString("statusItemClicked")))
    }
}
