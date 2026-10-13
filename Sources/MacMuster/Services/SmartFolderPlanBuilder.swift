import Foundation

/// Builds a `SmartFolderPlan` from the live catalog. The one place that turns "what's installed"
/// into "what goes where" for the wizard.
///
/// Concurrency: the candidate collection reads main-actor state (`displayOrder`,
/// `isSmartFolderCandidate`), so it happens on the main actor. The `Info.plist` reads are real
/// file I/O, so they run detached and pass only plain values (`[String]` in, `[String: BundleInfo]`
/// out). The classify step is pure and fast, so it runs back on the main actor. No step blocks the
/// main actor on disk.
@MainActor
enum SmartFolderPlanBuilder {

    /// Classifies every app the wizard may touch. Returns an empty plan when there are no
    /// candidates, so callers can treat a fresh install and an "everything is sorted" state
    /// identically.
    static func build(library: LibraryScanState) async -> SmartFolderPlan {
        // 1. Candidates, on the main actor — reuses the exact eligibility predicate the apply step
        //    re-validates against, so preview and apply can never disagree.
        let candidates: [SmartFolderCandidate] = library.displayOrder
            .filter { library.isSmartFolderCandidate($0) }
            .map { SmartFolderCandidate(path: $0.path, name: $0.name) }
        guard !candidates.isEmpty else { return SmartFolderPlan() }

        // 2. Bundle metadata, off the main actor (plist I/O). Values are passed by value.
        let bundleInfo: [String: BundleInfo] = await Task.detached(priority: .userInitiated) {
            BundleInfoReader.readBundleInfo(forPaths: candidates.map(\.path))
        }.value

        // 3. Pure classification, back on the main actor.
        return SmartFolderAssigner.classify(candidates: candidates, bundleInfo: bundleInfo)
    }
}
