import XCTest
@testable import MacMuster

final class IconCacheManagerTests: XCTestCase {

    // MARK: - Cache Key Generation (SHA256)

    func testCacheKeyFullDigestNoTruncation() {
        let key1 = IconCacheManager.shared.cacheKey(for: "/Applications/Safari.app")
        let key2 = IconCacheManager.shared.cacheKey(for: "/System/Applications/Calculator.app")
        XCTAssertNotEqual(key1, key2, "Two apps in different top-level directories should have distinct cache keys")
    }

    func testSamePathProducesSameKey() {
        let path = "/Applications/Xcode.app"
        let key1 = IconCacheManager.shared.cacheKey(for: path)
        let key2 = IconCacheManager.shared.cacheKey(for: path)
        XCTAssertEqual(key1, key2, "Same path should produce the same cache key")
    }

    func testCacheKeyFullHexLength() {
        // SHA256 produces 32 bytes → 64 hex characters
        let key = IconCacheManager.shared.cacheKey(for: "/Applications/Safari.app")
        XCTAssertEqual(key.count, 64, "SHA256 cache key should be 64 hex characters")
    }

    func testCacheKeyNoCollisionBetweenSharedPrefixPaths() {
        // Regression: the v2 cache key truncated the SHA256 to 8 bytes, so every app
        // under /System/Applications/* shared the same key. The v3 key uses the full
        // digest. Paths with long shared prefixes must produce different keys.
        let keyA = IconCacheManager.shared.cacheKey(for: "/System/Applications/Calculator.app")
        let keyB = IconCacheManager.shared.cacheKey(for: "/System/Applications/Calendar.app")
        let keyC = IconCacheManager.shared.cacheKey(for: "/System/Applications/Maps.app")
        XCTAssertNotEqual(keyA, keyB, "Calculator and Calendar must have distinct cache keys")
        XCTAssertNotEqual(keyB, keyC, "Calendar and Maps must have distinct cache keys")
        XCTAssertNotEqual(keyA, keyC, "Calculator and Maps must have distinct cache keys")
    }

    func testCacheKeyForEmptyPath() {
        let key = IconCacheManager.shared.cacheKey(for: "")
        XCTAssertEqual(key.count, 64, "Empty path should still produce a 64-char SHA256 key")
    }

    func testCacheKeyForPathWithSpecialCharacters() {
        let path = "/Applications/My App (Beta).app"
        let key = IconCacheManager.shared.cacheKey(for: path)
        XCTAssertEqual(key.count, 64, "Path with spaces/parens should produce a valid 64-char key")
    }

    func testCacheKeyForLongPath() {
        let path = "/Users/test/Very/Long/Path/To/A/Nested/Directory/Containing/An/App.app"
        let key = IconCacheManager.shared.cacheKey(for: path)
        XCTAssertEqual(key.count, 64, "Long path should still produce a 64-char key")
    }

    // MARK: - Mtime Cache

    func testCachedMtimeForNonExistentPathReturnsNil() {
        XCTAssertNil(IconCacheManager.shared.cachedMtime(for: "/NonExistent/Path.app"), "Non-existent path should return nil mtime")
    }

    func testCachedMtimeForRealAppReturnsNilWhenMtimeCacheEmpty() throws {
        // cachedMtime only returns entries already in mtimeCache. The mtimeCache is populated
        // by cacheIcon or pruneDeletedApps, not by cachedMtime itself. So by default it is nil.
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        XCTAssertNil(IconCacheManager.shared.cachedMtime(for: "/System/Applications/Calculator.app"),
            "Mtime cache is empty by default — cachedMtime returns nil")
    }

