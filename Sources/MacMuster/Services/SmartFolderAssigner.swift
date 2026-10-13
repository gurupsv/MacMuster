import Foundation

/// One app the wizard may classify, reduced to plain values so background work never touches
/// `Application` or any `@MainActor` state. Built on the main actor from the filtered candidates
/// (Phase 3's `LibraryScanState.isSmartFolderCandidate`); the planner only ever sees these.
struct SmartFolderCandidate: Sendable, Hashable {
    let path: String
    let name: String
}

/// The outcome of classifying a set of candidates: which apps go to which smart folder, and which
/// matched nothing and therefore stay loose. Every list is in deterministic order.
struct SmartFolderPlan: Sendable {
    /// Category → the candidates assigned to it, in name order (see `SmartFolderAssigner`).
    var assignments: [SmartFolderCategory: [SmartFolderCandidate]] = [:]
    /// Candidates that matched no tier and are left where they are.
    var loose: [SmartFolderCandidate] = []

    /// Total number of apps the plan would move into folders.
    var assignedCount: Int { assignments.values.reduce(0) { $0 + $1.count } }

    /// Every path the plan assigns, regardless of folder — handy for scoped icon regeneration.
    var assignedPaths: Set<String> {
        Set(assignments.values.flatMap { $0.map(\.path) })
    }
}

/// Classifies candidates into smart folders.
///
/// Pure and deterministic — no file I/O, no actor state — so it is trivially testable and safe to
/// run anywhere. Matching walks the four catalog tiers most-to-least trustworthy and takes the
/// first hit (D2): bundle-ID override → vendor prefix → `LSApplicationCategoryType` UTI → exact
/// normalized name. An app that reaches the end unmatched stays loose; it is never force-classified.
enum SmartFolderAssigner {

    /// Classifies every candidate, partitioning the result into per-folder lists and a loose list.
    static func classify(
        candidates: [SmartFolderCandidate],
        bundleInfo: [String: BundleInfo]
    ) -> SmartFolderPlan {
        var plan = SmartFolderPlan()
        for candidate in candidates {
            if let category = category(for: candidate, info: bundleInfo[candidate.path]) {
                plan.assignments[category, default: []].append(candidate)
            } else {
                plan.loose.append(candidate)
            }
        }
        // Deterministic order within each folder and for the loose list.
        for (category, var list) in plan.assignments {
            list.sort(by: Self.isOrderedBefore)
            plan.assignments[category] = list
        }
        plan.loose.sort(by: Self.isOrderedBefore)
        return plan
    }

    // MARK: - Tier matching

    /// The first tier that recognizes `candidate`, or nil. Tiers are ordered most-to-least
    /// trustworthy: an explicit override always wins, a vendor prefix next, the app's own declared
    /// category UTI before its name, and the name last.
    private static func category(for candidate: SmartFolderCandidate, info: BundleInfo?) -> SmartFolderCategory? {
        if let lowered = info?.bundleID?.lowercased(), !lowered.isEmpty {
            // Tier 1 — exact bundle-ID override.
            if let category = bundleIDIndex[lowered] { return category }
            // Tier 2 — vendor prefix.
            if let category = vendorPrefixMatch(lowered) { return category }
        }
        // Tier 3 — the app's declared LSApplicationCategoryType.
        if let lsCategory = info?.lsCategory,
           let category = SmartFolderCategory.byCategoryUTI[lsCategory] {
            return category
        }
        // Tier 4 — exact normalized name.
        if let category = SmartFolderCategory.byName[normalizeName(candidate.name)] {
            return category
        }
        return nil
    }

    /// Lowercased bundle-ID index, built once. Matching is case-insensitive (identifiers vary in
    /// case: `com.apple.Safari` vs `org.mozilla.firefox`); Phase 1's tests guarantee no two
    /// overrides differ only by case, so lowercasing is collision-free.
    private static let bundleIDIndex: [String: SmartFolderCategory] = {
        var index: [String: SmartFolderCategory] = [:]
        for (bundleID, category) in SmartFolderCategory.byBundleID {
            index[bundleID.lowercased()] = category
        }
        return index
    }()

    /// The vendor-prefix category for `loweredBundleID`, longest matching prefix first so a more
    /// specific vendor wins if prefixes ever nest.
    private static func vendorPrefixMatch(_ loweredBundleID: String) -> SmartFolderCategory? {
        var bestPrefixLength = -1
        var bestCategory: SmartFolderCategory?
        for (prefix, category) in SmartFolderCategory.vendorPrefixes
        where loweredBundleID.hasPrefix(prefix) {
            if prefix.count > bestPrefixLength {
                bestPrefixLength = prefix.count
                bestCategory = category
            }
        }
        return bestCategory
    }

    /// Normalizes an app name for tier-4 matching: trim, then case- and diacritic-insensitive
    /// folding, so "Safari", "safari" and "SAFARI" all hit the "safari" alias. The catalog aliases
    /// are stored already normalized (Phase 1 tests enforce it), so only the incoming name is folded.
    private static func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: - Ordering

    /// Mirrors `ApplicationSorter.isOrderedBefore(_,_,by:.name)` — lowercase name, then path — so
    /// the plan orders each folder the same way the launcher's default (Name) sort does. Replicated
    /// here rather than by building throwaway `Application` values, because `Application.init`
    /// canonicalizes the path (a syscall) and the planner should stay pure and cheap.
    private static func isOrderedBefore(_ lhs: SmartFolderCandidate, _ rhs: SmartFolderCandidate) -> Bool {
        let lhsName = lhs.name.lowercased()
        let rhsName = rhs.name.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.path < rhs.path
    }
}
