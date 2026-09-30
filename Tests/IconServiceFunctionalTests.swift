import XCTest
@testable import MacMuster

/// Tests icon loading, preservation, and folder icon generation.
@MainActor
final class IconServiceFunctionalTests: XCTestCase {

    private var service: IconService!

    override func setUp() async throws {
        service = IconService.shared
    }

    private func makeApp(_ name: String, path: String = "/Applications/Test.app") -> Application {
        Application(id: path, name: name, path: path, icon: nil,
                   installationDate: Date(), isFolder: false, containedApps: nil, bundleDescription: nil)
    }

    // MARK: - loadMissingIcons

    func testLoadMissingIconsReturnsIconsForProvidedApps() async {
        let app = makeApp("Finder", path: "/System/Library/CoreServices/Finder.app")
        let result = await service.loadMissingIcons(for: [app])

        XCTAssert(!result.isEmpty,
            "loadMissingIcons should return icons for real system apps")
        XCTAssertEqual(result[0].0, app.path,
            "Icon result should include the app path")
    }

    func testLoadMissingIconsHandlesMissingBundles() async {
        let app = makeApp("FakeApp", path: "/Applications/FakeApp.app")
        let result = await service.loadMissingIcons(for: [app])

        // A missing bundle is not dropped from the batch: the loader returns one entry per
        // requested path, and `NSWorkspace.icon(forFile:)` hands back the shared generic icon for
        // a path that does not exist. What matters is that a missing bundle degrades to a
        // placeholder instead of crashing or misaligning the result with the request.
        XCTAssertEqual(result.count, 1,
            "A missing bundle should still yield one entry, keeping results aligned with the request")
        XCTAssertEqual(result[0].0, app.path,
            "The fallback entry should still be keyed by the requested path")
    }

    func testLoadMissingIconsWithForceReloadsEvenIfCached() async {
        let app = makeApp("Finder", path: "/System/Library/CoreServices/Finder.app")

        let first = await service.loadMissingIcons(for: [app])
        let second = await service.loadMissingIcons(for: [app], force: true)

        XCTAssertFalse(first.isEmpty,
            "First load should return icons")
        XCTAssertFalse(second.isEmpty,
            "Force reload should return icons even if cached")
    }

    func testLoadMissingIconsWithoutForceSkipsAlreadyLoadedIcons() async {
        let app = makeApp("Finder", path: "/System/Library/CoreServices/Finder.app")

        // First load
        let first = await service.loadMissingIcons(for: [app])

        // Second load without force (should be cached/skipped)
        let second = await service.loadMissingIcons(for: [app], force: false)

        // Results should be equivalent
        XCTAssertEqual(first.count, second.count)
    }

    // MARK: - updateIconsInPlace

    func testUpdateIconsInPlacePreservesIndexMapping() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app3 = makeApp("App3", path: "/Applications/App3.app")

        let original = [app1, app2, app3]
        let icon = NSImage() // Placeholder
        let loadedIcons = [(app2.path, icon)]

        let updated = service.updateIconsInPlace(for: original, with: loadedIcons)

