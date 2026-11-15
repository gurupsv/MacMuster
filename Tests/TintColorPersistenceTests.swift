import XCTest
import SwiftUI
@testable import MacMuster

/// Regression: `tintColor`'s `didSet` persisted the *glow* color, so a chosen tint came back as
/// the glow color (white by default) after every relaunch.
@MainActor
final class TintColorPersistenceTests: XCTestCase {

    nonisolated private static let keys = ["tintColor", "glowColor", "tintStrength"]

    override func setUp() async throws { clearKeys() }
    override func tearDown() async throws { clearKeys() }

    nonisolated private func clearKeys() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    func testTintColorSurvivesRelaunchIndependentOfGlowColor() {
        let settings = SettingsAppearance()
        settings.glowColor = Color(red: 1, green: 1, blue: 1)
        settings.tintColor = Color(red: 1, green: 0, blue: 0)

        XCTAssertEqual(PreferencesStore.shared.loadTintColor(), "#ff0000")
        XCTAssertEqual(PreferencesStore.shared.loadGlowColor(), "#ffffff")

        let relaunched = SettingsAppearance()
        XCTAssertEqual(SettingsAppearance.hexString(for: relaunched.tintColor), "#ff0000")
        XCTAssertEqual(SettingsAppearance.hexString(for: relaunched.glowColor), "#ffffff")
    }

    func testGlowColorChangeDoesNotOverwriteTint() {
        let settings = SettingsAppearance()
        settings.tintColor = Color(red: 0, green: 1, blue: 0)
        settings.glowColor = Color(red: 0, green: 0, blue: 1)

        XCTAssertEqual(PreferencesStore.shared.loadTintColor(), "#00ff00")
        XCTAssertEqual(PreferencesStore.shared.loadGlowColor(), "#0000ff")
    }
}
