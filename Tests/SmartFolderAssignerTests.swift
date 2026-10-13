import XCTest
@testable import MacMuster

/// Covers the tier logic and determinism of `SmartFolderAssigner`. The precedence checks each pick
/// **real catalog entries** whose lower tiers would produce a *different* answer, so they prove the
/// ordering (override > vendor prefix > category UTI > name) rather than just that *something*
/// matched.
final class SmartFolderAssignerTests: XCTestCase {

    private func candidate(_ name: String, path: String? = nil) -> SmartFolderCandidate {
        SmartFolderCandidate(path: path ?? "/Applications/\(name).app", name: name)
    }

    /// Classifies a single candidate and returns the folder it was assigned to, or nil if it stayed
    /// loose.
    private func classify(
        _ candidate: SmartFolderCandidate,
        bundleID: String? = nil,
        lsCategory: String? = nil
    ) -> SmartFolderCategory? {
        let plan = SmartFolderAssigner.classify(
            candidates: [candidate],
            bundleInfo: [candidate.path: BundleInfo(bundleID: bundleID, lsCategory: lsCategory)])
        for (category, list) in plan.assignments where list.contains(where: { $0.path == candidate.path }) {
            return category
        }
        return nil
    }

    // MARK: - Tier precedence

    func testBundleIDOverrideBeatsCategoryUTI() {
        // Safari declares public.app-category.productivity, but the override says communication.
        let category = classify(candidate("Safari"),
                                bundleID: "com.apple.Safari",
                                lsCategory: "public.app-category.productivity")
        XCTAssertEqual(category, .internetCommunication,
            "The Safari override must win over its (incorrect) productivity UTI")
    }

    func testVendorPrefixBeatsCategoryUTI() {
        // Not a known bundle ID, but a JetBrains one; the declared UTI says productivity.
        let category = classify(candidate("SomeTool"),
                                bundleID: "com.jetbrains.SomeTool",
                                lsCategory: "public.app-category.productivity")
        XCTAssertEqual(category, .development,
            "A JetBrains bundle must classify as development via the vendor prefix, not its productivity UTI")
    }

    func testCategoryUTIBeatsNameAlias() {
        // "Safari" is a name alias for communication, but the declared UTI is developer-tools.
        let category = classify(candidate("Safari"),
                                bundleID: nil,
                                lsCategory: "public.app-category.developer-tools")
        XCTAssertEqual(category, .development,
            "The declared UTI must win over a coincidental name-alias match")
    }

    func testNameAliasIsUsedWhenHigherTiersMiss() {
        let category = classify(candidate("Firefox"), bundleID: nil, lsCategory: nil)
        XCTAssertEqual(category, .internetCommunication,
            "With no bundle ID or UTI, the exact name alias decides")
    }

    // MARK: - Name matching is exact, not a prefix

    func testNameMatchingIsExactNotPrefix() {
        // "Firefo" is a prefix of the "firefox" alias but not an exact match.
        let candidate = self.candidate("Firefo")
        let plan = SmartFolderAssigner.classify(
            candidates: [candidate],
            bundleInfo: [candidate.path: BundleInfo(bundleID: nil, lsCategory: nil)])
        XCTAssertNil(plan.assignments.values.first { $0.contains(where: { $0.path == candidate.path }) }?.first)
        XCTAssertTrue(plan.loose.contains { $0.path == candidate.path },
            "A prefix of an alias must not match — the app stays loose")
    }

    func testNameMatchingIsCaseInsensitive() {
        let category = classify(candidate("firefox"), bundleID: nil, lsCategory: nil)
        XCTAssertEqual(category, .internetCommunication)
    }

    // MARK: - Bundle-ID matching is case-insensitive

    func testBundleIDMatchingIsCaseInsensitive() {
        // Lowercased form of the "com.apple.Safari" override.
        let category = classify(candidate("Safari"), bundleID: "com.apple.safari", lsCategory: nil)
        XCTAssertEqual(category, .internetCommunication)
    }

    // MARK: - Unknown stays loose

    func testUnknownAppStaysLoose() {
        let candidate = self.candidate("Mystery")
        let plan = SmartFolderAssigner.classify(
            candidates: [candidate],
            bundleInfo: [candidate.path: BundleInfo(bundleID: "com.unknown.app",
                                                    lsCategory: "public.app-category.travel")])
        XCTAssertFalse(plan.assignments.values.contains { $0.contains(where: { $0.path == candidate.path }) })
        XCTAssertTrue(plan.loose.contains { $0.path == candidate.path },
            "An app matching no tier must stay loose, never be force-filed")
    }

    // MARK: - Coverage and determinism

    func testEveryCandidateIsAssignedOrLoose() {
        let safari = candidate("Safari")
        let mystery = candidate("Mystery")
        let firefox = candidate("Firefox")
        let plan = SmartFolderAssigner.classify(
            candidates: [safari, mystery, firefox],
            bundleInfo: [
                safari.path: BundleInfo(bundleID: "com.apple.Safari", lsCategory: "public.app-category.productivity"),
                firefox.path: BundleInfo(bundleID: nil, lsCategory: nil)
            ])
        XCTAssertEqual(plan.assignedCount + plan.loose.count, 3,
            "No candidate may be silently dropped — every one is either assigned or loose")
    }

    func testPlanIsDeterministicRegardlessOfInputOrder() {
        let candidates = (0..<40).map { candidate("App\($0)") }
        var info: [String: BundleInfo] = [:]
        for c in candidates {
            info[c.path] = BundleInfo(bundleID: nil, lsCategory: "public.app-category.productivity")
        }
        func names(_ plan: SmartFolderPlan) -> [String] { (plan.assignments[.productivity] ?? []).map(\.name) }
        let first = SmartFolderAssigner.classify(candidates: candidates, bundleInfo: info)
        let second = SmartFolderAssigner.classify(candidates: candidates.shuffled(), bundleInfo: info)
        let third = SmartFolderAssigner.classify(candidates: candidates.reversed(), bundleInfo: info)

        XCTAssertEqual(names(first), names(second), "Shuffled input must not change folder order")
        XCTAssertEqual(names(first), names(third), "Reversed input must not change folder order")
    }
}
