import XCTest
@testable import MacMuster

/// Covers `SmartFolderPlanBuilder` — the main-actor orchestration that turns the live catalog into a
/// plan. The test apps use fake paths (no real `Info.plist`), so classification falls to the name
/// tier; the point is the wiring (candidate filtering + off-main bundle read + classify), not the
/// catalog itself.
@MainActor
final class SmartFolderPlanBuilderTests: XCTestCase {

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

    private func makeApp(_ name: String, system: Bool = false) -> Application {
        let dir = system ? "/System/Applications" : "/Applications"
        let path = "\(dir)/\(name).app"
        return Application(id: path, name: name, path: path, icon: nil, installationDate: Date(), isFolder: false)
    }

    func testEmptyCatalogYieldsEmptyPlan() async {
        library.setApplications([])
        let plan = await SmartFolderPlanBuilder.build(library: library)
        XCTAssertEqual(plan.assignedCount, 0)
        XCTAssertTrue(plan.loose.isEmpty)
    }

    func testBuilderClassifiesLooseAppsByNameTier() async {
        library.setApplications([makeApp("Safari"), makeApp("Xcode"), makeApp("Spotify")])
        let plan = await SmartFolderPlanBuilder.build(library: library)

        // No real bundles on these fake paths, so the name tier decides.
        XCTAssertEqual(plan.assignedCount, 3)
        XCTAssertEqual(plan.assignments[.internetCommunication]?.first?.name, "Safari")
        XCTAssertEqual(plan.assignments[.development]?.first?.name, "Xcode")
        XCTAssertEqual(plan.assignments[.mediaEntertainment]?.first?.name, "Spotify")
    }

    func testBuilderExcludesFolderedAndSystemApps() async {
        library.setApplications([makeApp("Safari"), makeApp("Calculator", system: true)])
        _ = library.createFolder(name: "Dev", appPaths: ["/Applications/Safari.app"])

        let plan = await SmartFolderPlanBuilder.build(library: library)

        // Safari is already in a folder and Calculator is a system app, so nothing is classifiable.
        XCTAssertEqual(plan.assignedCount, 0)
        XCTAssertTrue(plan.loose.isEmpty)
    }

    func testBuilderLeavesUnclassifiableAppsLoose() async {
        // A name that matches no tier stays loose, not dropped.
        library.setApplications([makeApp("Zzqq NotARealApp")])
        let plan = await SmartFolderPlanBuilder.build(library: library)

        XCTAssertEqual(plan.assignedCount, 0)
        XCTAssertEqual(plan.loose.count, 1)
        XCTAssertEqual(plan.loose.first?.path, "/Applications/Zzqq NotARealApp.app")
    }
}
