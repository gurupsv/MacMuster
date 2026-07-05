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

}