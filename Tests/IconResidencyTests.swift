import XCTest
import AppKit
@testable import MacMuster

/// Covers what `IconCacheManager.cacheIcon` keeps resident. It must hand back the compressed,
/// lazily decoded PNG form — the one a warm start gets from disk — and not the freshly rasterized
/// bitmap: 228 retained 200×200 bitmaps measured 89 MB steady against 52 MB for the same library
/// loaded from a warm cache.
@MainActor
final class IconResidencyTests: XCTestCase {

    private var paths: [String] = []

    override func setUp() async throws {
        IconCacheManager.shared.clearAll()
        paths = []
    }

    override func tearDown() async throws {
        IconCacheManager.shared.clearAll()
        for path in paths { try? FileManager.default.removeItem(atPath: path) }
        paths = []
    }

    /// An existing directory is all the cache needs to treat a path as a bundle (it keys on mtime).
    private func makeBundle() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("Residency-\(UUID().uuidString).app").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        paths.append(path)
        return path
    }

    private func bitmap(px: Int, red: CGFloat) -> NSImage {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: 0.2, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: px, height: px))
    }

    private func pixelWidth(_ image: NSImage?) -> Int? {
        image?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width
    }

    // MARK: - What cacheIcon returns

    func testCacheIconReturnsThePngBackedImageNotTheBitmap() throws {
        let path = try makeBundle()
        let original = bitmap(px: 200, red: 0.9)

        let resident = IconCacheManager.shared.cacheIcon(original, for: path, appearance: .light)

        XCTAssertFalse(resident === original, "The rasterized bitmap must not be what stays resident")
        XCTAssertEqual(pixelWidth(resident), 200)
        XCTAssertEqual(resident.size, original.size, "Point size must be preserved so callers see the same icon")
    }

    func testMemoryHitReturnsTheSameResidentInstance() throws {
        let path = try makeBundle()
        let resident = IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: 0.5), for: path, appearance: .light)
        XCTAssertTrue(IconCacheManager.shared.cachedIcon(for: path, appearance: .light) === resident)
    }

    func testIconIsStillWrittenToDiskAndReadableAfterMemoryEviction() throws {
        let path = try makeBundle()
        IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: 0.7), for: path, appearance: .light)

        IconCacheManager.shared.evictMemoryVariants(for: [path], appearance: .light)
        let fromDisk = IconCacheManager.shared.cachedIcon(for: path, appearance: .light)

        XCTAssertEqual(pixelWidth(fromDisk), 200, "The PNG written to disk must round-trip at full size")
    }

    func testCacheIconForAPathWithNoBundleReturnsTheInputUnchanged() {
        let original = bitmap(px: 64, red: 0.3)
        let result = IconCacheManager.shared.cacheIcon(original, for: "/NonExistent/Path-\(UUID().uuidString).app", appearance: .light)
        XCTAssertTrue(result === original, "With nothing to cache against, hand back what was given")
    }

    // MARK: - Resident form

    /// `CGImage.utType` is the source's type for an image created from a PNG and nil for one made
    /// from a bitmap context, so it tells the lazily decoded PNG-backed form from a rasterized
    /// bitmap without decoding anything. (A footprint-delta test was tried and dropped: ImageIO's
    /// encoder state makes the number too noisy to assert on.)
    private func isPngBacked(_ image: NSImage) -> Bool {
        (image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.utType as String?) == "public.png"
    }

    func testTheBitmapWeStartFromIsNotPngBacked() {
        XCTAssertFalse(isPngBacked(bitmap(px: 200, red: 0.1)),
            "Sanity check: if a raw bitmap reported public.png, the assertions below would prove nothing")
    }

    func testResidentIconIsPngBacked() throws {
        let path = try makeBundle()
        let resident = IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: 0.4), for: path, appearance: .light)
        XCTAssertTrue(isPngBacked(resident), "The returned icon must be the lazily decoded PNG form")
    }

    func testEveryColdIconStaysPngBacked() throws {
        for i in 0..<20 {
            let path = try makeBundle()
            let resident = IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: CGFloat(i) / 20), for: path, appearance: .light)
            XCTAssertTrue(isPngBacked(resident), "Icon \(i) was kept as a decoded bitmap")
            XCTAssertTrue(isPngBacked(IconCacheManager.shared.cachedIcon(for: path, appearance: .light) ?? bitmap(px: 1, red: 0)),
                "The memory-cached copy of icon \(i) must be PNG-backed too")
        }
    }

    func testIconStampedWithPreRasterMtimeIsStaleAfterBundleMoved() throws {
        let path = try makeBundle()
        // The bundle was read as older than it is now (an update landed during rasterization).
        IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: 0.5), for: path, appearance: .light,
                                          bundleMtime: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: path, appearance: .light),
                     "An icon drawn from the old bundle must not be served as current")
    }

    func testCorruptCachedPngIsDeleted() throws {
        let path = try makeBundle()
        IconCacheManager.shared.cacheIcon(bitmap(px: 200, red: 0.5), for: path, appearance: .light)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MacMuster/icons-v4")
            .appendingPathComponent(IconCacheManager.shared.cacheKey(for: path, appearance: .light))
        try Data("not a png".utf8).write(to: file)
        IconCacheManager.shared.evictMemoryVariants(for: [path], appearance: .light)

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: path, appearance: .light))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "A corrupt PNG must be removed, not re-read every session")
    }
}
