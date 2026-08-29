import XCTest
@testable import MacMuster

/// Covers **PERF-1**: an app updated while MacMuster was running kept its old icon, and the
/// six-hourly `refreshCachedIcons` job could never find anything to refresh.
///
/// Two separate defects produced that, and fixing either alone changes nothing:
///
/// 1. `currentBundleModificationTime` returned the cached value when one existed, and the cache
///    was only ever written by that same method — so after the first read of a path, nothing
///    re-read the disk for the rest of the session. Staleness checks compared a recorded mtime
///    against itself and always concluded "fresh".
/// 2. `cachedIcon` returned in-memory hits before checking anything, and `loadMissingIcons(force:)`
///    re-loads through `cachedIcon` — so even a correct disk-layer check would hand the stale
///    image straight back out of memory.
///
/// These tests drive real files whose mtimes are moved on disk, so they fail against either
/// half-fix.
final class IconStalenessTests: XCTestCase {

    private var bundlePath: String!

    override func setUpWithError() throws {
        // A temp directory stands in for an app bundle: the cache only ever stats the path.
        bundlePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("StalenessTest-\(UUID().uuidString).app", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let bundlePath {
            IconCacheManager.shared.pruneDeletedApps(currentAppPaths: [])
            try? FileManager.default.removeItem(atPath: bundlePath)
        }
        bundlePath = nil
    }

    // MARK: - Helpers

    private func setMtime(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: bundlePath)
    }

    private func makeIcon(_ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    // MARK: - Defect 1: the mtime read must actually hit the disk

    func testModificationTimeIsRereadFromDiskAfterTheBundleChanges() throws {
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try setMtime(past)
        let first = IconCacheManager.shared.currentBundleModificationTime(for: bundlePath)
        XCTAssertEqual(first.map { Int($0.timeIntervalSince1970) }, Int(past.timeIntervalSince1970),
            "Precondition: the first read should report the mtime just set")

        // Move the bundle's mtime the way an app update does.
        let later = past.addingTimeInterval(5000)
        try setMtime(later)

        let second = IconCacheManager.shared.currentBundleModificationTime(for: bundlePath)

        XCTAssertEqual(second.map { Int($0.timeIntervalSince1970) }, Int(later.timeIntervalSince1970),
            "A second read must report the new mtime — returning the memoized one is what made icon invalidation inert")
    }

    func testModificationTimeReturnsNilForAMissingBundle() throws {
        XCTAssertNil(IconCacheManager.shared.currentBundleModificationTime(for: "/NonExistent/Nope.app"),
            "A path that cannot be statted has no mtime")
    }

    // MARK: - Defect 2: a memory hit must be validated too

    func testCachedIconIsDiscardedWhenTheBundleChangesMidSession() throws {
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try setMtime(past)
        IconCacheManager.shared.cacheIcon(makeIcon(.red, size: 64), for: bundlePath, appearance: .light)
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light),
            "Precondition: the icon should be served from cache while the bundle is unchanged")

        // The app updates underneath us — exactly the case the badge and the refresh job care about.
        try setMtime(past.addingTimeInterval(5000))

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light),
            "Once the bundle's mtime moves, the cached icon must not be served — including from the in-memory layer")
    }

    func testCachedIconIsStillServedWhenTheBundleHasNotChanged() throws {
        try setMtime(Date(timeIntervalSince1970: 1_600_000_000))
        IconCacheManager.shared.cacheIcon(makeIcon(.green, size: 48), for: bundlePath, appearance: .light)

        // Repeated reads of an unchanged bundle must keep hitting the cache — the fix must not
        // turn every lookup into a re-decode.
        for attempt in 1...3 {
            let cached = IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light)
            XCTAssertNotNil(cached, "Read \(attempt): an unchanged bundle should keep serving its cached icon")
            XCTAssertEqual(cached?.size.width, 48, "Read \(attempt): the cached icon should be the one that was stored")
        }
    }

    func testReCachingAfterAnUpdateServesTheNewIcon() throws {
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try setMtime(past)
        IconCacheManager.shared.cacheIcon(makeIcon(.red, size: 64), for: bundlePath, appearance: .light)

        try setMtime(past.addingTimeInterval(5000))
        IconCacheManager.shared.cacheIcon(makeIcon(.blue, size: 32), for: bundlePath, appearance: .light)

        let cached = IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light)
        XCTAssertEqual(cached?.size.width, 32,
            "After an update and a re-cache, the new icon should be served, not the pre-update one")
    }

    func testStalenessIsTrackedPerAppearance() throws {
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try setMtime(past)
        IconCacheManager.shared.cacheIcon(makeIcon(.red, size: 64), for: bundlePath, appearance: .light)
        IconCacheManager.shared.cacheIcon(makeIcon(.red, size: 64), for: bundlePath, appearance: .dark)

        try setMtime(past.addingTimeInterval(5000))

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .light),
            "The light variant should be invalidated by the bundle change")
        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: bundlePath, appearance: .dark),
            "The dark variant should be invalidated by the same bundle change")
    }

    // MARK: - The record the disk-scan path reads

    func testCachedMtimeReflectsTheLatestDiskRead() throws {
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try setMtime(past)
        _ = IconCacheManager.shared.currentBundleModificationTime(for: bundlePath)

        let later = past.addingTimeInterval(5000)
        try setMtime(later)
        _ = IconCacheManager.shared.currentBundleModificationTime(for: bundlePath)

        let recorded = IconCacheManager.shared.cachedMtime(for: bundlePath)
        XCTAssertEqual(recorded.map { Int($0.timeIntervalSince1970) }, Int(later.timeIntervalSince1970),
            "The recorded mtime should track the most recent disk read, not the first one")
    }
}
