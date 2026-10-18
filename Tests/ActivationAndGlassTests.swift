import XCTest
@testable import MacMuster

@MainActor
final class ActivationAndGlassTests: XCTestCase {

    nonisolated private static let keys = [
        "glassStyle", "simpleGlass", "scrollEdgeEffect", "globalHotkeyEnabled", "hotkeyKeyCode",
        "hotkeyModifiers", "hotCornerEnabled", "hotCorner"
    ]

    override func setUp() async throws { clearKeys() }
    override func tearDown() async throws {
        clearKeys()
        ActivationManager.shared.apply(
            hotkeyEnabled: false, keyCode: 0, modifiers: 0, cornerEnabled: false, corner: .topRight
        )
    }

    nonisolated func clearKeys() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: - Hot corner re-arm after the launcher hides

    /// Regression: the corner disarms when it fires and re-armed only on a global `mouseMoved` that
    /// showed the pointer outside it. Global monitors never see this app's own events, so the pointer
    /// leaving the corner while the launcher was up went unnoticed, and after the launcher hid the
    /// corner stayed dead until the pointer crossed another app.
    func testOverlayHideRearmsCornerWhenPointerLeftIt() {
        ActivationManager.shared.overlayDidHide(pointerInCorner: true)   // corner fired: disarmed
        XCTAssertFalse(ActivationManager.shared.cornerArmed)

        ActivationManager.shared.overlayDidHide(pointerInCorner: false)  // pointer moved away, launcher hid

        XCTAssertTrue(ActivationManager.shared.cornerArmed,
            "Hiding the launcher with the pointer outside the corner must re-arm it")
    }

    func testOverlayHideKeepsCornerDisarmedWhilePointerIsStillInIt() {
        ActivationManager.shared.overlayDidHide(pointerInCorner: true)

        XCTAssertFalse(ActivationManager.shared.cornerArmed,
            "Hiding with the pointer parked in the corner must not let the next nudge reopen the launcher")
    }

    // MARK: - Pointer sampling while MacMuster is active

    /// Regression: after the launcher hides MacMuster is still the active app, and the global
    /// `mouseMoved` monitor receives nothing in that state, so the corner stayed dead until another
    /// app was activated. Sampling must run exactly when the corner is on and this app is active.
    func testShouldPollOnlyWhenCornerOnAndAppActive() {
        XCTAssertTrue(ActivationManager.shouldPoll(cornerMonitoring: true, appIsActive: true))
        XCTAssertFalse(ActivationManager.shouldPoll(cornerMonitoring: true, appIsActive: false),
            "Another app is active: the global monitor works, no polling needed")
        XCTAssertFalse(ActivationManager.shouldPoll(cornerMonitoring: false, appIsActive: true),
            "Corner off: never poll")
    }

    func testPollingStartsWhenAppActiveAndStopsWhenItResignsOrCornerTurnsOff() {
        let manager = ActivationManager.shared
        manager.apply(hotkeyEnabled: false, keyCode: 0, modifiers: 0, cornerEnabled: true, corner: .topRight)

        manager.updatePolling(appIsActive: true)
        XCTAssertTrue(manager.isPollingPointer)

        manager.updatePolling(appIsActive: false)
        XCTAssertFalse(manager.isPollingPointer)

        manager.updatePolling(appIsActive: true)
        manager.apply(hotkeyEnabled: false, keyCode: 0, modifiers: 0, cornerEnabled: false, corner: .topRight)
        XCTAssertFalse(manager.isPollingPointer, "Turning the corner off must stop the timer")
    }

    func testHidingTheLauncherStartsPollingWhileTheAppIsStillActive() {
        let manager = ActivationManager.shared
        manager.apply(hotkeyEnabled: false, keyCode: 0, modifiers: 0, cornerEnabled: true, corner: .topRight)
        manager.updatePolling(appIsActive: false)
        XCTAssertFalse(manager.isPollingPointer)

        // `overlayDidHide` re-evaluates using the real activation state; under `swift test` the app
        // is not active, so only the decision function is asserted for the active case above.
        manager.overlayDidHide(pointerInCorner: false)
        XCTAssertEqual(manager.isPollingPointer, NSApplication.shared.isActive)
    }

    // MARK: - Hot corner geometry

