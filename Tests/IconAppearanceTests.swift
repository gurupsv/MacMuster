import XCTest
@testable import MacMuster

/// Coverage for per-appearance icon caching. Appearance is an explicit parameter throughout the
/// cache API, so these tests name the variant directly rather than mutating `NSApp.appearance` —
/// no dependence on an application object or on the machine's current theme.
final class IconAppearanceTests: XCTestCase {

    private let calculator = "/System/Applications/Calculator.app"

    override func setUp() {
        super.setUp()
        IconCacheManager.shared.clearAll()
    }

    override func tearDown() {
        IconCacheManager.shared.clearAll()
        super.tearDown()
    }

    private func swatch(_ color: NSColor, size: CGFloat = 32) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private func requireCalculator() throws {
        guard FileManager.default.fileExists(atPath: calculator) else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
    }

    // MARK: - Appearance-Aware Cache Keys

    func testCacheKeyDiffersByAppearance() {
        let path = "/Applications/Safari.app"
        let light = IconCacheManager.shared.cacheKey(for: path, appearance: .light)
        let dark = IconCacheManager.shared.cacheKey(for: path, appearance: .dark)

        XCTAssertNotEqual(light, dark, "Light and dark variants must not share a cache file")
        XCTAssertEqual(light.count, 64, "Cache key should be a 64-char SHA256 digest")
        XCTAssertEqual(dark.count, 64, "Cache key should be a 64-char SHA256 digest")
        XCTAssertEqual(light, IconCacheManager.shared.cacheKey(for: path, appearance: .light),
            "Cache key should be deterministic for a given path and appearance")
    }

