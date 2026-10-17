import XCTest
@testable import MacMuster

/// Covers the pure math and gating for the wizard animation. These are the parts that are cheap to
/// reason about and expensive to get wrong (a mis-gated animation can peg a small machine; a broken
/// easing makes the dots teleport), so they are tested directly rather than only through the view.
final class WizardAnimationTests: XCTestCase {

    // MARK: - Gate

    func testGateAllowsOnNominalWithEnoughCores() {
        XCTAssertTrue(SmartFoldersAnimation.isAnimationAllowed(
            thermalState: .nominal,
            activeCores: WizardMetrics.minAnimatedCores,
            reduceMotion: false))
    }

    func testGateRejectsThermalPressure() {
        for state in [ProcessInfo.ThermalState.fair, .serious, .critical] {
            XCTAssertFalse(SmartFoldersAnimation.isAnimationAllowed(
                thermalState: state, activeCores: 8, reduceMotion: false),
                "Animation must not be offered under thermal state \(state)")
        }
    }

    func testGateRejectsTooFewCores() {
        XCTAssertFalse(SmartFoldersAnimation.isAnimationAllowed(
            thermalState: .nominal,
            activeCores: WizardMetrics.minAnimatedCores - 1,
            reduceMotion: false))
    }

    func testGateRejectsReduceMotion() {
        XCTAssertFalse(SmartFoldersAnimation.isAnimationAllowed(
            thermalState: .nominal, activeCores: 8, reduceMotion: true))
    }

    // MARK: - progress

    func testProgressIsZeroBeforeItsStaggeredStart() {
        // index 5 starts at 0.5 (0.1 stagger × 5); at elapsed 0 it has not begun.
        XCTAssertEqual(SmartFoldersAnimation.progress(elapsed: 0, index: 5, duration: 1, stagger: 0.1),
                       0, accuracy: 1e-9)
    }

    func testProgressClampsToOneAfterDuration() {
        XCTAssertEqual(SmartFoldersAnimation.progress(elapsed: 10, index: 0, duration: 1, stagger: 0.1),
                       1, accuracy: 1e-9)
    }

    func testProgressStaggerDelaysLaterApps() {
        let early = SmartFoldersAnimation.progress(elapsed: 0.5, index: 0, duration: 1, stagger: 0.1)
        let late = SmartFoldersAnimation.progress(elapsed: 0.5, index: 5, duration: 1, stagger: 0.1)
        XCTAssertGreaterThan(early, late, "A later app must be behind an earlier one at the same clock")
    }

    // MARK: - ease

    func testEaseEndpointsAndMidpoint() {
        XCTAssertEqual(SmartFoldersAnimation.ease(0), 0, accuracy: 1e-9)
        XCTAssertEqual(SmartFoldersAnimation.ease(1), 1, accuracy: 1e-9)
        XCTAssertEqual(SmartFoldersAnimation.ease(0.5), 0.5, accuracy: 1e-9)
    }

    func testEaseIsMonotonicNonDecreasing() {
        var previous = 0.0
        for i in 0...100 {
            let eased = SmartFoldersAnimation.ease(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(eased, previous)
            previous = eased
        }
    }

    // MARK: - lerp

    func testLerpEndpointsAndMidpoint() {
        let from = CGPoint(x: 0, y: 0), to = CGPoint(x: 10, y: 20)
        XCTAssertEqual(SmartFoldersAnimation.lerp(from, to, 0).x, 0, accuracy: 1e-9)
        XCTAssertEqual(SmartFoldersAnimation.lerp(from, to, 1).y, 20, accuracy: 1e-9)
        XCTAssertEqual(SmartFoldersAnimation.lerp(from, to, 0.5).x, 5, accuracy: 1e-9)
        XCTAssertEqual(SmartFoldersAnimation.lerp(from, to, 0.5).y, 10, accuracy: 1e-9)
    }

    // MARK: - position (two-phase)

    func testPositionStartsAtLoose() {
        let p = SmartFoldersAnimation.position(loose: .init(x: 1, y: 2), clusterCenter: .init(x: 50, y: 50),
                                               slot: .init(x: 52, y: 70), at: 0)
        XCTAssertEqual(p.x, 1, accuracy: 1e-9)
        XCTAssertEqual(p.y, 2, accuracy: 1e-9)
    }

    func testPositionEndsAtSlot() {
        let p = SmartFoldersAnimation.position(loose: .init(x: 1, y: 2), clusterCenter: .init(x: 50, y: 50),
                                               slot: .init(x: 52, y: 70), at: 1)
        XCTAssertEqual(p.x, 52, accuracy: 1e-9)
        XCTAssertEqual(p.y, 70, accuracy: 1e-9)
    }

    func testPositionPassesThroughClusterCenterAtPhaseBoundary() {
        // At exactly the cluster-phase boundary the first phase has eased fully to the cluster
        // center, and the second phase has eased zero — both agree on the cluster center.
        let cluster = CGPoint(x: 40, y: 60)
        let p = SmartFoldersAnimation.position(loose: .init(x: 0, y: 0), clusterCenter: cluster,
                                               slot: .init(x: 42, y: 80), at: WizardMetrics.animationClusterPhase)
        XCTAssertEqual(p.x, 40, accuracy: 1e-6)
        XCTAssertEqual(p.y, 60, accuracy: 1e-6)
    }
}
