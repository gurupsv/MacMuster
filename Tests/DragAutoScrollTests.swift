import XCTest
@testable import MacMuster

final class DragAutoScrollTests: XCTestCase {
    private let height: CGFloat = 800

    func testMiddleOfViewDoesNotScroll() {
        XCTAssertEqual(DragAutoScroll.velocity(y: 400, height: height), 0)
    }

    func testTopEdgeScrollsTowardTopAtMaxSpeed() {
        XCTAssertEqual(DragAutoScroll.velocity(y: height, height: height), -DragScrollMetrics.maxPointsPerSecond)
    }

    func testBottomEdgeScrollsTowardBottomAtMaxSpeed() {
        XCTAssertEqual(DragAutoScroll.velocity(y: 0, height: height), DragScrollMetrics.maxPointsPerSecond)
    }

    func testSpeedRampsInsideBand() {
        let half = DragAutoScroll.velocity(y: height - DragScrollMetrics.edgeBandPoints / 2, height: height)
        XCTAssertEqual(half, -DragScrollMetrics.maxPointsPerSecond / 2, accuracy: 0.001)
    }

    func testBandInnerEdgeIsStationary() {
        XCTAssertEqual(DragAutoScroll.velocity(y: height - DragScrollMetrics.edgeBandPoints, height: height), 0)
    }

    func testViewShorterThanBothBandsNeverScrolls() {
        XCTAssertEqual(DragAutoScroll.velocity(y: 10, height: DragScrollMetrics.edgeBandPoints), 0)
    }

    func testClampedStaysInsideContent() {
        XCTAssertEqual(DragAutoScroll.clamped(offset: 10, delta: -50, contentHeight: 2000, viewHeight: 800), 0)
        XCTAssertEqual(DragAutoScroll.clamped(offset: 1100, delta: 500, contentHeight: 2000, viewHeight: 800), 1200)
        XCTAssertEqual(DragAutoScroll.clamped(offset: 0, delta: 40, contentHeight: 500, viewHeight: 800), 0)
    }
}
