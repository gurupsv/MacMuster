import Foundation

/// Pure curve for scrolling the grid while an icon is dragged near its top or bottom edge, so a
/// folder (or any drop target) that is off screen can be reached without dropping first.
enum DragAutoScroll {
    /// Signed scroll velocity in points per second for a pointer at `y` (measured from the bottom of
    /// a view `height` tall). Negative scrolls toward the top of the content, positive toward the
    /// bottom, zero outside both bands. Speed ramps from 0 at the band's inner edge to
    /// `DragScrollMetrics.maxPointsPerSecond` at the view's edge, and holds there beyond it.
    nonisolated static func velocity(y: CGFloat, height: CGFloat) -> CGFloat {
        let band = DragScrollMetrics.edgeBandPoints
        guard height > 2 * band else { return 0 }
        if y > height - band {
            let t = min(1, (y - (height - band)) / band)
            return -DragScrollMetrics.maxPointsPerSecond * t
        }
        if y < band {
            let t = min(1, (band - y) / band)
            return DragScrollMetrics.maxPointsPerSecond * t
        }
        return 0
    }

    /// `offset + delta` kept inside the scrollable range.
    nonisolated static func clamped(offset: CGFloat, delta: CGFloat, contentHeight: CGFloat, viewHeight: CGFloat) -> CGFloat {
        min(max(0, offset + delta), max(0, contentHeight - viewHeight))
    }
}
