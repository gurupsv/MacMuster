import XCTest
@testable import MacMuster

/// Covers the Smart Folders Wizard's persisted-identity, apply, and undo logic on
/// `LibraryScanState`. The centerpiece invariants:
///
/// - `dataVersion` bumps exactly once per real apply (twice when a folder is open), and zero for a
///   no-op (with or without a folder open).
/// - Re-validation at apply time drops stale candidates (moved, hidden, uninstalled) and never
///   writes a non-`.app` wrapper path.
/// - Reruns are idempotent and match folders by key, so a rename doesn't orphan them.
/// - Undo restores cleanly or surgically (a membership-only edit that `==` would miss is detected
///   by `hasSameContent`).
@MainActor
final class SmartFoldersWizardTests: XCTestCase {

    private var appModel: AppModel!
    private var library: LibraryScanState { appModel.library }

    override func setUp() async throws {
        clearAllUserDefaultsState()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        appModel = nil
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

    // MARK: - Helpers

    private func makeApp(_ name: String, system: Bool = false) -> Application {
        let dir = system ? "/System/Applications" : "/Applications"
        let path = "\(dir)/\(name).app"
        return Application(id: path, name: name, path: path, icon: nil, installationDate: Date(), isFolder: false)
    }

    private func candidate(_ name: String) -> SmartFolderCandidate {
        SmartFolderCandidate(path: "/Applications/\(name).app", name: name)
    }

    private func plan(_ assignments: [SmartFolderCategory: [SmartFolderCandidate]]) -> SmartFolderPlan {
        var p = SmartFolderPlan()
        p.assignments = assignments
        return p
    }

    private func apply(_ p: SmartFolderPlan, allowCreating: Bool) -> (delta: Int, token: SmartFolderUndoToken?) {
        let before = library.dataVersion
        let token = library.applySmartFolderBatch(p, allowCreatingFolders: allowCreating)
        return (library.dataVersion - before, token)
    }

    private func folder(named name: String) -> AppFolder? {
        library.folders.first { $0.name == name }
    }

    // MARK: - isSmartFolderCandidate

    func testCandidateIsRealLooseApp() {
        library.setApplications([makeApp("Xcode")])
        XCTAssertTrue(library.isSmartFolderCandidate(library.displayOrder[0]))
    }

    func testCandidateExcludesSystemApp() {
        library.setApplications([makeApp("Calculator", system: true)])
        XCTAssertFalse(library.isSmartFolderCandidate(library.displayOrder[0]))
    }

    func testCandidateExcludesHiddenApp() {
        library.setApplications([makeApp("Xcode")])
        library.hiddenAppPaths = ["/Applications/Xcode.app"]
        XCTAssertFalse(library.isSmartFolderCandidate(library.displayOrder[0]))
    }

    func testCandidateExcludesFolderedApp() {
        library.setApplications([makeApp("Xcode")])
        _ = library.createFolder(name: "Dev", appPaths: ["/Applications/Xcode.app"])
        XCTAssertFalse(library.isSmartFolderCandidate(library.displayOrder[0]))
    }

    func testCandidateExcludesUnindexedApp() {
        // An app path that is not in the scanned catalog.
        XCTAssertFalse(library.isSmartFolderCandidate(makeApp("Ghost")))
    }

    func testCandidateExcludesWrapperFolderTile() {
        // A scanner-made wrapper folder tile: isFolder true and a non-.app path.
        let tile = Application(id: "/Applications/Microsoft Office", name: "Microsoft Office",
                               path: "/Applications/Microsoft Office", icon: nil,
                               installationDate: Date(), isFolder: true)
        XCTAssertFalse(library.isSmartFolderCandidate(tile))
    }

    func testCandidateIndependentOfShowHidden() {
        library.setApplications([makeApp("Xcode")])
        library.hiddenAppPaths = ["/Applications/Xcode.app"]
        let app = library.displayOrder[0]
        appModel.settings.showHiddenApps = false
        XCTAssertFalse(library.isSmartFolderCandidate(app))
        appModel.settings.showHiddenApps = true
        XCTAssertFalse(library.isSmartFolderCandidate(app),
            "A hidden app must stay excluded regardless of the show-hidden toggle")
    }

    // MARK: - Apply: dataVersion accounting

    func testApplyBumpsOnceWithNoFolderOpen() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome")])
        let (delta, token) = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Chrome")]]),
                                   allowCreating: true)
        XCTAssertEqual(delta, 1)
        XCTAssertNotNil(token)
        let f = folder(named: "Internet & Communication")
        XCTAssertEqual(Set(f?.appPaths ?? []), Set(["/Applications/Safari.app", "/Applications/Chrome.app"]))
        XCTAssertEqual(f?.smartCategoryKey, "internet-communication")
    }

    func testApplyBumpsTwiceWithFolderOpen() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome"), makeApp("DevApp")])
        let dev = library.createFolder(name: "Dev", appPaths: ["/Applications/DevApp.app"])
        library.openFolder(dev!.id)
        XCTAssertNotNil(library.currentFolderId)

        let (delta, _) = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Chrome")]]),
                               allowCreating: true)
        XCTAssertEqual(delta, 2)
        XCTAssertNil(library.currentFolderId)
    }

    func testNoOpApplyBumpsZero() {
        library.setApplications([makeApp("Safari")])
        _ = library.createFolder(name: "Dev", appPaths: ["/Applications/Safari.app"])
        let (delta, token) = apply(plan([.internetCommunication: [candidate("Safari")]]), allowCreating: true)
        XCTAssertEqual(delta, 0)
        XCTAssertNil(token)
        XCTAssertNil(folder(named: "Internet & Communication"))
    }

    func testNoOpApplyWithFolderOpenStaysOpen() {
        library.setApplications([makeApp("Safari"), makeApp("DevApp")])
        let dev = library.createFolder(name: "Dev", appPaths: ["/Applications/Safari.app", "/Applications/DevApp.app"])
        library.openFolder(dev!.id)
        let (delta, token) = apply(plan([.internetCommunication: [candidate("Safari")]]), allowCreating: true)
        XCTAssertEqual(delta, 0)
        XCTAssertNil(token)
        XCTAssertEqual(library.currentFolderId, dev!.id, "A no-op must not close the open folder")
    }

    // MARK: - Apply: re-validation at apply time

    func testStalePlanDropsMovedApp() {
        library.setApplications([makeApp("Safari"), makeApp("Other")])
        _ = library.createFolder(name: "Dev", appPaths: ["/Applications/Safari.app"])
        _ = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Other")]]), allowCreating: true)
        XCTAssertEqual(folder(named: "Internet & Communication")?.appPaths, ["/Applications/Other.app"],
            "An app moved into a folder mid-wizard must be dropped; only the still-loose one is added")
    }

    func testStalePlanDropsHiddenApp() {
        library.setApplications([makeApp("Safari"), makeApp("Other")])
        library.hiddenAppPaths = ["/Applications/Safari.app"]
        _ = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Other")]]), allowCreating: true)
        XCTAssertEqual(folder(named: "Internet & Communication")?.appPaths, ["/Applications/Other.app"])
    }

    func testStalePlanDropsRemovedApp() {
        library.setApplications([makeApp("Other")])
        _ = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Other")]]), allowCreating: true)
        XCTAssertEqual(folder(named: "Internet & Communication")?.appPaths, ["/Applications/Other.app"],
            "A plan referencing an uninstalled app must drop that entry")
    }

    func testRerunDropsAssignmentsWhenTargetFolderWasDeleted() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome")])
        _ = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari"), candidate("Chrome")]]),
                                          allowCreatingFolders: true)
        if let id = library.folders.first?.id { library.deleteFolder(folderId: id) }
        let (delta, token) = apply(plan([.internetCommunication: [candidate("Safari"), candidate("Chrome")]]),
                                   allowCreating: false)
        XCTAssertEqual(delta, 0)
        XCTAssertNil(token)
        XCTAssertTrue(library.folders.isEmpty)
    }

    func testWrapperFolderPathNeverWritten() {
        library.setApplications([makeApp("Safari")])
        var bad = SmartFolderPlan()
        bad.assignments = [.tools: [
            SmartFolderCandidate(path: "/Applications/Microsoft Office", name: "Microsoft Office"),
            candidate("Safari")
        ]]
        _ = library.applySmartFolderBatch(bad, allowCreatingFolders: true)
        let f = folder(named: "Tools")
        XCTAssertNotNil(f)
        XCTAssertNil(f?.appPaths.first { !$0.hasSuffix(".app") },
            "A non-.app (wrapper) path must never be written into a folder")
    }

    func testNoEmptyFolderCreatedWhenAllCandidatesRevalidateOut() {
        library.setApplications([makeApp("Safari")])
        _ = library.createFolder(name: "Dev", appPaths: ["/Applications/Safari.app"])
        _ = apply(plan([.development: [candidate("Safari")]]), allowCreating: true)
        XCTAssertNil(folder(named: "Development"), "A folder is only created when it receives an app")
    }

    // MARK: - Rerun

    func testRerunIsIdempotent() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome")])
        let p = plan([.internetCommunication: [candidate("Safari"), candidate("Chrome")]])
        _ = library.applySmartFolderBatch(p, allowCreatingFolders: true)
        let countBefore = library.folders.count
        let (delta, token) = apply(p, allowCreating: false)
        XCTAssertEqual(delta, 0)
        XCTAssertNil(token)
        XCTAssertEqual(library.folders.count, countBefore)
    }

    func testNameReuseStampsKey() {
        library.setApplications([makeApp("Safari")])
        _ = library.createFolder(name: "Development", appPaths: [])
        _ = library.applySmartFolderBatch(plan([.development: [candidate("Safari")]]), allowCreatingFolders: false)
        let dev = folder(named: "Development")
        XCTAssertEqual(dev?.smartCategoryKey, "development",
            "Reusing a folder by name must stamp its key so later renames still match")
        XCTAssertEqual(dev?.appPaths, ["/Applications/Safari.app"])
        XCTAssertEqual(library.folders.count, 1)
    }

    func testRenameSurvivesRerun() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome")])
        _ = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                          allowCreatingFolders: true)
        library.renameFolder(folderId: library.folders[0].id, newName: "My Browsers")
        _ = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Chrome")]]),
                                          allowCreatingFolders: false)
        XCTAssertEqual(library.folders.count, 1, "The renamed folder must be found by key, not duplicated")
        XCTAssertEqual(library.folders[0].name, "My Browsers")
        XCTAssertEqual(Set(library.folders[0].appPaths), Set(["/Applications/Safari.app", "/Applications/Chrome.app"]))
    }

    func testExistingFolderMembershipUntouched() {
        library.setApplications([makeApp("Safari"), makeApp("Chrome")])
        _ = library.createFolder(name: "Internet & Communication", appPaths: ["/Applications/Chrome.app"])
        _ = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                          allowCreatingFolders: true)
        let f = folder(named: "Internet & Communication")
        XCTAssertEqual(Set(f?.appPaths ?? []), Set(["/Applications/Chrome.app", "/Applications/Safari.app"]),
            "The pre-existing member is kept and the new app is appended, with no duplicate folder")
        XCTAssertEqual(library.folders.count, 1)
    }

    // MARK: - Undo

    func testUndoCleanRestoresPreApply() {
        library.setApplications([makeApp("Safari")])
        let token = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                                  allowCreatingFolders: true)!
        XCTAssertEqual(library.folders.count, 1)
        library.undoSmartFolderBatch(token)
        XCTAssertEqual(library.folders.count, 0)
        XCTAssertTrue(library.isSmartFolderCandidate(library.displayOrder[0]),
            "After undo the app is loose again")
    }

    func testUndoBumpsOnce() {
        library.setApplications([makeApp("Safari")])
        let token = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                                  allowCreatingFolders: true)!
        let before = library.dataVersion
        library.undoSmartFolderBatch(token)
        XCTAssertEqual(library.dataVersion - before, 1)
    }

    func testUndoAfterMembershipChangeKeepsUserEdits() {
        library.setApplications([makeApp("Safari"), makeApp("Extra")])
        let token = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                                  allowCreatingFolders: true)!
        library.addAppToFolder("/Applications/Extra.app", folderId: library.folders[0].id)
        library.undoSmartFolderBatch(token)
        XCTAssertEqual(library.folders[0].appPaths, ["/Applications/Extra.app"],
            "Undo must remove only the batch's path (Safari) and keep the user's edit (Extra)")
    }

    func testUndoWhileCreatedFolderOpenClosesIt() {
        library.setApplications([makeApp("Safari")])
        let token = library.applySmartFolderBatch(plan([.internetCommunication: [candidate("Safari")]]),
                                                  allowCreatingFolders: true)!
        library.openFolder(library.folders[0].id)
        XCTAssertNotNil(library.currentFolderId)
        let before = library.dataVersion
        library.undoSmartFolderBatch(token)
        XCTAssertEqual(library.dataVersion - before, 2,
            "Undo deletes the created folder, so it must close it: close (1) + apply (1) = 2")
        XCTAssertNil(library.currentFolderId)
        XCTAssertEqual(library.folders.count, 0)
    }

    // MARK: - Persisted untrusted input

    func testGarbageSmartCategoryKeyDroppedOnUserDefaultsLoad() throws {
        // A folder persisted with a garbage key (hand-edited or from a tampered backup) must come
        // back with the key dropped and the folder intact.
        let folder = AppFolder(name: "Legacy", appPaths: [], smartCategoryKey: "bogus-key")
        UserDefaults.standard.set(try JSONEncoder().encode([folder]), forKey: "appFolders")

        let fresh = AppModel()
        XCTAssertEqual(fresh.library.folders.count, 1)
        XCTAssertEqual(fresh.library.folders.first?.name, "Legacy")
        XCTAssertNil(fresh.library.folders.first?.smartCategoryKey,
            "A garbage key in persisted UserDefaults must be dropped on load; the folder is kept")
    }
}
