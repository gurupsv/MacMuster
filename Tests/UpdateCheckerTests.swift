import XCTest
@testable import MacMuster

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private let keys = ["updateCheckEnabled", "lastUpdateCheck", "availableUpdateVersion", "availableUpdateURL", "dismissedUpdateVersion"]
    override func setUp() async throws { for k in keys { UserDefaults.standard.removeObject(forKey: k) } }
    override func tearDown() async throws { for k in keys { UserDefaults.standard.removeObject(forKey: k) } }

    private func payload(tag: String, url: String) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)"}"#.utf8)
    }

    // MARK: - Version comparison

    func testIsNewerComparesNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.0.13", than: "1.0.12"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.0.100", than: "1.0.12"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "v2.0", than: "1.9.9"))
    }

    func testIsNewerFalseWhenEqualOrOlder() {
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.12", than: "1.0.12"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.1", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.11", than: "1.0.12"))
    }

    func testIsNewerFalseForMalformedVersions() {
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.13-beta", than: "1.0.12"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "", than: "1.0.12"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "9.9.9", than: "garbage"))
    }

    // MARK: - Payload parsing

    func testParseAcceptsProjectReleaseURL() {
        let release = UpdateChecker.parseLatestRelease(
            from: payload(tag: "v1.0.13", url: "https://github.com/gurupsv/MacMuster/releases/tag/1.0.13"))
        XCTAssertEqual(release?.version, "1.0.13")
        XCTAssertEqual(release?.pageURL.host, "github.com")
    }

    func testParseRejectsForeignOrInsecureLinks() {
        for url in ["https://evil.example/gurupsv/MacMuster/releases/tag/1.0.13",
                    "http://github.com/gurupsv/MacMuster/releases/tag/1.0.13",
                    "https://github.com/other/repo/releases/tag/1.0.13",
                    "file:///Applications/Calculator.app"] {
            XCTAssertNil(UpdateChecker.parseLatestRelease(from: payload(tag: "1.0.13", url: url)), url)
        }
    }

    func testParseRejectsBadPayloads() {
        XCTAssertNil(UpdateChecker.parseLatestRelease(from: Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(from: Data("{}".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(
            from: payload(tag: "nightly", url: "https://github.com/gurupsv/MacMuster/releases/tag/nightly")))
        XCTAssertNil(UpdateChecker.parseLatestRelease(from: Data(count: UpdateMetrics.maxResponseBytes + 1)))
    }

    // MARK: - Scheduling

    func testCheckDueRules() {
        let now = Date()
        XCTAssertFalse(UpdateChecker.isCheckDue(enabled: false, lastCheck: nil, now: now))
        XCTAssertTrue(UpdateChecker.isCheckDue(enabled: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateChecker.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateChecker.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-90_000), now: now))
        XCTAssertTrue(UpdateChecker.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(3600), now: now))
    }

    // MARK: - Banner state

    func testBannerHiddenWhenOptedOut() {
        XCTAssertNil(UpdateChecker.shared.bannerRelease(enabled: false))
    }

    func testPersistedUpdateRoundTripsAndClears() {
        PreferencesStore.shared.saveAvailableUpdate(version: "9.9.9", url: "https://github.com/gurupsv/MacMuster/releases/tag/9.9.9")
        XCTAssertEqual(PreferencesStore.shared.loadAvailableUpdate()?.version, "9.9.9")
        PreferencesStore.shared.clearAvailableUpdate()
        XCTAssertNil(PreferencesStore.shared.loadAvailableUpdate())
    }

    func testReleaseURLRule() {
        XCTAssertTrue(UpdateChecker.isReleaseURL(URL(string: "https://github.com/gurupsv/MacMuster/releases/tag/1.1.1")!))
        XCTAssertFalse(UpdateChecker.isReleaseURL(URL(string: "https://github.com/other/repo/releases")!))
        XCTAssertFalse(UpdateChecker.isReleaseURL(URL(string: "http://github.com/gurupsv/MacMuster/releases")!))
    }

    // MARK: - Setting

    func testUpdateCheckDefaultsOffAndPersists() {
        XCTAssertFalse(SettingsAppearance().updateCheckEnabled)
        XCTAssertFalse(PreferencesStore.shared.loadUpdateCheckEnabled())
        PreferencesStore.shared.saveUpdateCheckEnabled(true)
        XCTAssertTrue(SettingsAppearance().updateCheckEnabled)
    }
}
