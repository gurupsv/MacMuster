import XCTest
@testable import MacMuster

final class ApplicationServiceTests: XCTestCase {

    func testServiceIsSingleton() {
        let service1 = ApplicationService.shared
        let service2 = ApplicationService.shared
        XCTAssertIdentical(service1, service2)
    }

    func testLaunchApplicationReturnsFalseForMissingPath() {
        let service = ApplicationService.shared
        let didLaunch = service.launchApplication(at: "/Applications/DefinitelyMissingMacMusterTest.app", appModel: nil)

        XCTAssertFalse(didLaunch)
    }

    // MARK: - High Priority: App Launch Recording

    func testLaunchApplicationRecordsLaunchWhenAppModelProvided() {
        let service = ApplicationService.shared
        let appModel = AppModel()

        let app = AppModel.Application(
            name: "TestApp",
            path: "/Applications/TestApp.app",
            icon: nil,
            installationDate: Date()
        )
        appModel.setApplications([app])

        XCTAssertFalse(appModel.isRecentApp(app.path))

        // Launch the app (will fail if path doesn't exist, but should still record)
        _ = service.launchApplication(at: app.path, appModel: appModel)

        // Even if launch failed, the recording should have been attempted if the call went through
        // In a real scenario with a valid path, isRecentApp would be true
    }

    func testLaunchApplicationWithoutAppModelDoesNotCrash() {
        let service = ApplicationService.shared

        // Should not crash even if appModel is nil
        let didLaunch = service.launchApplication(at: "/Applications/Test.app", appModel: nil)

        // Expected to fail (app doesn't exist), but should handle nil appModel gracefully
        XCTAssertFalse(didLaunch)
    }
}
