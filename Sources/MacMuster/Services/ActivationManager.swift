import AppKit
import Carbon.HIToolbox
import Observation

/// Screen corner used for hot-corner activation.
enum HotCorner: String, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }

    /// Whether `point` (global screen coordinates, origin bottom-left) is within `zone` points of
    /// this corner of `frame`. Pure so the geometry is testable without a display.
    nonisolated func contains(_ point: CGPoint, in frame: CGRect, zone: CGFloat) -> Bool {
        let corner: CGPoint = switch self {
        case .topLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.maxX, y: frame.minY)
        }
        return abs(point.x - corner.x) <= zone && abs(point.y - corner.y) <= zone
    }

    /// Two points one unit beyond `frame`'s edges at this corner (past the side edge, and past the
    /// top/bottom edge). If another display contains either, the corner is shared, not a dead end.
    nonisolated func outwardProbes(of frame: CGRect) -> [CGPoint] {
        let dx: CGFloat = (self == .topLeft || self == .bottomLeft) ? -1 : 1
        let dy: CGFloat = (self == .topLeft || self == .topRight) ? 1 : -1
        let x = dx < 0 ? frame.minX : frame.maxX
        let y = dy > 0 ? frame.maxY : frame.minY
        return [CGPoint(x: x + dx, y: y - dy), CGPoint(x: x - dx, y: y + dy)]
    }
}

/// Registers the global keyboard shortcut and the hot corner that open the launcher.
///
/// Both are configured by value (`apply`) rather than by reading `AppModel`, so this singleton
/// never instantiates app state and `SettingsAppearance` stays the single source of truth.
/// Neither mechanism needs the Accessibility permission: Carbon hot keys are delivered to the
/// registering process, and global `mouseMoved` monitors (unlike key monitors) are not gated.
@MainActor
@Observable
final class ActivationManager {
    static let shared = ActivationManager()
    private init() {}

    /// True when the OS refused the shortcut (usually because another app already owns it).
    private(set) var hotkeyRegistrationFailed = false

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var activeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private(set) var cornerArmed = true
    @ObservationIgnored private var corner: HotCorner = .topRight

    /// Modifier bits a shortcut may use; anything else (caps lock, fn, device flags) is dropped.
    nonisolated static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    func apply(hotkeyEnabled: Bool, keyCode: Int, modifiers: Int, cornerEnabled: Bool, corner: HotCorner) {
        unregisterHotkey()
        if hotkeyEnabled {
            registerHotkey(keyCode: keyCode, modifiers: modifiers)
        } else {
            hotkeyRegistrationFailed = false
        }
        self.corner = corner
        if cornerEnabled {
            startCornerMonitor()
        } else {
            stopCornerMonitor()
        }
    }

    // MARK: - Hot Key

