import XCTest
@testable import MacMuster

@MainActor
final class ScrollEdgeEffectTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "scrollEdgeEffect")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "scrollEdgeEffect")
        super.tearDown()
    }

    // MARK: - Curve

    func testFullyVisibleRowIsIdentity() {
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: 0), .identity)
    }

    func testEdgeRowReachesConfiguredMinimums() {
        for phase in [-1.0, 1.0] {
            let v = ScrollEdgeEffect.values(phaseValue: phase)
            XCTAssertEqual(v.opacity, ScrollEdgeMetrics.minOpacity, accuracy: 1e-9)
            XCTAssertEqual(v.scale, ScrollEdgeMetrics.minScale, accuracy: 1e-9)
            XCTAssertEqual(v.blurRadius, ScrollEdgeMetrics.maxBlurRadius, accuracy: 1e-9)
        }
    }

    func testTopAndBottomAreSymmetric() {
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: -0.4), ScrollEdgeEffect.values(phaseValue: 0.4))
    }

    func testTaperIsMonotonic() {
        var previous = ScrollEdgeEffect.values(phaseValue: 0)
        for step in 1...10 {
            let v = ScrollEdgeEffect.values(phaseValue: Double(step) / 10)
            XCTAssertLessThanOrEqual(v.opacity, previous.opacity)
            XCTAssertLessThanOrEqual(v.scale, previous.scale)
            XCTAssertGreaterThanOrEqual(v.blurRadius, previous.blurRadius)
            previous = v
        }
    }

    func testOutOfRangeAndNonFinitePhasesAreSafe() {
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: 5), ScrollEdgeEffect.values(phaseValue: 1))
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: -5), ScrollEdgeEffect.values(phaseValue: -1))
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: .nan), .identity)
        XCTAssertEqual(ScrollEdgeEffect.values(phaseValue: .infinity), .identity)
    }

    // MARK: - Gating

    func testEffectYieldsToLowGPUGlassAndReduceMotion() {
        XCTAssertTrue(ScrollEdgeEffect.isActive(enabled: true, simpleGlass: false, reduceMotion: false))
        XCTAssertFalse(ScrollEdgeEffect.isActive(enabled: false, simpleGlass: false, reduceMotion: false))
        XCTAssertFalse(ScrollEdgeEffect.isActive(enabled: true, simpleGlass: true, reduceMotion: false))
        XCTAssertFalse(ScrollEdgeEffect.isActive(enabled: true, simpleGlass: false, reduceMotion: true))
    }

    // MARK: - Setting

    func testSettingDefaultsOnAndPersists() {
        let settings = SettingsAppearance()
        XCTAssertTrue(settings.scrollEdgeEffect)
        settings.scrollEdgeEffect = false
        XCTAssertFalse(SettingsAppearance().scrollEdgeEffect)
    }

    func testSimpleGlassDisablesEffectiveEffect() {
        let settings = SettingsAppearance()
        settings.scrollEdgeEffect = true
        settings.simpleGlass = true
        XCTAssertFalse(settings.isScrollEdgeEffectActive)
        settings.simpleGlass = false
    }

    func testStaleLowGPUGlassDoesNotDisableEffectInSheetMode() {
        let settings = SettingsAppearance()
        settings.scrollEdgeEffect = true
        settings.simpleGlass = true
        settings.presentationMode = .sheet
        defer { settings.simpleGlass = false; settings.presentationMode = .glass }
        XCTAssertEqual(settings.isScrollEdgeEffectActive, !settings.shouldReduceMotion)
    }

    func testBackupArchiveRoundTripsSetting() throws {
        let archive = BackupManager.BackupArchive(
            appFolders: [], customOrder: [:], hiddenAppPaths: [],
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue, showFoldersFirst: false, refreshInterval: 900,
            currentFolderId: nil, customDirectories: [], glowEnabled: true, glowColor: "#ffffff",
            glowIntensity: 0.3, glowWidth: 40, fontFamily: "SF Pro", fontSize: 14,
            fontWeight: "normal", pressFeedbackEnabled: true, recentAppsEnabled: true,
            overlayOpacity: GlowMetrics.overlayOpacityDefault, showInDock: true,
            scrollEdgeEffect: false,
            icons: BackupManager.IconPack(entries: [:])
        )
        let decoded = try JSONDecoder().decode(BackupManager.BackupArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.scrollEdgeEffect, false)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        object.removeValue(forKey: "scrollEdgeEffect")
        let older = try JSONDecoder().decode(BackupManager.BackupArchive.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(older.scrollEdgeEffect)
    }
}
