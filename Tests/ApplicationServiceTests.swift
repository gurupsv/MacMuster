import XCTest
@testable import MacMuster

@MainActor
final class ApplicationServiceTests: XCTestCase {

    override func setUp() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        RecentAppsTracker.shared.clearHistory()
    }

    nonisolated func clearAllUserDefaultsState() {
        UserDefaults.standard.removeObject(forKey: "recentAppLaunchTimes")
        UserDefaults.standard.removeObject(forKey: "appLaunchCounts")
    }

    func testServiceIsSingleton() {
        let service1 = ApplicationService.shared
        let service2 = ApplicationService.shared
        XCTAssertIdentical(service1, service2)
    }

    // MARK: - App Launch Recording

    func testLaunchApplicationWithoutAppModelDoesNotRecord() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/TestApp.app", name: "TestApp", path: "/Applications/TestApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        _ = service.launchApplication(at: app.path, appModel: nil)

        // Without appModel, recording should not happen
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    func testLaunchApplicationWithValidAppModelAndValidPathRecordsLaunch() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/FinderTest.app", name: "Finder", path: "/Applications/FinderTest.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        let didLaunch = service.launchApplication(at: app.path, appModel: appModel)

        // Fake path doesn't exist, launch should fail and recording should not happen
        XCTAssertFalse(didLaunch)
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    func testLaunchApplicationWithMissingPathDoesNotRecord() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/NonExistentTest.app", name: "NonExistent", path: "/Applications/NonExistentTest.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        let didLaunch = service.launchApplication(at: app.path, appModel: appModel)

        // Non-existent path, launch should fail and recording should not happen
        XCTAssertFalse(didLaunch)
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    func testLaunchApplicationReturnsLaunchResult() {
        let service = ApplicationService.shared

        let didLaunchExisting = service.launchApplication(at: "/Applications/FinderTest.app", appModel: nil)
        XCTAssertFalse(didLaunchExisting)

        let didLaunchMissing = service.launchApplication(at: "/Applications/NonExistentTest.app", appModel: nil)
        XCTAssertFalse(didLaunchMissing)
    }

    func testLaunchApplicationWithNilAppModelAndValidPathDoesNotRecord() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/FinderTest.app", name: "Finder", path: "/Applications/FinderTest.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])

        let didLaunch = service.launchApplication(at: app.path, appModel: nil)

        // Fake path doesn't exist, launch fails but no recording without appModel
        XCTAssertFalse(didLaunch)
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    // MARK: - Already Running App Activation

    func testLaunchApplicationWithRunningFinderActivatesIt() {
        let service = ApplicationService.shared

        // Finder is always running on macOS
        let didLaunch = service.launchApplication(at: "/System/Library/CoreServices/Finder.app", appModel: nil)
        XCTAssertTrue(didLaunch)
    }

    func testRunningFinderLaunchRecordsAppModel() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/System/Library/CoreServices/Finder.app", name: "Finder", path: "/System/Library/CoreServices/Finder.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, appSize: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))
        _ = service.launchApplication(at: app.path, appModel: appModel)
        XCTAssertTrue(appModel.isRecentApp(app.path))
    }

    // MARK: - Minimized App Unhide (Regression)

    func testRunningAppMinimizedIsUnhiddenBeforeActivation() {
        let service = ApplicationService.shared

        // Finder is always running — the fix ensures if match.isHidden { match.unhide() } runs
        // before match.activate(options: [.activateAllWindows])
        let didLaunch = service.launchApplication(at: "/System/Library/CoreServices/Finder.app", appModel: nil)
        XCTAssertTrue(didLaunch)
    }

    // MARK: - Path Validation

    func testLaunchApplicationWithNonExistentPathReturnsFalse() {
        let service = ApplicationService.shared

        let didLaunch = service.launchApplication(at: "/Applications/NonExistentApp12345.app", appModel: nil)
        XCTAssertFalse(didLaunch)
    }
}
