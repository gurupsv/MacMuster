import XCTest
@testable import MacMuster

/// Covers the wizard's state machine: step transitions, first-run selection, rerun detection,
/// apply/undo, and the gate wiring. Runs against a real `AppModel`, so it exercises the same
/// `applySmartFolderBatch`/`undoSmartFolderBatch` the production panel drives.
@MainActor
final class SmartFoldersWizardViewModelTests: XCTestCase {

    private var appModel: AppModel!
    private var library: LibraryScanState { appModel.library }
    private var model: SmartFoldersWizardViewModel!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        appModel = AppModel()
        model = SmartFoldersWizardViewModel(appModel: appModel)
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        appModel = nil
        model = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "appFolders")
        UserDefaults.standard.removeObject(forKey: "hiddenAppPaths")
        UserDefaults.standard.removeObject(forKey: "customDirectories")
        UserDefaults.standard.removeObject(forKey: "customDirectoryBookmarks")
        UserDefaults.standard.removeObject(forKey: "currentFolderId")
        UserDefaults.standard.removeObject(forKey: "customOrder")
        UserDefaults.standard.removeObject(forKey: "sortOption")
        UserDefaults.standard.removeObject(forKey: "columnCount")
        UserDefaults.standard.removeObject(forKey: "iconSize")
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        UserDefaults.standard.removeObject(forKey: "fontFamily")
        UserDefaults.standard.removeObject(forKey: "fontSize")
        UserDefaults.standard.removeObject(forKey: "fontWeight")
        UserDefaults.standard.removeObject(forKey: "glowEnabled")
        UserDefaults.standard.removeObject(forKey: "glowColor")
        UserDefaults.standard.removeObject(forKey: "glowIntensity")
        UserDefaults.standard.removeObject(forKey: "glowWidth")
        UserDefaults.standard.removeObject(forKey: "overlayOpacity")
        UserDefaults.standard.removeObject(forKey: "showFoldersFirst")
        UserDefaults.standard.removeObject(forKey: "hasShownLauncher")
        UserDefaults.standard.removeObject(forKey: "recentAppsEnabled")
        UserDefaults.standard.removeObject(forKey: "pressFeedbackEnabled")
    }

    private func makeApp(_ name: String, system: Bool = false) -> Application {
        let dir = system ? "/System/Applications" : "/Applications"
        let path = "\(dir)/\(name).app"
        return Application(id: path, name: name, path: path, icon: nil, installationDate: Date(), isFolder: false)
    }

    // MARK: - start

    func testStartFirstRunSelectsEveryCategoryWithApps() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()

        XCTAssertFalse(model.isRerun)
        XCTAssertNotNil(model.plan)
        XCTAssertEqual(model.totalUnsortedApps, 2)
        XCTAssertTrue(model.selectedCategories.contains(.internetCommunication), "Safari → Internet")
        XCTAssertTrue(model.selectedCategories.contains(.development), "Xcode → Development")
        // showAnimation tracks the gate result (whatever it is on this machine).
        XCTAssertEqual(model.showAnimation, model.animationOffered)
    }

    func testStartDetectsRerunWhenASmartFolderExists() async {
        library.setApplications([makeApp("Safari")])
        _ = library.createFolder(name: "Dev", appPaths: [])
        if let i = library.folders.firstIndex(where: { $0.name == "Dev" }) {
            library.folders[i].smartCategoryKey = "development"
        }

        await model.start()

        XCTAssertTrue(model.isRerun)
    }

    func testStartIsRerunFalseForAKeylessManualFolder() async {
        library.setApplications([makeApp("Safari")])
        _ = library.createFolder(name: "My Manual Folder", appPaths: [])

        await model.start()

        // A manually created folder (no key) does not put the wizard in rerun mode.
        XCTAssertFalse(model.isRerun)
    }

    // MARK: - canProceed

    func testCanProceedFalseWhenNothingUnsorted() async {
        library.setApplications([])
        await model.start()
        XCTAssertFalse(model.canProceed)
    }

    func testCanProceedFalseFirstRunWhenNoCategorySelected() async {
        library.setApplications([makeApp("Safari")])
        await model.start()
        model.selectedCategories = []
        XCTAssertFalse(model.canProceed)
    }

    // MARK: - apply / undo

    func testApplyOrganizesAndReachesDone() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()
        model.proceedToPreview()
        XCTAssertEqual(model.step, .preview)

        _ = model.apply()

        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.organizedApps, 2)
        XCTAssertEqual(model.organizedFolders, 2)
        XCTAssertTrue(library.folders.contains { $0.smartCategoryKey == "internet-communication" })
        XCTAssertTrue(library.folders.contains { $0.smartCategoryKey == "development" })
    }

    func testFirstRunAppliesOnlySelectedCategories() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()
        // Select only Internet; Development must be left alone.
        model.selectedCategories = [.internetCommunication]
        model.proceedToPreview()
        _ = model.apply()

        XCTAssertEqual(model.organizedApps, 1)
        XCTAssertTrue(library.folders.contains { $0.smartCategoryKey == "internet-communication" })
        XCTAssertFalse(library.folders.contains { $0.smartCategoryKey == "development" },
            "An unselected category must not have a folder created for it")
    }

    func testUndoRevertsAndReturnsToPreview() async {
        library.setApplications([makeApp("Safari")])
        await model.start()
        model.proceedToPreview()
        _ = model.apply()
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(library.folders.count, 1)

        model.undo()

        XCTAssertEqual(model.step, .preview)
        XCTAssertEqual(library.folders.count, 0)
        XCTAssertFalse(model.canUndo)
    }

    // MARK: - effectivePlan (preview == apply)

    func testEffectivePlanFirstRunRespectsSelection() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()

        // start() selects every category with apps, so both are in the effective plan.
        XCTAssertEqual(model.effectiveAppCount, 2)

        model.selectedCategories = [.internetCommunication]
        XCTAssertEqual(model.effectiveAppCount, 1)
        XCTAssertNil(model.effectivePlan.assignments[.development],
            "A deselected category must not appear in what 'Organize' will do")
    }

    func testEffectivePlanRerunExcludesNewCategoryUnlessCreateMissing() async {
        // An existing smart folder for Internet & Communication (matched by key).
        _ = library.createFolder(name: "Dev", appPaths: [])
        if let i = library.folders.firstIndex(where: { $0.name == "Dev" }) {
            library.folders[i].name = SmartFolderCategory.internetCommunication.displayName
            library.folders[i].smartCategoryKey = SmartFolderCategory.internetCommunication.rawValue
        }
        // Safari → Internet (existing folder), Xcode → Development (no folder yet).
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()
        XCTAssertTrue(model.isRerun)

        model.createMissingFolders = false
        XCTAssertNotNil(model.effectivePlan.assignments[.internetCommunication])
        XCTAssertNil(model.effectivePlan.assignments[.development],
            "A new category is left alone when the create-missing box is off")
        XCTAssertEqual(model.effectiveAppCount, 1)

        model.createMissingFolders = true
        XCTAssertNotNil(model.effectivePlan.assignments[.development],
            "A new category is included when the create-missing box is on")
        XCTAssertEqual(model.effectiveAppCount, 2)
    }

    // MARK: - Rerun selection (regression)

    /// Makes a keyed Internet & Communication folder so the wizard reads as a rerun.
    private func makeRerunWithInternetFolder() {
        _ = library.createFolder(name: SmartFolderCategory.internetCommunication.displayName, appPaths: [])
        if let i = library.folders.indices.first {
            library.folders[i].smartCategoryKey = SmartFolderCategory.internetCommunication.rawValue
        }
    }

    /// Regression: on a rerun `start()` left `selectedCategories` empty and `effectivePlan` ignored
    /// it, so every checkbox showed unchecked and toggling one did nothing.
    func testRerunPreselectsCategoriesSoCheckboxesMatchThePlan() async {
        makeRerunWithInternetFolder()
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()

        XCTAssertTrue(model.isRerun)
        XCTAssertEqual(model.selectedCategories, [.internetCommunication, .development])
    }

    func testRerunDeselectingAnAvailableCategoryRemovesItFromThePlan() async {
        makeRerunWithInternetFolder()
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()
        XCTAssertEqual(model.effectiveAppCount, 1, "Only the category with an existing folder is available")

        model.selectedCategories.remove(.internetCommunication)

        XCTAssertNil(model.effectivePlan.assignments[.internetCommunication],
            "On a rerun, unticking a category must take it out of what 'Organize' does")
        XCTAssertEqual(model.effectiveAppCount, 0)
    }

    func testRerunCategoryAvailabilityFollowsExistingFolderAndCreateMissing() async {
        makeRerunWithInternetFolder()
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()

        XCTAssertTrue(model.isCategoryAvailable(.internetCommunication))
        XCTAssertFalse(model.isCategoryAvailable(.development), "No Development folder and create-missing is off")

        model.createMissingFolders = true
        XCTAssertTrue(model.isCategoryAvailable(.development))
        XCTAssertEqual(model.effectiveAppCount, 2)
    }

    func testFirstRunEveryCategoryIsAvailable() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode")])
        await model.start()
        XCTAssertFalse(model.isRerun)
        XCTAssertTrue(model.isCategoryAvailable(.development))
        XCTAssertFalse(model.needsCreateMissingToProceed)
    }

    func testRerunExplainsDisabledContinueWhenOnlyNewCategoriesRemain() async {
        makeRerunWithInternetFolder()
        library.setApplications([makeApp("Xcode")])   // Development only: no folder for it yet
        await model.start()

        XCTAssertFalse(model.canProceed)
        XCTAssertTrue(model.needsCreateMissingToProceed)

        model.createMissingFolders = true
        XCTAssertTrue(model.canProceed)
        XCTAssertFalse(model.needsCreateMissingToProceed)
    }
}