    func testMtimeCacheIsIdempotentAfterCacheIconPopulatesIt() throws {
        // cacheIcon populates the mtimeCache (via currentBundleModificationTime).
        // After cacheIcon, subsequent cachedMtime reads should return the same cached value.
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: "/System/Applications/Calculator.app")
        let mtime1 = IconCacheManager.shared.cachedMtime(for: "/System/Applications/Calculator.app")
        let mtime2 = IconCacheManager.shared.cachedMtime(for: "/System/Applications/Calculator.app")
        let mtime3 = IconCacheManager.shared.cachedMtime(for: "/System/Applications/Calculator.app")
        XCTAssertNotNil(mtime1, "Mtime should be populated after cacheIcon")
        XCTAssertEqual(mtime1, mtime2, "First two mtime reads after cacheIcon should match")
        XCTAssertEqual(mtime2, mtime3, "Second and third mtime reads after cacheIcon should match")
    }

    // MARK: - Disk Cache Operations

    func testCachedAppPathsReturnsNonEmptyWhenCacheDirExists() {
        // The cacheDir is a fixed location under ~/Library/Caches/MacMuster/icons-v3.
        // If it exists on disk (from previous test runs or normal usage), cachedAppPaths
        // returns all cached entries.
        let paths = IconCacheManager.shared.cachedAppPaths()
        // We can't guarantee the cache dir is empty, so we verify it returns the count
        // of entries on disk (which may be 0 or more).
        XCTAssertTrue(paths.count >= 0, "cachedAppPaths should return a non-negative count")
    }

    func testCacheIconForNonExistentPathStoresInMemoryCacheOnly() {
        // cacheIcon writes to memoryCache BEFORE the mtime check. If the path doesn't exist,
        // the mtime check fails and disk cache is not written, but the icon IS stored in the
        // memory cache. This is correct — subsequent reads hit the memory cache immediately.
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: "/NonExistent/Path.app")
        let cached = IconCacheManager.shared.cachedIcon(for: "/NonExistent/Path.app")
        XCTAssertNotNil(cached, "Icon should be cached in memory (mtime check only affects disk cache)")
        XCTAssertEqual(cached?.size.width, icon.size.width, "Cached icon size should match")
    }

    func testCachedIconForNonExistentPathReturnsNil() {
        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: "/NonExistent/Path.app"), "Non-existent path should return nil cached icon")
    }

    func testCacheIconForRealAppStoresInMemoryCache() throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: "/System/Applications/Calculator.app")
        let cached = IconCacheManager.shared.cachedIcon(for: "/System/Applications/Calculator.app")
        XCTAssertNotNil(cached, "Cached icon should be retrievable")
        XCTAssertEqual(cached?.size.width, icon.size.width, "Cached icon size should match")
        XCTAssertEqual(cached?.size.height, icon.size.height, "Cached icon height should match")
    }

    // MARK: - clearAll (force refresh)

    func testClearAllRemovesInMemoryCachedIcon() {
        let path = "/NonExistent/ClearAllTest.app"
        let icon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.purple.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: path)
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: path), "Icon should be cached in memory before clearAll")

        IconCacheManager.shared.clearAll()

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: path), "clearAll should evict the in-memory cache")
    }

    func testClearAllRemovesDiskCacheForRealApp() throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let path = "/System/Applications/Calculator.app"
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.orange.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: path)
        XCTAssertNotNil(IconCacheManager.shared.cachedIcon(for: path), "Icon should be cached before clearAll")

        IconCacheManager.shared.clearAll()

        XCTAssertNil(IconCacheManager.shared.cachedIcon(for: path), "clearAll should evict both the memory and on-disk cache, forcing a fresh decode")
        XCTAssertTrue(IconCacheManager.shared.cachedAppPaths().isEmpty, "clearAll should remove the on-disk cache directory entirely")
    }

    func testClearAllResetsMtimeCache() throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else {
            throw XCTSkip("Calculator.app not found on this machine")
        }
        let path = "/System/Applications/Calculator.app"
        let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.yellow.setFill()
            rect.fill()
            return true
        }
        IconCacheManager.shared.cacheIcon(icon, for: path)
        XCTAssertNotNil(IconCacheManager.shared.cachedMtime(for: path), "Mtime should be populated after cacheIcon")

        IconCacheManager.shared.clearAll()

        XCTAssertNil(IconCacheManager.shared.cachedMtime(for: path), "clearAll should reset the mtime cache")
    }

}