    /// Converts `NSEvent` modifier bits to the Carbon mask `RegisterEventHotKey` expects.
    nonisolated static func carbonModifiers(from rawFlags: Int) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: rawFlags)).intersection(allowedModifiers)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// A shortcut must include Command, Option or Control; Shift alone would hijack typing.
    nonisolated static func isValidShortcut(modifiers rawFlags: Int) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: rawFlags))
        return !flags.intersection([.command, .option, .control]).isEmpty
    }

    private func registerHotkey(keyCode: Int, modifiers: Int) {
        guard keyCode >= 0, Self.isValidShortcut(modifiers: modifiers) else {
            hotkeyRegistrationFailed = true
            return
        }
        if handlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, _ in
                    Task { @MainActor in ActivationManager.shared.activate() }
                    return noErr
                },
                1, &spec, nil, &handlerRef
            )
            guard status == noErr else {
                hotkeyRegistrationFailed = true
                return
            }
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D43_4D53), id: 1) // 'MCMS'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(from: modifiers),
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            hotKeyRef = ref
            hotkeyRegistrationFailed = false
        } else {
            hotkeyRegistrationFailed = true
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// The shortcut toggles; a hot corner only opens (the pointer is parked in the corner, so
    /// "toggle" would immediately re-hide it on the next dwell).
    private func activate() {
        StatusBarManager.shared.toggleWindow()
    }

    // MARK: - Hot Corner

    private func startCornerMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        // The global monitor is blind while this app is active (see `hotCornerPollInterval`), so
        // follow activation and fall back to sampling the pointer in that state.
        let center = NotificationCenter.default
        activeObservers = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
            .map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePolling() }
                }
            }
        updatePolling()
    }

    /// Whether the pointer should be sampled by timer: only when the corner is on and this app is
    /// active, the one state in which the global monitor receives nothing.
    nonisolated static func shouldPoll(cornerMonitoring: Bool, appIsActive: Bool) -> Bool {
        cornerMonitoring && appIsActive
    }

    var isPollingPointer: Bool { pollTimer != nil }

    func updatePolling() {
        updatePolling(appIsActive: NSApplication.shared.isActive)
    }

    func updatePolling(appIsActive: Bool) {
        if Self.shouldPoll(cornerMonitoring: mouseMonitor != nil, appIsActive: appIsActive) {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: ActivationMetrics.hotCornerPollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func stopCornerMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        activeObservers.forEach(NotificationCenter.default.removeObserver)
        activeObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
        dwellTask?.cancel()
        dwellTask = nil
        cornerArmed = true
    }

    /// Re-arms the corner after the launcher hides, if the pointer is no longer in it.
    ///
    /// The corner disarms when it fires and re-arms only when a global `mouseMoved` event shows the
    /// pointer outside it. Global monitors never see events delivered to this app, so while the
    /// launcher was up the pointer could leave the corner unnoticed and the corner stayed disarmed:
    /// after hiding the launcher (clicking empty space), moving back to the corner did nothing until
    /// the pointer had crossed another app's window. When the pointer is still parked in the corner
    /// (e.g. Esc pressed there) it stays disarmed so the next nudge doesn't reopen the launcher.
    func overlayDidHide() {
        overlayDidHide(pointerInCorner: cornerEnabledMonitorActive ? pointerIsInCorner() : false)
    }

    func overlayDidHide(pointerInCorner: Bool) {
        dwellTask?.cancel()
        dwellTask = nil
        cornerArmed = !pointerInCorner
        // This app is usually still active once the launcher hides; make sure sampling is running.
        updatePolling()
    }

    private var cornerEnabledMonitorActive: Bool { mouseMonitor != nil }

    private func pointerMoved() {
        guard pointerIsInCorner() else {
            dwellTask?.cancel()
            dwellTask = nil
            cornerArmed = true
            return
        }
        guard cornerArmed, dwellTask == nil else { return }
        dwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(ActivationMetrics.hotCornerDwell))
            guard !Task.isCancelled, let self else { return }
            self.dwellTask = nil
            // Re-check: the pointer may have left, or a button gone down (a drag to the corner).
            guard self.pointerIsInCorner(), NSEvent.pressedMouseButtons == 0 else { return }
            self.cornerArmed = false
            if !OverlayWindowManager.shared.isWindowVisible {
                StatusBarManager.shared.showWindow()
            }
        }
    }

    private func pointerIsInCorner() -> Bool {
        let point = NSEvent.mouseLocation
        let zone = ActivationMetrics.hotCornerZonePoints
        let screens = NSScreen.screens
        return screens.contains { screen in
            guard corner.contains(point, in: screen.frame, zone: zone) else { return false }
            // A corner that touches another display isn't a real corner: the pointer crosses it.
            let neighbours = corner.outwardProbes(of: screen.frame)
            return !screens.contains { other in
                other != screen && neighbours.contains { other.frame.contains($0) }
            }
        }
    }
}

// MARK: - Shortcut Display

enum HotkeyFormatter {
    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4",
        120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    /// e.g. "⌃⌥Space". Modifier order follows the macOS convention (⌃⌥⇧⌘).
    static func displayString(keyCode: Int, modifiers rawFlags: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: rawFlags))
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (keyNames[keyCode] ?? "Key \(keyCode)")
    }
}
