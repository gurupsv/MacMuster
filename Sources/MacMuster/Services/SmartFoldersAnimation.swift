import AppKit
import Foundation

/// The pure math and gating for the wizard's "apps moving into folders" animation. Kept free of
/// SwiftUI/AppKit view state so it is directly testable: the gate is a pure function of the machine
/// state, and the position math is a pure function of the clock and a few points.
enum SmartFoldersAnimation {

    /// Whether the animation should be offered at all. It requires all three: the machine is not
    /// thermally pressed, it has enough active cores to spare, and the user has not asked the system
    /// to reduce motion. If any fails, the wizard shows the static plan preview instead — no
    /// information is lost, the animation is only a flourish.
    static func isAnimationAllowed(
        thermalState: ProcessInfo.ThermalState,
        activeCores: Int,
        reduceMotion: Bool
    ) -> Bool {
        thermalState == .nominal
            && activeCores >= WizardMetrics.minAnimatedCores
            && !reduceMotion
    }

    /// Convenience that reads the real machine state, for the production call site.
    static var isAnimationAllowed: Bool {
        isAnimationAllowed(
            thermalState: ProcessInfo.processInfo.thermalState,
            activeCores: ProcessInfo.processInfo.activeProcessorCount,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// The eased 0→1 progress for one app at a moment in the animation clock. Each app starts
    /// `stagger × index` into the timeline, so the dots move in a wave; before its start the progress
    /// is 0, after `duration` it is 1.
    static func progress(elapsed: Double, index: Int, duration: Double, stagger: Double) -> Double {
        let local = (elapsed - Double(index) * stagger) / duration
        return min(max(local, 0), 1)
    }

    /// Cubic ease-in-out: slow at both ends, fast in the middle. Reads as natural motion for the
    /// dots rather than a linear glide.
    static func ease(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Linear interpolation between two points by a 0→1 factor.
    static func lerp(_ from: CGPoint, _ to: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }

    /// The two-phase position of an app at overall progress `t` (0→1). The first
    /// `clusterPhase` fraction eases it from its loose position to its folder's cluster center;
    /// the rest eases it from the cluster center into its final slot. That split is what makes the
    /// motion read as "grouping" rather than a single straight line.
    static func position(
        loose: CGPoint,
        clusterCenter: CGPoint,
        slot: CGPoint,
        at t: Double
    ) -> CGPoint {
        let phase = WizardMetrics.animationClusterPhase
        if t < phase {
            return lerp(loose, clusterCenter, ease(t / phase))
        } else {
            return lerp(clusterCenter, slot, ease((t - phase) / (1 - phase)))
        }
    }
}
