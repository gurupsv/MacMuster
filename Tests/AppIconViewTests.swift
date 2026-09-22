import XCTest
import AppKit
@testable import MacMuster

/// Regression tests for the "blank icons on first launch" bug.
///
/// `LazyVGrid`'s `ForEach` does not reliably re-invoke a cell's content closure once it has
/// materialized a row for a given identity — an icon finishing its async decode bumps
/// `dataVersion` and gets `getDisplayedApps()` a fresh `Application` value with the icon
/// attached, but an already-on-screen `AppIconView` cell can keep running its *old* body with the
/// *stale* `Application` snapshot (`icon == nil`) it was originally constructed with, forever.
/// The grid only recovers when something swaps the whole displayed set (opening/closing a
/// folder), which is what made this look fixable by navigating away and back.
///
/// `AppIconView.currentIcon` is the fix: it re-resolves the icon from `appModel.library
/// .appPathIndex` (an `@Observable`-tracked property) by path instead of trusting the `app` value
/// handed to the cell, so a direct Observation dependency forces the redraw regardless of what
/// the lazy grid's own diffing decided. These tests hold `currentIcon` to that contract using a
/// deliberately stale `Application` snapshot, the exact shape of the bug.
@MainActor
final class AppIconViewTests: XCTestCase {

    private var appModel: AppModel!

    override func setUp() async throws {
        clearAllUserDefaultsState()
        appModel = AppModel()
    }

    override func tearDown() async throws {
        clearAllUserDefaultsState()
        appModel = nil
    }

    nonisolated func clearAllUserDefaultsState() {
        let keys = [
            "appFolders", "hiddenAppPaths", "customDirectories", "customDirectoryBookmarks",
            "currentFolderId", "customOrder", "sortOption", "columnCount"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The exact scenario that shipped blank: a cell constructed while `app.icon == nil`, and the
    /// model loading a real icon for that same path afterwards — without ever handing this cell a
    /// fresh `Application` value.
    func testCurrentIconPrefersTheLiveLibraryIconOverAStaleSnapshot() async throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let path = "/System/Applications/Calculator.app"
        let staleApp = Application(
            id: path, name: "Calculator", path: path, icon: nil, installationDate: Date(),
            isFolder: false, containedApps: nil
        )
        appModel.setApplications([staleApp])
        XCTAssertNil(appModel.library.appPathIndex[path]?.icon, "Precondition: no icon loaded yet")

        await appModel.library.loadMissingIcons()
        XCTAssertNotNil(appModel.library.appPathIndex[path]?.icon,
            "Precondition: the library now has a real icon for this path")

        // `staleApp` is the *original* value — exactly what a `LazyVGrid` cell that never got
        // re-invoked would still be holding, with `icon == nil`.
        let cell = AppIconView(appModel: appModel, app: staleApp)
        XCTAssertNotNil(cell.currentIcon,
            "currentIcon must resolve the live icon by path, not the stale snapshot's nil")
    }

    /// Folder tiles are synthesized on the fly by `getFolderApplication` and never appear in
    /// `appPathIndex` — `currentIcon` must fall back to the value it was actually given rather
    /// than treating a missing index entry as "no icon".
    func testCurrentIconFallsBackToTheGivenIconWhenPathIsNotInTheLibraryIndex() {
        let folderIcon = NSImage(size: NSSize(width: 4, height: 4))
        let folderApp = Application(
            id: "folder-1", name: "My Folder", path: "folder-1", icon: folderIcon,
            installationDate: Date(), isFolder: true, containedApps: ["/some/App.app"],
            folderId: "folder-1"
        )
        XCTAssertNil(appModel.library.appPathIndex["folder-1"],
            "Precondition: folder tiles are not real scanned apps, so they aren't indexed")

        let cell = AppIconView(appModel: appModel, app: folderApp)
        XCTAssertTrue(cell.currentIcon === folderIcon,
            "With no library entry for this path, currentIcon must fall back to the app's own icon")
    }
}
