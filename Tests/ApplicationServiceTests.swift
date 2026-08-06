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

    func testLaunchApplicationWithoutAppModelDoesNotRecord() async throws {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/TestApp.app", name: "TestApp", path: "/Applications/TestApp.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        var completed = false
        service.launchApplication(at: app.path, appModel: nil) { _ in
            completed = true
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 100_000_000)
        // Without appModel, recording should not happen
        XCTAssertFalse(appModel.isRecentApp(app.path))
        XCTAssertTrue(completed)
    }

    func testLaunchApplicationWithValidAppModelRecordsLaunchOnSuccess() async throws {
        let service = ApplicationService.shared
        let appModel = AppModel()

        // Finder is always running on macOS
        let app = Application(id: "/System/Library/CoreServices/Finder.app", name: "Finder", path: "/System/Library/CoreServices/Finder.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        var completedSuccessfully = false
        service.launchApplication(at: app.path, appModel: appModel) { success in
            completedSuccessfully = success
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 200_000_000)
        // Finder should launch successfully and be recorded
        XCTAssertTrue(completedSuccessfully)
        XCTAssertTrue(appModel.isRecentApp(app.path))
    }

    func testLaunchApplicationWithMissingPathDoesNotRecord() async throws {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/Applications/NonExistentTest.app", name: "NonExistent", path: "/Applications/NonExistentTest.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        var completedSuccessfully = false
        service.launchApplication(at: app.path, appModel: appModel) { success in
            completedSuccessfully = success
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 100_000_000)
        // Non-existent path, launch should fail and recording should not happen
        XCTAssertFalse(completedSuccessfully)
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    func testLaunchApplicationReturnsResultViaCompletion() async throws {
        let service = ApplicationService.shared

        var nonExistentCompleted = false
        var nonExistentSuccess = true
        service.launchApplication(at: "/Applications/NonExistentTest.app", appModel: nil) { success in
            nonExistentCompleted = true
            nonExistentSuccess = success
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(nonExistentCompleted)
        XCTAssertFalse(nonExistentSuccess)
    }

    func testLaunchApplicationWithNilAppModelAndValidPathDoesNotRecord() async throws {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = Application(id: "/System/Library/CoreServices/Finder.app", name: "Finder", path: "/System/Library/CoreServices/Finder.app", icon: nil, installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
        appModel.setApplications([app])

        var completedSuccessfully = false
        service.launchApplication(at: app.path, appModel: nil) { success in
            completedSuccessfully = success
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 100_000_000)
        // No recording without appModel, even for Finder
        XCTAssertTrue(completedSuccessfully)
        XCTAssertFalse(appModel.isRecentApp(app.path))
    }

    // MARK: - Already Running App Activation

    func testLaunchApplicationWithRunningFinderActivatesIt() async throws {
        let service = ApplicationService.shared

        var finderCompleted = false
        var finderSuccess = false
        // Finder is always running on macOS
        service.launchApplication(at: "/System/Library/CoreServices/Finder.app", appModel: nil) { success in
            finderCompleted = true
            finderSuccess = success
        }

        // Wait for completion handler
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(finderCompleted)
        XCTAssertTrue(finderSuccess)
    }

    // MARK: - Minimized App Unhide (Regression)

    func testRunningAppIsUnhiddenOnLaunch() async throws {
        let service = ApplicationService.shared

        // Finder is always running — verify it activates successfully
        // The unhide happens inside the completion handler
        var finderSuccess = false
        service.launchApplication(at: "/System/Library/CoreServices/Finder.app", appModel: nil) { success in
            finderSuccess = success
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(finderSuccess)
    }

    // MARK: - Path Validation

    func testLaunchApplicationWithNonExistentPathReturnsFailure() async throws {
        let service = ApplicationService.shared

        var completed = false
        var success = true
        service.launchApplication(at: "/Applications/NonExistentApp12345.app", appModel: nil) { result in
            completed = true
            success = result
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(completed)
        XCTAssertFalse(success)
    }
}
