import XCTest
@testable import MacMuster

/// Regression coverage for the first-launch icon-loading stall: `IconService.loadMissingIcons`
/// must decode icons concurrently (via `withTaskGroup`), not one at a time on a single
/// background thread. A serial `.map` turned a sub-second batch into a multi-second stall
/// before icons appeared on first launch.
final class IconServicePerformanceTests: XCTestCase {

    /// Stock macOS apps that ship with every Mac, so the test doesn't depend on whatever the
    /// machine running it (developer or CI) happens to have installed in /Applications.
    private func systemAppPaths() -> [String] {
        let candidates = [
            "/System/Applications/Calculator.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Maps.app",
            "/System/Applications/Reminders.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Utilities/Terminal.app",
            "/System/Applications/Utilities/Activity Monitor.app",
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private func makeApp(path: String, index: Int) -> Application {
        Application(id: "\(path)#\(index)", name: "Bench\(index)", path: path, icon: nil,
                     installationDate: Date(), isFolder: false, containedApps: nil,
                     bundleDescription: nil)
    }

    /// Tests that the force parameter bypasses the icon == nil filter, re-decoding icons
    /// that are already loaded. This is critical for the appearance-change handler and for
    /// refreshCachedIcons to work correctly — without force: true, apps with already-loaded
    /// icons are silently skipped.
    func testLoadMissingIconsWithForceTrueRedecodesLoadedIcons() async throws {
        let paths = systemAppPaths()
        try XCTSkipIf(paths.count < 1, "At least 1 stock system app required")

        let path = paths[0]
        let app = makeApp(path: path, index: 0)

        // Pre-load the icon so icon != nil
        let preloadedIcons = await IconService.shared.loadMissingIcons(for: [app])
        XCTAssertFalse(preloadedIcons.isEmpty, "Should load icon on first call")

        var appWithIcon = app
        if let (_, icon) = preloadedIcons.first {
            appWithIcon.icon = icon
        }

        // Call with force: false (default) — should skip the app since it already has an icon
        let skipped = await IconService.shared.loadMissingIcons(for: [appWithIcon], force: false)
        XCTAssertTrue(skipped.isEmpty, "force: false should skip apps that already have icons")

        // Call with force: true — should re-decode despite the icon already being loaded
        let reloaded = await IconService.shared.loadMissingIcons(for: [appWithIcon], force: true)
        XCTAssertFalse(reloaded.isEmpty, "force: true should re-decode even when icon != nil")
    }

    /// Asserts that loading a batch of icons takes far less wall-clock time than doing the
    /// same number of single-icon loads back to back — true only if multiple icons decode
    /// concurrently. If `loadMissingIcons` regresses to a serial `.map`, the batch time
    /// converges to (per-item time × batch size) and this test fails.
    func testLoadMissingIconsDecodesIconsConcurrently() async throws {
        let paths = systemAppPaths()
        try XCTSkipIf(paths.count < 3, "Fewer than 3 stock system apps found on this machine — can't benchmark")

        let batchSize = 80
        let apps = (0..<batchSize).map { makeApp(path: paths[$0 % paths.count], index: $0) }

        // Warm up: the first-ever icon lookup in the process pays one-time setup costs that
        // would otherwise pollute the per-item baseline measured below.
        _ = await IconService.shared.loadMissingIcons(for: [apps[0]])

        let singleStart = Date()
        _ = await IconService.shared.loadMissingIcons(for: [apps[1]])
        let perItemEstimate = Date().timeIntervalSince(singleStart)

        let batchStart = Date()
        _ = await IconService.shared.loadMissingIcons(for: apps)
        let batchElapsed = Date().timeIntervalSince(batchStart)

        let serialEstimate = perItemEstimate * Double(batchSize)

        // Require at least ~1.67x speedup over the serial estimate. Real hardware sees far
        // more (9-12x on a multi-core Mac in manual benchmarking), so this leaves generous
        // headroom for slow/virtualized CI while still failing hard if concurrency is lost
        // entirely (ratio would be ~1.0).
        XCTAssertLessThan(
            batchElapsed, serialEstimate * 0.6,
            """
            Loading \(batchSize) icons took \(String(format: "%.3f", batchElapsed))s, which is not \
            meaningfully faster than the \(String(format: "%.3f", serialEstimate))s a serial, \
            one-at-a-time decode would take at \(String(format: "%.3f", perItemEstimate))s/icon. \
            IconService.loadMissingIcons should fan icon decoding out across withTaskGroup so \
            icons decode concurrently instead of one at a time — see IconService.swift.
            """
        )
    }

    /// Generous absolute ceiling, independent of the relative comparison above: even if some
    /// future change slows down icon decoding uniformly (so the concurrency ratio test above
    /// wouldn't notice), a real batch of icons should never take seconds to load.
    func testLoadMissingIconsCompletesQuickly() async throws {
        let paths = systemAppPaths()
        try XCTSkipIf(paths.count < 3, "Fewer than 3 stock system apps found on this machine — can't benchmark")

        let batchSize = 80
        let apps = (0..<batchSize).map { makeApp(path: paths[$0 % paths.count], index: $0) }

        let start = Date()
        _ = await IconService.shared.loadMissingIcons(for: apps)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 3.0, "Loading \(batchSize) icons took \(elapsed)s — first-launch icon loading should never take seconds.")
    }
}
