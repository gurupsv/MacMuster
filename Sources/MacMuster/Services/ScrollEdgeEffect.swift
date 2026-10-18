import SwiftUI

/// Rows blur, shrink and fade as they approach the top or bottom of the grid's scroll view.
///
/// The curve lives in a pure function so it can be unit-tested; the SwiftUI modifier only feeds it
/// the `ScrollTransitionPhase.value` (-1 = fully past the top edge, 0 = fully visible, 1 = past the
/// bottom edge). Rows fully inside the viewport evaluate to identity values, so mid-scroll the
/// cost is limited to the one row inside each edge band.
enum ScrollEdgeEffect {
    struct Values: Equatable {
        let opacity: Double
        let scale: Double
        let blurRadius: Double

        static let identity = Values(opacity: 1, scale: 1, blurRadius: 0)
    }

    /// Whether the effect should run: needs the preference, and yields to the modes whose purpose
    /// is to minimise GPU work (Low-GPU glass) or motion (Reduce Motion).
    static func isActive(enabled: Bool, simpleGlass: Bool, reduceMotion: Bool) -> Bool {
        enabled && !simpleGlass && !reduceMotion
    }

    /// `phaseValue` is clamped to -1...1 and treated symmetrically; NaN falls back to identity.
    /// Eased with a square so the first part of the band stays crisp and the taper concentrates
    /// near the edge, rather than the whole row looking washed out as soon as it moves.
    static func values(phaseValue: Double) -> Values {
        guard phaseValue.isFinite else { return .identity }
        let t = min(1, abs(phaseValue))
        let eased = t * t
        return Values(
            opacity: 1 - (1 - ScrollEdgeMetrics.minOpacity) * eased,
            scale: 1 - (1 - ScrollEdgeMetrics.minScale) * eased,
            blurRadius: ScrollEdgeMetrics.maxBlurRadius * eased
        )
    }
}

extension View {
    /// Applies `ScrollEdgeEffect` to a scroll-view child. Always attaches the same modifiers (with
    /// identity values when inactive) so toggling the setting never changes the cell's identity
    /// and discards its hover/press `@State`.
    func scrollEdgeEffect(active: Bool) -> some View {
        scrollTransition(.interactive) { content, phase in
            let v = active ? ScrollEdgeEffect.values(phaseValue: phase.value) : .identity
            return content
                .opacity(v.opacity)
                .scaleEffect(v.scale)
                .blur(radius: v.blurRadius)
        }
    }
}