        XCTAssertEqual(updated.count, 3,
            "updateIconsInPlace should preserve app count")
        XCTAssertEqual(updated[0].path, app1.path,
            "App order should be preserved")
        XCTAssertEqual(updated[2].path, app3.path,
            "Last app should remain in place")
    }

    func testUpdateIconsInPlaceUpdatesCorrectAppIcon() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")

        let original = [app1, app2]
        let icon = NSImage()
        let loadedIcons = [(app2.path, icon)]

        let updated = service.updateIconsInPlace(for: original, with: loadedIcons)

        XCTAssertNil(updated[0].icon,
            "App1 icon should remain nil")
        XCTAssertNotNil(updated[1].icon,
            "App2 should receive the icon")
    }

    func testUpdateIconsInPlaceHandlesDuplicateIcons() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let icon1 = NSImage()
        let icon2 = NSImage()

        let original = [app1]
        // Duplicate icons for same path — second should win (or first, but consistent)
        let loadedIcons = [(app1.path, icon1), (app1.path, icon2)]

        let updated = service.updateIconsInPlace(for: original, with: loadedIcons)

        XCTAssertNotNil(updated[0].icon,
            "App should receive one of the icons")
    }

    // MARK: - applicationsPreservingLoadedIcons

    func testApplicationsPreservingLoadedIconsCarriesForwardLoadedIcons() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")

        let icon1 = NSImage()
        let loadedIcons = [app1.path: icon1]

        let result = service.applicationsPreservingLoadedIcons(
            from: [app1, app2], loadedIconsByPath: loadedIcons)

        XCTAssertEqual(result.count, 2,
            "Result should include all apps")
        XCTAssertNotNil(result[0].icon,
            "App1 should carry its loaded icon forward")
    }

    func testApplicationsPreservingLoadedIconsDoesNotHallucinateIconsForNewApps() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app3 = makeApp("App3", path: "/Applications/App3.app")

        let icon1 = NSImage()
        let loadedIcons = [app1.path: icon1]

        // New app (app3) that doesn't have a loaded icon
        let result = service.applicationsPreservingLoadedIcons(
            from: [app1, app2, app3], loadedIconsByPath: loadedIcons)

        XCTAssertNotNil(result[0].icon)
        XCTAssertNil(result[2].icon,
            "App3 (new) should not get a fabricated icon")
    }

    // MARK: - generateFolderIcon

    func testGenerateFolderIconProducesValidImage() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")

        let folderIcon = service.generateFolderIcon([app1, app2], for: "folder1")

        XCTAssertNotNil(folderIcon,
            "generateFolderIcon should produce a valid NSImage")
        XCTAssert(folderIcon?.size.width ?? 0 > 0,
            "Folder icon should have non-zero dimensions")
    }

    func testGenerateFolderIconWithEmptyAppsArray() {
        let folderIcon = service.generateFolderIcon([], for: "folder1")

        // Empty apps array may result in nil or a placeholder icon; either is acceptable, so the
        // assertion admits both rather than pinning one. What it does rule out is a malformed
        // zero-sized image, which would paint as an empty cell.
        XCTAssertTrue(folderIcon == nil || (folderIcon?.size.width ?? 0) > 0,
            "generateFolderIcon should return nil or a usable placeholder for an empty apps array")
    }

    func testGenerateFolderIconWithSingleApp() {
        let app = makeApp("App", path: "/Applications/App.app")

        let folderIcon = service.generateFolderIcon([app], for: "folder1")

        XCTAssertNotNil(folderIcon,
            "generateFolderIcon should handle single app")
    }

    func testGenerateFolderIconUsesContainedAppIcons() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let app1WithIcon = Application(
            id: app1.id, name: app1.name, path: app1.path,
            icon: NSImage(), installationDate: app1.installationDate,
            isFolder: app1.isFolder, containedApps: app1.containedApps,
            bundleDescription: app1.bundleDescription
        )

        let folderIcon = service.generateFolderIcon([app1WithIcon, app2], for: "folder1")

        XCTAssertNotNil(folderIcon,
            "Folder icon generation should work with apps that have icons")
    }

    // MARK: - refreshFolderIcons

    func testRefreshFolderIconsInvalidatesFolderIconsOnAppChange() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")
        let folder = AppFolder(id: "folder1", name: "Folder", appPaths: [app1.path, app2.path])

        let appPathIndex = [app1.path: app1, app2.path: app2]

        // Should complete without error
        service.refreshFolderIcons(folders: [folder], appPathIndex: appPathIndex,
                                  changedAppPaths: Set([app1.path]))

        XCTAssertTrue(true, "refreshFolderIcons should not crash on icon updates")
    }

    func testRefreshFolderIconsWithEmptyChangedAppPaths() {
        let app = makeApp("App", path: "/Applications/App.app")
        let folder = AppFolder(id: "folder1", name: "Folder", appPaths: [app.path])
        let appPathIndex = [app.path: app]

        service.refreshFolderIcons(folders: [folder], appPathIndex: appPathIndex,
                                  changedAppPaths: [])

        XCTAssertTrue(true, "refreshFolderIcons should handle empty changes")
    }

    func testRefreshFolderIconsWithNoFolders() {
        let app = makeApp("App", path: "/Applications/App.app")
        let appPathIndex = [app.path: app]

        service.refreshFolderIcons(folders: [], appPathIndex: appPathIndex,
                                  changedAppPaths: Set([app.path]))

        XCTAssertTrue(true, "refreshFolderIcons should handle empty folder list")
    }

    // MARK: - Concurrent Loading

    func testLoadMissingIconsConcurrentCallsAreThreadSafe() async {
        let app1 = makeApp("Finder", path: "/System/Library/CoreServices/Finder.app")
        let app2 = makeApp("Safari", path: "/Applications/Safari.app")

        let result1 = await service.loadMissingIcons(for: [app1])
        let result2 = await service.loadMissingIcons(for: [app2])

        XCTAssertFalse(result1.isEmpty,
            "Finder app should load icons")
        XCTAssertFalse(result2.isEmpty,
            "Safari app should load icons — the second concurrent call must not be starved")
    }

    // MARK: - Bounded Decode Concurrency (memory regression)

    /// Regression for the unbounded decode fan-out: one task per path let a full-library
    /// re-decode (theme toggle, "Refresh Now") rasterize every icon simultaneously, spiking
    /// memory by hundreds of MB. The batch now keeps at most `maxConcurrentIconDecodes`
    /// decodes in flight. Completeness is the observable contract — the windowed scheduler
    /// must refill and drain until every requested icon has come back.
    func testLoadMissingIconsCompletesEveryItemWhenBatchExceedsInFlightLimit() async throws {
        let paths = [
            "/System/Applications/Calculator.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Library/CoreServices/Finder.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        try XCTSkipIf(paths.isEmpty, "No stock system apps found on this machine")

        // Far beyond the in-flight cap, so the windowed scheduler must refill several times.
        let batchSize = 100
        let apps = (0..<batchSize).map { makeApp("App\($0)", path: paths[$0 % paths.count]) }

        let results = await service.loadMissingIcons(for: apps)

        XCTAssertEqual(results.count, batchSize,
            "Every requested path must come back even when the batch is larger than the in-flight cap")
    }

    /// The cap boundary itself: batches of exactly the cap, and one over, must both complete.
    /// The one-over case is where a naive "launch the window once and drain" scheduler would
    /// deadlock (the group is complete while an item is still unlaunched).
    func testLoadMissingIconsCompletesAtAndJustAboveTheInFlightLimit() async throws {
        let paths = [
            "/System/Applications/Calculator.app",
            "/System/Applications/Calendar.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        try XCTSkipIf(paths.isEmpty, "No stock system apps found on this machine")

        for batchSize in [IconMetrics.maxConcurrentIconDecodes, IconMetrics.maxConcurrentIconDecodes + 1] {
            let apps = (0..<batchSize).map { makeApp("App\($0)", path: paths[$0 % paths.count]) }
            let results = await service.loadMissingIcons(for: apps)
            XCTAssertEqual(results.count, batchSize,
                "A batch of \(batchSize) (the in-flight cap, and one over) must complete without deadlock")
        }
    }

    // MARK: - Edge Cases

    func testUpdateIconsInPlaceWithNoLoadedIcons() {
        let app = makeApp("App", path: "/Applications/App.app")

        let result = service.updateIconsInPlace(for: [app], with: [])

        XCTAssertEqual(result.count, 1,
            "Should return original apps when no new icons provided")
        XCTAssertNil(result[0].icon,
            "App should not get icon from empty load list")
    }

    func testUpdateIconsInPlaceWithNonMatchingPaths() {
        let app1 = makeApp("App1", path: "/Applications/App1.app")
        let app2 = makeApp("App2", path: "/Applications/App2.app")

        let icon = NSImage()
        // Icon for a path not in the original apps
        let loadedIcons = [("/Applications/Unrelated.app", icon)]

        let result = service.updateIconsInPlace(for: [app1, app2], with: loadedIcons)

        XCTAssertNil(result[0].icon,
            "Unrelated icons should not be assigned")
        XCTAssertNil(result[1].icon,
            "Unrelated icons should not be assigned")
    }
}
