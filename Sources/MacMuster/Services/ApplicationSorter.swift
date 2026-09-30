import Foundation

class ApplicationSorter {
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case installationDate = "Installation Date"
    }

    // MARK: - Drag-to-Reorder

    /// Where a dragged app lands relative to the icon it was dropped on.
    enum ReorderSide {
        case before
        case after
    }

    /// Which of the three horizontal thirds of a grid cell a drop landed in, given the drop's
    /// x-position as a fraction of the cell's width (0 = leading edge, 1 = trailing edge).
    ///
    /// The outer quarters mean "reorder next to this icon"; the center half keeps the existing
    /// "merge into a folder" gesture unchanged — the same edge-vs-center split Launchpad and
    /// Finder's icon view use, so dragging doesn't need a new mode or a modifier key to be
    /// discoverable.
    enum DropZone {
        case leadingEdge
        case center
        case trailingEdge
    }

    static func dropZone(forXFraction fraction: CGFloat) -> DropZone {
        if fraction < 0.25 { return .leadingEdge }
        if fraction > 0.75 { return .trailingEdge }
        return .center
    }

    /// Moves `movedPath` to sit immediately before or after `targetPath` within `apps`, preserving
    /// everyone else's relative order. Returns `apps` unchanged if either path isn't present, or if
    /// they're the same path (dropping an icon on itself).
    ///
    /// This only reorders the array handed to it — callers decide *which* array that is (the root
    /// grid's loose apps + folder icons, or one folder's contents), and persisting the result is a
    /// separate step (`LibraryScanState.updateCustomOrder`). Kept free of `Application`'s other
    /// fields and of any app/AppKit dependency so the reorder math is directly unit-testable.
    static func reordered(
        _ apps: [Application],
        moving movedPath: String,
        toSideOf targetPath: String,
        side: ReorderSide
    ) -> [Application] {
        guard movedPath != targetPath else { return apps }
        var result = apps
        guard let fromIndex = result.firstIndex(where: { $0.path == movedPath }) else { return apps }
        let moved = result.remove(at: fromIndex)
        guard let targetIndex = result.firstIndex(where: { $0.path == targetPath }) else {
            // Target vanished from `apps` (shouldn't happen outside a stale drag payload) — put
            // the moved app back where it came from rather than silently dropping it.
            result.insert(moved, at: min(fromIndex, result.count))
            return result
        }
        let insertIndex = side == .before ? targetIndex : targetIndex + 1
        result.insert(moved, at: insertIndex)
        return result
    }

    static func sort(_ applications: [Application], by option: SortOption) -> [Application] {
        applications.sorted { isOrderedBefore($0, $1, by: option) }
    }

    /// Orders apps by the user's drag order where one exists, falling back to `option` for the rest.
    ///
    /// Replaces a comparator that was duplicated in three places and had two problems.
    ///
    /// It ignored `option` entirely the moment `customOrder` was non-empty, so dragging a single
    /// icon silently switched the Sort menu off — every app, including ones the user had never
    /// touched, fell under the drag order, and the menu appeared to do nothing.
    ///
    /// It also reported every pair of un-dragged apps as equal. `sorted` is not stable in Swift,
    /// so apps with no custom position could come back in a different order on each scan and
    /// visibly shuffle around the grid. Falling through to `option` gives those pairs a real,
    /// deterministic answer.
    ///
    /// Apps carrying a custom position come first, in that order; everything else follows in
    /// `option` order. That keeps a drag meaningful without freezing newly installed apps out of
    /// the sort the user actually chose.
    static func sort(
        _ applications: [Application],
        by option: SortOption,
        customOrder: [String: Int]
    ) -> [Application] {
        guard !customOrder.isEmpty else { return sort(applications, by: option) }
        return applications.sorted { lhs, rhs in
            switch (customOrder[lhs.path], customOrder[rhs.path]) {
            case let (lhsIndex?, rhsIndex?):
                // Two dragged apps: their positions decide, and equal positions (which a stale
                // order dictionary can contain) still need a deterministic answer.
                return lhsIndex != rhsIndex ? lhsIndex < rhsIndex : isOrderedBefore(lhs, rhs, by: option)
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return isOrderedBefore(lhs, rhs, by: option)
            }
        }
    }

    /// Places folders ahead of apps, ordering within each group by `option` and `customOrder`.
    ///
    /// Partitioning first is what makes "Show Folders First" survive a drag: the previous code
    /// computed the folders-first arrangement and then re-sorted the whole list by custom order,
    /// throwing the partition away.
    static func sort(
        _ applications: [Application],
        by option: SortOption,
        customOrder: [String: Int],
        foldersFirst: Bool
    ) -> [Application] {
        guard foldersFirst else { return sort(applications, by: option, customOrder: customOrder) }
        let folders = applications.filter(\.isFolder)
        let apps = applications.filter { !$0.isFolder }
        guard !folders.isEmpty, !apps.isEmpty else {
            return sort(applications, by: option, customOrder: customOrder)
        }
        return sort(folders, by: option, customOrder: customOrder)
             + sort(apps, by: option, customOrder: customOrder)
    }

    /// The total order for `option`.
    ///
    /// Each case ends in a tiebreak on `path`, which is unique per app, so no two distinct apps
    /// ever compare equal. Without that, ties — same name, or the same install date, which is
    /// common now that an unreadable mtime resolves to `.distantPast` — would be left to an
    /// unstable sort and could reorder between scans.
    static func isOrderedBefore(_ lhs: Application, _ rhs: Application, by option: SortOption) -> Bool {
        switch option {
        case .name:
            if lhs.lowercaseName != rhs.lowercaseName { return lhs.lowercaseName < rhs.lowercaseName }
            return lhs.path < rhs.path
        case .installationDate:
            if lhs.installationDate != rhs.installationDate { return lhs.installationDate > rhs.installationDate }
            return lhs.path < rhs.path
        }
    }
}
