import Foundation
import Observation

/// The state machine behind the Smart Folders Wizard. It owns the wizard's step, the built plan,
/// the first-run folder selection, the rerun "create missing" option, and the undo token. It is a
/// plain `@MainActor @Observable` object with no window in it, so the panel just renders whatever
/// state is here and the whole flow is unit-testable against a real `AppModel`.
@MainActor
@Observable
final class SmartFoldersWizardViewModel {

    enum Step: Equatable {
        case selection   // first run: choose which folders to create · rerun: confirm the batch
        case preview     // the assignments, optionally animated
        case done        // summary + undo
    }

    private let appModel: AppModel

    var step: Step = .selection
    var isBuilding = false
    var plan: SmartFolderPlan?

    /// Which categories the user wants filled, on a first run and on a rerun alike. Defaults to
    /// every category that actually has apps (set once the plan is built). On a rerun a selected
    /// category still needs an existing folder, or `createMissingFolders`, to take effect.
    var selectedCategories: Set<SmartFolderCategory> = []
    /// Rerun only: create a folder for a category that has no existing folder yet.
    var createMissingFolders = false

    private(set) var undoToken: SmartFolderUndoToken?
    private(set) var organizedApps = 0
    private(set) var organizedFolders = 0

    /// Whether the CPU/thermal/reduce-motion gate passed (decided once on open).
    private(set) var animationOffered = false
    /// Whether the user opted into the animation (defaults to the gate result; they can turn it off).
    var showAnimation = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    /// Rerun mode: the wizard already created at least one folder (any folder carrying a key).
    var isRerun: Bool {
        appModel.library.folders.contains { $0.smartCategoryKey != nil }
    }

    /// Categories the plan would fill, with how many apps each would take — drives the selection
    /// list and the "N apps are unsorted" line.
    var categoryCounts: [(category: SmartFolderCategory, count: Int)] {
        guard let plan else { return [] }
        return plan.assignments
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    var totalUnsortedApps: Int { plan?.assignedCount ?? 0 }

    /// Decides the animation gate and starts building the plan. Called once when the window opens.
    func start() async {
        animationOffered = SmartFoldersAnimation.isAnimationAllowed
        showAnimation = animationOffered
        await buildPlan()
        // Default to selecting every category that has apps, so the checkboxes always show what
        // "Organize" will do (a rerun used to leave them unchecked and ignore them).
        if let plan {
            selectedCategories = Set(plan.assignments.keys)
        }
    }

    func buildPlan() async {
        isBuilding = true
        defer { isBuilding = false }
        plan = await SmartFolderPlanBuilder.build(library: appModel.library)
    }

    /// The plan the wizard will actually act on, for both preview and apply: the categories the
    /// user selected. On a rerun a selected category also needs an existing folder (matched by key
    /// or name, mirroring `applySmartFolderBatch`) unless `createMissingFolders` is on. The
    /// preview renders *this* — not the full plan — so what the user sees is exactly what
    /// "Organize" will do.
    var effectivePlan: SmartFolderPlan {
        guard let plan else { return SmartFolderPlan() }
        var result = SmartFolderPlan()
        for (category, candidates) in plan.assignments {
            guard selectedCategories.contains(category), isCategoryAvailable(category) else { continue }
            result.assignments[category] = candidates
        }
        return result
    }

    /// Whether an existing folder already matches this category (by key first, then name) — the
    /// same resolution `applySmartFolderBatch` uses, so preview and apply can't disagree.
    /// Whether a selected `category` can take effect: always on a first run (folders get created),
    /// and on a rerun only when a folder already exists for it or `createMissingFolders` is on.
    /// The panel disables the checkbox of an unavailable category and says why.
    func isCategoryAvailable(_ category: SmartFolderCategory) -> Bool {
        !isRerun || createMissingFolders || hasExistingFolder(for: category)
    }

    /// Rerun only: the plan has apps, but none can be filed because no matching folder exists and
    /// `createMissingFolders` is off. Lets the panel explain a disabled Continue button.
    var needsCreateMissingToProceed: Bool {
        isRerun && !isBuilding && !createMissingFolders && totalUnsortedApps > 0 && effectiveAppCount == 0
            && !selectedCategories.isEmpty
    }

    private func hasExistingFolder(for category: SmartFolderCategory) -> Bool {
        appModel.library.folders.contains {
            $0.smartCategoryKey == category.rawValue || $0.name == category.displayName
        }
    }

    private var allowCreating: Bool { isRerun ? createMissingFolders : true }

    /// How many apps "Organize" would actually move, given the current options.
    var effectiveAppCount: Int { effectivePlan.assignedCount }

    var canProceed: Bool {
        !isBuilding && effectiveAppCount > 0
    }

    func proceedToPreview() {
        guard canProceed else { return }
        step = .preview
    }

    func backToSelection() {
        step = .selection
    }

    /// Applies the batch. Returns false when nothing changed (everything was already sorted).
    @discardableResult
    func apply() -> Bool {
        guard let token = appModel.library.applySmartFolderBatch(effectivePlan, allowCreatingFolders: allowCreating) else {
            organizedApps = 0
            organizedFolders = 0
            step = .done
            return false
        }
        undoToken = token
        organizedApps = token.assignedPaths.count
        organizedFolders = token.addedPathsByFolder.count
        step = .done
        return true
    }

    /// Reverts the last apply and returns to the preview.
    func undo() {
        guard let token = undoToken else { return }
        appModel.library.undoSmartFolderBatch(token)
        undoToken = nil
        step = .preview
    }

    var canUndo: Bool { undoToken != nil }
}