    func testHotCornerContainsPointNearEachCorner() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let zone = ActivationMetrics.hotCornerZonePoints
        XCTAssertTrue(HotCorner.topLeft.contains(CGPoint(x: 0, y: 800), in: frame, zone: zone))
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 1000, y: 799), in: frame, zone: zone))
        XCTAssertTrue(HotCorner.bottomLeft.contains(CGPoint(x: 1, y: 0), in: frame, zone: zone))
        XCTAssertTrue(HotCorner.bottomRight.contains(CGPoint(x: 999, y: 1), in: frame, zone: zone))
    }

    func testHotCornerRejectsOtherCornersAndEdges() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let zone = ActivationMetrics.hotCornerZonePoints
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 0, y: 800), in: frame, zone: zone))
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 500, y: 800), in: frame, zone: zone))
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 1000, y: 700), in: frame, zone: zone))
    }

    func testHotCornerHonoursNonZeroScreenOrigin() {
        let frame = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertTrue(HotCorner.bottomLeft.contains(CGPoint(x: 1440, y: -200), in: frame, zone: 2))
        XCTAssertFalse(HotCorner.bottomLeft.contains(CGPoint(x: 0, y: 0), in: frame, zone: 2))
    }

    func testOutwardProbesLieOutsideFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for corner in HotCorner.allCases {
            for probe in corner.outwardProbes(of: frame) {
                XCTAssertFalse(frame.contains(probe), "\(corner) probe \(probe) should be outside the screen")
            }
        }
    }

    // MARK: - Shortcut helpers

    func testShortcutRequiresCommandOptionOrControl() {
        XCTAssertFalse(ActivationManager.isValidShortcut(modifiers: 0))
        XCTAssertFalse(ActivationManager.isValidShortcut(modifiers: Int(NSEvent.ModifierFlags.shift.rawValue)))
        XCTAssertTrue(ActivationManager.isValidShortcut(modifiers: Int(NSEvent.ModifierFlags.command.rawValue)))
        XCTAssertTrue(ActivationManager.isValidShortcut(modifiers: ActivationMetrics.defaultHotkeyModifiers))
    }

    func testCarbonModifierConversion() {
        let flags = NSEvent.ModifierFlags([.control, .option]).rawValue
        let carbon = ActivationManager.carbonModifiers(from: Int(flags))
        XCTAssertEqual(carbon, UInt32(4096 | 2048))
        XCTAssertEqual(ActivationManager.carbonModifiers(from: Int(NSEvent.ModifierFlags.capsLock.rawValue)), 0)
    }

    func testHotkeyDisplayString() {
        XCTAssertEqual(
            HotkeyFormatter.displayString(keyCode: ActivationMetrics.defaultHotkeyKeyCode,
                                          modifiers: ActivationMetrics.defaultHotkeyModifiers),
            "⌃⌥Space"
        )
        let cmdShift = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        XCTAssertEqual(HotkeyFormatter.displayString(keyCode: 40, modifiers: cmdShift), "⇧⌘K")
    }

    // MARK: - Persistence

    func testActivationAndGlassDefaults() {
        let settings = SettingsAppearance()
        XCTAssertFalse(settings.globalHotkeyEnabled)
        XCTAssertFalse(settings.hotCornerEnabled)
        XCTAssertEqual(settings.glassStyle, .classic)
        XCTAssertFalse(settings.simpleGlass)
        XCTAssertEqual(settings.hotkeyKeyCode, ActivationMetrics.defaultHotkeyKeyCode)
    }

    func testActivationAndGlassSettingsPersist() {
        let settings = SettingsAppearance()
        settings.glassStyle = .liquid
        settings.simpleGlass = true
        settings.hotkeyKeyCode = 40
        settings.hotkeyModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
        settings.hotCorner = .bottomLeft

        let reloaded = SettingsAppearance()
        XCTAssertEqual(reloaded.glassStyle, .liquid)
        XCTAssertTrue(reloaded.simpleGlass)
        XCTAssertEqual(reloaded.hotkeyKeyCode, 40)
        XCTAssertEqual(reloaded.hotCorner, .bottomLeft)
    }

    func testUnknownPersistedGlassStyleFallsBackToClassic() {
        UserDefaults.standard.set("Holographic", forKey: "glassStyle")
        XCTAssertEqual(SettingsAppearance().glassStyle, .classic)
    }

    func testEffectiveGlassStyleFollowsAvailability() {
        let settings = SettingsAppearance()
        settings.glassStyle = .liquid
        XCTAssertEqual(
            settings.effectiveGlassStyle,
            SettingsAppearance.GlassStyle.liquidGlassAvailable ? .liquid : .classic
        )
    }

    // MARK: - Backup

    private func makeArchive(
        modifiers: Int?, keyCode: Int?, style: String?, corner: String?
    ) -> BackupManager.BackupArchive {
        BackupManager.BackupArchive(
            appFolders: [], customOrder: [:], hiddenAppPaths: [],
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue, showFoldersFirst: false, refreshInterval: 900,
            currentFolderId: nil, customDirectories: [], glowEnabled: true, glowColor: "#ffffff",
            glowIntensity: 0.3, glowWidth: 40, fontFamily: "SF Pro", fontSize: 14,
            fontWeight: "normal", pressFeedbackEnabled: true, recentAppsEnabled: true,
            overlayOpacity: GlowMetrics.overlayOpacityDefault, showInDock: true,
            glassStyle: style, simpleGlass: true, globalHotkeyEnabled: true,
            hotkeyKeyCode: keyCode, hotkeyModifiers: modifiers,
            hotCornerEnabled: true, hotCorner: corner,
            icons: BackupManager.IconPack(entries: [:])
        )
    }

    func testBackupArchiveRoundTripsNewSettings() throws {
        let archive = makeArchive(modifiers: ActivationMetrics.defaultHotkeyModifiers, keyCode: 49,
                                  style: "Liquid Glass", corner: "Bottom Right")
        let decoded = try JSONDecoder().decode(
            BackupManager.BackupArchive.self, from: JSONEncoder().encode(archive)
        )
        XCTAssertEqual(decoded.glassStyle, "Liquid Glass")
        XCTAssertEqual(decoded.hotCorner, "Bottom Right")
        XCTAssertEqual(decoded.hotkeyKeyCode, 49)
        XCTAssertEqual(decoded.simpleGlass, true)
    }

    func testOlderArchiveWithoutNewKeysStillDecodes() throws {
        let archive = makeArchive(modifiers: nil, keyCode: nil, style: nil, corner: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any]
        )
        for key in ["glassStyle", "simpleGlass", "globalHotkeyEnabled", "hotkeyKeyCode",
                    "hotkeyModifiers", "hotCornerEnabled", "hotCorner"] {
            object.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(BackupManager.BackupArchive.self, from: data)
        XCTAssertNil(decoded.glassStyle)
        XCTAssertNil(decoded.hotkeyKeyCode)
    }

    func testRestoreAppliesValidSettings() async {
        let archive = makeArchive(modifiers: ActivationMetrics.defaultHotkeyModifiers, keyCode: 40,
                                  style: "Liquid Glass", corner: "Top Left")
        await BackupManager.shared.apply(preview: .init(archive: archive, validAppPaths: [], missingAppPaths: []))
        XCTAssertEqual(PreferencesStore.shared.loadGlassStyle(), "Liquid Glass")
        XCTAssertEqual(PreferencesStore.shared.loadHotkeyKeyCode(), 40)
        XCTAssertEqual(PreferencesStore.shared.loadHotCorner(), "Top Left")
        XCTAssertFalse(PreferencesStore.shared.loadGlobalHotkeyEnabled(),
                       "SEC-8: a restore never switches a system-wide hotkey on")
    }

    func testRestoreDoesNotRepointAHotkeyThatIsAlreadyLive() async {
        PreferencesStore.shared.saveGlobalHotkeyEnabled(true)
        PreferencesStore.shared.saveHotkeyKeyCode(11)
        let archive = makeArchive(modifiers: ActivationMetrics.defaultHotkeyModifiers, keyCode: 49,
                                  style: nil, corner: nil)
        await BackupManager.shared.apply(preview: .init(archive: archive, validAppPaths: [], missingAppPaths: []))
        XCTAssertEqual(PreferencesStore.shared.loadHotkeyKeyCode(), 11, "live chord must stay as the user set it")
        XCTAssertTrue(PreferencesStore.shared.loadGlobalHotkeyEnabled(), "an archive saying 'enabled' leaves it enabled")
    }

    func testRestoreMayTurnTheHotkeyOff() async {
        PreferencesStore.shared.saveGlobalHotkeyEnabled(true)
        let base = makeArchive(modifiers: ActivationMetrics.defaultHotkeyModifiers, keyCode: 40, style: nil, corner: nil)
        let archive = BackupManager.BackupArchive(
            appFolders: [], customOrder: [:], hiddenAppPaths: [], sortOption: base.sortOption, iconSize: base.iconSize,
            showFoldersFirst: false, refreshInterval: 900, currentFolderId: nil, customDirectories: [],
            glowEnabled: true, glowColor: "#ffffff", glowIntensity: 0.3, glowWidth: 40, fontFamily: "SF Pro",
            fontSize: 14, fontWeight: "normal", pressFeedbackEnabled: true, recentAppsEnabled: true,
            overlayOpacity: GlowMetrics.overlayOpacityDefault, showInDock: true,
            globalHotkeyEnabled: false, hotkeyKeyCode: 40, hotkeyModifiers: ActivationMetrics.defaultHotkeyModifiers,
            icons: BackupManager.IconPack(entries: [:]))
        await BackupManager.shared.apply(preview: .init(archive: archive, validAppPaths: [], missingAppPaths: []))
        XCTAssertFalse(PreferencesStore.shared.loadGlobalHotkeyEnabled())
    }

    func testRestoreRejectsInvalidShortcutAndUnknownValues() async {
        // Shift-only modifiers, out-of-range key code, and unknown enum strings from an
        // untrusted file must not reach preferences.
        let archive = makeArchive(modifiers: Int(NSEvent.ModifierFlags.shift.rawValue), keyCode: 9999,
                                  style: "Holographic", corner: "Center")
        await BackupManager.shared.apply(preview: .init(archive: archive, validAppPaths: [], missingAppPaths: []))
        XCTAssertNil(PreferencesStore.shared.loadHotkeyKeyCode())
        XCTAssertFalse(PreferencesStore.shared.loadGlobalHotkeyEnabled())
        XCTAssertNil(PreferencesStore.shared.loadGlassStyle())
        XCTAssertNil(PreferencesStore.shared.loadHotCorner())
    }
}