    func testCachedIconIsNotVisibleToTheOtherAppearance() throws {
        try requireCalculator()
        let icon = swatch(.red, size: 64)

        IconCacheManager.shared.cacheIcon(icon, for: calculator, appearance: .light)

        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: calculator, appearance: .light),
            "Icon should be retrievable under the appearance it was cached for")
        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: calculator, appearance: .dark),
            "A light-mode icon must never be served for a dark-mode request — that is the stale-icon bug")
    }

    // MARK: - Duplicate Cache Entries (crash regression)

    /// Regression for the crash on `com.apple.root.utility-qos.cooperative`: caching one app
    /// under both appearances wrote two `.meta` files that each recorded only `appPath`, so
    /// `cachedAppPaths()` returned the same path twice. `refreshCachedIcons` fed that list to
    /// `Dictionary(uniqueKeysWithValues:)`, which traps on duplicate keys — killing the app
    /// hours after launch, but only once the user had toggled appearance at least once.
    func testCachedAppPathsHasNoDuplicatePaths() throws {
        try requireCalculator()
        let icon = swatch(.red)

        // Cache the same app under both appearances — what happens the first time a user
        // toggles the system theme.
        IconCacheManager.shared.cacheIcon(icon, for: calculator, appearance: .light)
        IconCacheManager.shared.cacheIcon(icon, for: calculator, appearance: .dark)

        XCTAssertEqual(IconCacheManager.shared.allCachedAppPaths().count, 1,
            "Precondition: both variants belong to one app")

        for appearance in IconAppearance.allCases {
            let cached = IconCacheManager.shared.cachedAppPaths(appearance: appearance)
            let paths = cached.map(\.appPath)
            XCTAssertEqual(Set(paths).count, paths.count,
                "cachedAppPaths(\(appearance.rawValue)) returned a path twice — the duplicate is what trapped Dictionary(uniqueKeysWithValues:)")
            XCTAssertEqual(paths, [calculator], "Each appearance should see exactly its own variant")
        }
    }

    /// Both appearance variants exist on disk, so pruning a deleted app must reclaim both —
    /// not just the one matching whatever appearance happens to be active at prune time.
    func testPruneReclaimsVariantForNonCurrentAppearance() throws {
        try requireCalculator()

        // Cache under dark only; the "current" appearance for the listing below is light.
        IconCacheManager.shared.cacheIcon(swatch(.blue), for: calculator, appearance: .dark)

        XCTAssertTrue(IconCacheManager.shared.cachedAppPaths(appearance: .light).isEmpty,
            "Precondition: the dark variant is invisible to a light-appearance listing")
        XCTAssertTrue(IconCacheManager.shared.allCachedAppPaths().contains(calculator),
            "The dark variant should be visible to the appearance-independent listing")

        IconCacheManager.shared.pruneDeletedApps(currentAppPaths: Set())

        XCTAssertFalse(IconCacheManager.shared.allCachedAppPaths().contains(calculator),
            "pruneDeletedApps must reclaim variants cached under other appearances")
    }

    func testPruneRemovesBothVariantsOfADeletedApp() throws {
        try requireCalculator()
        IconCacheManager.shared.cacheIcon(swatch(.blue), for: calculator, appearance: .light)
        IconCacheManager.shared.cacheIcon(swatch(.blue), for: calculator, appearance: .dark)

        IconCacheManager.shared.pruneDeletedApps(currentAppPaths: Set())

        for appearance in IconAppearance.allCases {
            XCTAssertNil(IconCacheManager.shared.cachedIcon(for: calculator, appearance: appearance),
                "pruneDeletedApps should remove the \(appearance.rawValue) variant")
        }
    }

    // MARK: - Rasterization Honors the Requested Appearance

    /// The decode must render the appearance it is told to, not the one the drawing thread
    /// happens to inherit. Otherwise a theme toggle mid-batch bakes the new variant into a
    /// bitmap that then gets filed under the old appearance's key, where nothing corrects it.
    func testRasterizeRendersRequestedAppearance() throws {
        // Find a stock app that actually ships distinct light/dark artwork.
        let candidates = [
            "/System/Applications/Calculator.app", "/System/Applications/Notes.app",
            "/System/Applications/Mail.app", "/System/Applications/Maps.app",
            "/System/Applications/Reminders.app", "/System/Applications/Utilities/Terminal.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }

        func pngBytes(_ image: NSImage) -> Data? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }

        let pair = candidates.lazy.compactMap { path -> (String, Data, Data)? in
            guard let light = pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .light)),
                  let dark = pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .dark)),
                  light != dark else { return nil }
            return (path, light, dark)
        }.first

        guard let (path, light, dark) = pair else {
            throw XCTSkip("No stock app on this machine ships distinct light/dark icon artwork")
        }

        // Re-rendering must be stable and must track the requested appearance, whichever
        // appearance the calling thread happens to be running under.
        XCTAssertEqual(pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .light)), light,
            "Rasterizing for light twice should produce identical bytes")
        XCTAssertEqual(pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .dark)), dark,
            "Rasterizing for dark twice should produce identical bytes")
    }

    /// The decode runs on the cooperative pool, so pinning must work off the main thread too —
    /// a background thread inherits the app's appearance rather than the requested one unless
    /// the draw is explicitly wrapped.
    func testRasterizeHonorsAppearanceOffTheMainThread() async throws {
        let candidates = [
            "/System/Applications/Calculator.app", "/System/Applications/Notes.app",
            "/System/Applications/Mail.app", "/System/Applications/Maps.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }

        func pngBytes(_ image: NSImage) -> Data? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }

        guard let path = candidates.first(where: { p in
            guard let l = pngBytes(IconService.rasterize(p, pixelSize: 128, appearance: .light)),
                  let d = pngBytes(IconService.rasterize(p, pixelSize: 128, appearance: .dark)) else { return false }
            return l != d
        }) else {
            throw XCTSkip("No stock app on this machine ships distinct light/dark icon artwork")
        }

        let onMain = (
            light: pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .light)),
            dark: pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .dark))
        )

        let offMain = await Task.detached(priority: .utility) { () -> (Data?, Data?) in
            (pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .light)),
             pngBytes(IconService.rasterize(path, pixelSize: 128, appearance: .dark)))
        }.value

        XCTAssertEqual(offMain.0, onMain.light, "Light variant must match regardless of which thread decodes it")
        XCTAssertEqual(offMain.1, onMain.dark, "Dark variant must match regardless of which thread decodes it")
        XCTAssertNotEqual(offMain.0, offMain.1, "The two variants must stay distinct off the main thread")
    }

    // MARK: - Clear All Behavior

    func testClearAllRemovesEveryAppearanceVariant() throws {
        try requireCalculator()
        IconCacheManager.shared.cacheIcon(swatch(.green), for: calculator, appearance: .light)
        IconCacheManager.shared.cacheIcon(swatch(.green), for: calculator, appearance: .dark)

        IconCacheManager.shared.clearAll()

        for appearance in IconAppearance.allCases {
            XCTAssertNil(IconCacheManager.shared.cachedIcon(for: calculator, appearance: appearance),
                "clearAll should remove the \(appearance.rawValue) variant")
        }
        XCTAssertTrue(IconCacheManager.shared.allCachedAppPaths().isEmpty,
            "clearAll should leave no entries on disk")
    }
}
