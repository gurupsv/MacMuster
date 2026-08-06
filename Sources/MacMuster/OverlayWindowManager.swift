import AppKit
import SwiftUI

enum KeyCodes {
    static let escape: UInt16 = 53
    static let backspaceDelete: UInt16 = 51
    static let returnEnter: [UInt16] = [36, 76]
    static let forwardSlash: UInt16 = 43
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

extension Notification.Name {
    static let launcherDidShow = Notification.Name("launcherDidShow")
    static let focusSearchField = Notification.Name("focusSearchField")
    static let keyboardNavigationDidStart = Notification.Name("keyboardNavigationDidStart")
}

// MARK: - Glow Effect View (SwiftUI overlay for glowing edges)

struct GlowEffectView: View {
    let appModel: AppModel
    
    private let glowMaxOpacity: CGFloat = 1.0
    
    var body: some View {
        if appModel.glowEnabled && appModel.glowIntensity > 0 {
            let color = appModel.glowColor
            let intensity = appModel.glowIntensity
            let glowInset = appModel.glowWidth
            
            Rectangle()
                .fill(.clear)
                .overlay(alignment: .top) { EdgeGlow(edge: .top, color: color, intensity: intensity, inset: glowInset) }
                .overlay(alignment: .bottom) { EdgeGlow(edge: .bottom, color: color, intensity: intensity, inset: glowInset) }
                .overlay(alignment: .leading) { EdgeGlow(edge: .leading, color: color, intensity: intensity, inset: glowInset) }
                .overlay(alignment: .trailing) { EdgeGlow(edge: .trailing, color: color, intensity: intensity, inset: glowInset) }
                .allowsHitTesting(false)
                .drawingGroup(opaque: false)
        }
    }
}

struct EdgeGlow: View {
    let edge: Alignment
    let color: Color
    let intensity: CGFloat
    let inset: CGFloat
    
    private let glowMaxOpacity: CGFloat = 1.0
    
    var body: some View {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return GlowEdgeView(edge: edge, colors: [.clear], inset: inset)
        }
        let maxOpacity = intensity * glowMaxOpacity
        let midOpacity = intensity * glowMaxOpacity * 0.6
        let fadeOpacity = intensity * glowMaxOpacity * 0.15
        let colors: [Color] = [
            Color(nsColor: rgb.withAlphaComponent(maxOpacity)),
            Color(nsColor: rgb.withAlphaComponent(midOpacity)),
            Color(nsColor: rgb.withAlphaComponent(fadeOpacity)),
            .clear,
        ]
        
        return GlowEdgeView(edge: edge, colors: colors, inset: inset)
    }
}

struct GlowEdgeView: View {
    let edge: Alignment
    let colors: [Color]
    let inset: CGFloat
    
    var body: some View {
        switch edge {
        case .top:
            Rectangle()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: nil, height: inset, alignment: .top)
        case .bottom:
            Rectangle()
                .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                .frame(width: nil, height: inset, alignment: .bottom)
        case .leading:
            Rectangle()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: inset, height: nil, alignment: .leading)
        case .trailing:
            Rectangle()
                .fill(LinearGradient(colors: colors, startPoint: .trailing, endPoint: .leading))
                .frame(width: inset, height: nil, alignment: .trailing)
        default:
            Rectangle().fill(.clear)
        }
    }
}

final class OverlayWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performClose(_ sender: Any?) {
        OverlayWindowManager.shared.hide()
    }
}

@MainActor
class OverlayWindowManager {
    static let shared = OverlayWindowManager()

    private var window: OverlayWindow?
    private var backgroundWindows: [NSWindow] = []
    private weak var appModel: AppModel?
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var combinedKeyEventMonitor: Any?
    private var displayChangeObserver: NSObjectProtocol?

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
    
    func setup(appModel: AppModel) {
        self.appModel = appModel
        
        // Store reference for later use in StatusBarManager
        StatusBarManager.shared.setAppModel(appModel)
        
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        
        window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
// Keep the launcher above ordinary app windows and dock — set window level to .floating.
// (Fix: dock visible issue on macOS Tahoe; .fullScreenAuxiliary alone is insufficient.)
        
        // Configure collection behavior for overlay behavior
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window?.level = .floating
        window?.isMovableByWindowBackground = false
        window?.isOpaque = false
        let backgroundColor: NSColor = switch appModel.presentationMode {
            case .glass:
                NSColor.black.withAlphaComponent(appModel.overlayOpacity)
            case .sheet:
                appModel.settings.tintedBackgroundColor()
        }

        window?.backgroundColor = backgroundColor
        window?.hasShadow = false
        
        // Set minimum size for content
        window?.minSize = NSSize(width: WindowMetrics.windowMinWidth, height: WindowMetrics.windowMinHeight)
        
        // Hide title bar buttons (should already be hidden with borderless)
        window?.standardWindowButton(.closeButton)?.isHidden = true
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Set SwiftUI content - use LaunchWrapperView for first-launch zoom-out animation
        let hostingView = NSHostingView(rootView: LaunchWrapperView(appModel: appModel))
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window?.contentView = hostingView
        
        window?.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }
    
    func show() {
        guard let window else { return }
        guard let targetScreen = preferredScreen(for: window) else { return }

        let mode = appModel?.launchMode ?? .window
        applyWindowMode(mode, on: targetScreen)

        installCombinedEventMonitor()
        installDisplayChangeObserver()

        DispatchQueue.main.asyncAfter(deadline: .now() + WindowMetrics.windowAnimationDelay) {
            NotificationCenter.default.post(name: .launcherDidShow, object: window)
        }
    }

    func applyCurrentMode() {
        guard let window, window.isVisible else { return }
        guard let targetScreen = preferredScreen(for: window) else { return }
        let mode = appModel?.launchMode ?? .window
        applyWindowMode(mode, on: targetScreen)
    }

    func applyWindowMode(_ mode: LaunchMode, on targetScreen: NSScreen) {
        guard let window else { return }

        switch mode {
        case .window:
            let visibleFrame = targetScreen.visibleFrame
            let width = visibleFrame.width * 0.6
            let height = visibleFrame.height * 0.6
            let x = visibleFrame.minX + (visibleFrame.width - width) / 2
            let y = visibleFrame.minY + (visibleFrame.height - height) / 2
            let windowFrame = NSRect(x: x, y: y, width: width, height: height)

            exitLauncherPresentationMode()
            hideBackgroundWindows()

            window.styleMask = [.titled, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.title = "MacMuster"
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces]
            window.hasShadow = true
            window.isOpaque = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setFrame(windowFrame, display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.contentView?.frame = CGRect(origin: .zero, size: windowFrame.size)

        case .fullscreen, .maximized:
            // Full Screen covers the entire display (including the menu-bar/notch area) and hides
            // the Dock + menu bar (Launchpad-style). Maximized fills only the visible working area,
            // leaving the menu bar and Dock in place.
            let screenFrame: NSRect = mode == .fullscreen ? targetScreen.frame : targetScreen.visibleFrame

            window.styleMask = [.borderless]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hasShadow = false
            window.isOpaque = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setFrame(screenFrame, display: true)
            showBackgroundWindows(excluding: targetScreen)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if mode == .fullscreen {
                enterLauncherPresentationMode()
            } else {
                exitLauncherPresentationMode()
            }
            window.contentView?.frame = CGRect(origin: .zero, size: screenFrame.size)
        }

        // When the user switches launch mode from Settings, applyWindowMode brings the overlay
        // to front (makeKeyAndOrderFront + NSApp.activate). Re-bring Settings to front so it
        // stays on top of the overlay during the transition.
        if SettingsWindowManager.shared.isVisible {
            SettingsWindowManager.shared.show()
        }
    }
    
    func hide() {
        window?.orderOut(nil)
        hideBackgroundWindows()
        exitLauncherPresentationMode()
        appModel?.clearSearchState()
        removeCombinedEventMonitor()
        removeDisplayChangeObserver()
    }
    
    private func preferredScreen(for window: NSWindow) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let allScreens = NSScreen.screens

        for screen in allScreens {
            let r = CGRect(origin: screen.frame.origin, size: screen.frame.size)
            if r.contains(mouseLocation) { return screen }
        }

        if let windowScreen = window.screen, allScreens.contains(windowScreen) {
            return windowScreen
        }

        return NSScreen.main ?? allScreens.first
    }
    
    private func showBackgroundWindows(excluding targetScreen: NSScreen) {
        hideBackgroundWindows()
        guard let appModel else { return }

        backgroundWindows = NSScreen.screens
            .filter { $0.frame != targetScreen.frame }
            .map { screen in
                let backgroundWindow = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                backgroundWindow.level = .floating
                backgroundWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                backgroundWindow.isOpaque = false
                let backgroundColor = NSColor.black.withAlphaComponent(appModel.overlayOpacity)
                backgroundWindow.backgroundColor = backgroundColor
                backgroundWindow.hasShadow = false
                backgroundWindow.contentView = NSHostingView(rootView: SecondaryOverlayBackground(appModel: appModel))
                backgroundWindow.orderFrontRegardless()
                return backgroundWindow
            }
    }
    
    private func hideBackgroundWindows() {
        backgroundWindows.forEach { $0.orderOut(nil) }
        backgroundWindows.removeAll()
    }
    
    private func enterLauncherPresentationMode() {
        if savedPresentationOptions == nil {
            savedPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions.insert([.autoHideDock, .autoHideMenuBar])
    }
    
    private func exitLauncherPresentationMode() {
        if let savedPresentationOptions {
            NSApp.presentationOptions = savedPresentationOptions
            self.savedPresentationOptions = nil
        }
    }
    
    // internal (not private) so OverlayWindowManagerTests can simulate key events via @testable import.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
case KeyCodes.escape: // Escape: if search is focused, unfocus it; else close folder if inside one; else hide launcher
if window?.firstResponder is NSTextView || window?.firstResponder is NSTextField {
// Search field is focused - unfocus it
window?.makeFirstResponder(nil)
return true
} else if let appModel = appModel, appModel.currentFolderId != nil {
// Inside a folder - go back to the root grid instead of dismissing
appModel.closeFolder()
return true
} else {
// At root and search is not focused - hide launcher
hide()
return true
}
        case KeyCodes.backspaceDelete: // Backspace/Delete: go up one level when inside a folder (and not editing search text)
            if window?.firstResponder is NSTextView || window?.firstResponder is NSTextField {
                return false
            }
            if let appModel = appModel, appModel.currentFolderId != nil {
                appModel.closeFolder()
                return true
            }
            return false
        case KeyCodes.returnEnter[0], KeyCodes.returnEnter[1]: // Return, Enter
            if let appModel = appModel, !appModel.searchTerm.isEmpty {
                let displayedApps = appModel.getDisplayedApps()
                if let first = displayedApps.first {
                    if first.isFolder, let folderId = first.folderId {
                        appModel.openFolder(folderId)
                        // Don't hide — user navigated into a folder
                        return true
                    }
                    appModel.launchAndDismiss(first)
                }
            } else {
                if let appModel = appModel {
                    let displayedApps = appModel.getDisplayedApps()
                    let idx = appModel.selectedAppIndex
                    if idx >= 0, idx < displayedApps.count {
                        let app = displayedApps[idx]
                        if app.isFolder {
                            // Folder selected — navigate in, don't dismiss
                            _ = appModel.launchSelectedApp()
                            return true
                        }
                        appModel.launchAndDismiss(app)
                    }
                }
            }
            return true
        case KeyCodes.forwardSlash: // Forward slash (/)
            // Focus search field when / is pressed
            NotificationCenter.default.post(name: NSNotification.Name("focusSearchField"), object: nil)
            return true
        case KeyCodes.leftArrow: // Left arrow - move selection left
            NotificationCenter.default.post(name: .keyboardNavigationDidStart, object: nil)
            appModel?.selectAppLeft()
            return true
        case KeyCodes.rightArrow: // Right arrow - move selection right
            NotificationCenter.default.post(name: .keyboardNavigationDidStart, object: nil)
            appModel?.selectAppRight()
            return true
        case KeyCodes.downArrow: // Down arrow - move selection down
            NotificationCenter.default.post(name: .keyboardNavigationDidStart, object: nil)
            appModel?.selectAppDown()
            return true
        case KeyCodes.upArrow: // Up arrow - move selection up
            NotificationCenter.default.post(name: .keyboardNavigationDidStart, object: nil)
            appModel?.selectAppUp()
            return true
        default:
            // Type-to-search: Spotlight, Launchpad, Alfred, and Raycast all let you start typing
            // the instant the window is open — no "/" or click required first. Mirror that instead
            // of silently dropping the keystroke. Only reachable when no text field already has
            // first responder (AppKit routes the event straight to the field in that case, so this
            // default case never fires), so there's no risk of double-handling a keystroke.
            if let appModel, isPlainTypingKeystroke(event) {
                appModel.searchTerm += event.characters ?? ""
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
                return true
            }
            return false
        }
    }

    /// Whether `event` represents an ordinary printable character typed with no command/control
    /// modifier — i.e. something that should start a search rather than be treated as a shortcut.
    /// Excludes control characters, Delete, and AppKit's function-key private-use range (arrows,
    /// F-keys, Home/End, etc. — already handled by the explicit cases above, or not search input).
    private func isPlainTypingKeystroke(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { return false }
        guard let characters = event.characters,
              let scalar = characters.unicodeScalars.first,
              characters.unicodeScalars.count == 1 else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
    }

    // MARK: - Arrow Key Event Monitoring

    private func installCombinedEventMonitor() {
        removeCombinedEventMonitor()

        let arrowKeyCodes: Set<UInt16> = Set([KeyCodes.leftArrow, KeyCodes.rightArrow, KeyCodes.downArrow, KeyCodes.upArrow])

        combinedKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Handle arrow keys first — consume when search is empty
            if arrowKeyCodes.contains(event.keyCode) {
                if let appModel = self?.appModel, !appModel.searchTerm.isEmpty {
                    return event // Search has content - pass to TextField for cursor movement
                }
                _ = self?.handleKeyDown(event)
                return nil // Consume the event (prevent TextField from seeing it)
            }

            // Always run selection collapse on every keyDown
            self?.collapseSearchFieldSelectionIfSelectAll()
            return event
        }
    }

    private func removeCombinedEventMonitor() {
        if let monitor = combinedKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            combinedKeyEventMonitor = nil
        }
    }

    private func installDisplayChangeObserver() {
        removeDisplayChangeObserver()
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleDisplayChange() }
        }
    }

    private func removeDisplayChangeObserver() {
        if let observer = displayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            displayChangeObserver = nil
        }
    }

    private func handleDisplayChange() {
        guard let window = window, window.isVisible else { return }
        let mode = appModel?.launchMode ?? .window
        guard mode == .fullscreen || mode == .maximized else { return }
        guard let targetScreen = preferredScreen(for: window) else { return }
        // Re-apply the current mode so the frame (full vs. visible) and background windows
        // stay correct for the new display configuration.
        applyWindowMode(mode, on: targetScreen)
    }

    // MARK: - Search Field Selection Fix

    /// AppKit auto-selects all existing text whenever a populated NSTextField becomes first
    /// responder (the standard select-all-on-focus behavior). With type-to-search, the first
    /// keystroke sets `searchTerm` *before* the field gains focus, so the field opens with that
    /// character already in it — and that character fully selected. The next keystroke then
    /// replaces it instead of appending, which is the reported bug.
    ///
    /// The previous approach observed `NSControl.textDidBeginEditingNotification`, but that
    /// notification fires *before* AppKit applies the auto-select-all, so the collapse was
    /// immediately overridden.
    ///
    /// Instead, install a local `keyDown` monitor that runs on *every* key event. AppKit applies
    /// its auto-select-all as part of making the field first responder, which happens *before*
    /// the next key event is dispatched. So at the moment our monitor runs — just before that
    /// next keystroke reaches the field editor — the select-all has already been applied. If we
    /// detect the full-string-selected state there, we collapse it to a cursor at the end, and
    /// the incoming keystroke appends instead of replacing.
    ///

    /// Detects AppKit's auto-select-all (whole string highlighted) and collapses it to a cursor
    /// at the end so the next keystroke appends. A manual selection or cursor is left untouched.
    private func collapseSearchFieldSelectionIfSelectAll() {
        guard let fieldEditor = window?.firstResponder as? NSText else { return }
        let length = (fieldEditor.string as NSString).length
        guard length > 0, isFullSelection(fieldEditor.selectedRange, fieldLength: length) else { return }
        collapseSelectionToEnd(of: fieldEditor)
    }

    /// True only when `range` covers the entire `fieldLength` (AppKit's auto-select-all state).
    /// Split out so the decision is unit-testable without a live window and first responder.
    nonisolated func isFullSelection(_ range: NSRange, fieldLength: Int) -> Bool {
        guard fieldLength > 0 else { return false }
        return range.location == 0 && range.length == fieldLength
    }

    /// Moves the insertion point to the end of `fieldEditor`, clearing any selection (such as the
    /// select-all AppKit applies when a populated field becomes first responder). Split out from
    /// `collapseSearchFieldSelectionIfSelectAll()` so the selection math is unit-testable without
    /// a live window and first responder; internal for `@testable` access.
    func collapseSelectionToEnd(of fieldEditor: NSText) {
        fieldEditor.selectedRange = NSRange(location: (fieldEditor.string as NSString).length, length: 0)
    }
}

// MARK: - Launch Wrapper View (zoom-out animation on first launch)

struct LaunchWrapperView: View {
    let appModel: AppModel
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Background and glow remain at full screen size (not scaled)
            VisualEffectBackground(appModel: appModel)
                .ignoresSafeArea()
                .opacity(appModel.overlayOpacity)
            GlowEffectView(appModel: appModel)
                .ignoresSafeArea()

            // Only content scales — zoom-out effect applied to UI grid
            ContentView(appModel: appModel)
                .scaleEffect(scale)
        }
        .onAppear {
            let shouldAnimate = !appModel.hasShownLauncher || appModel.launchAnimationEnabled
            guard shouldAnimate else { return }
            let startScale: CGFloat = switch appModel.launchAnimationDirection {
                case .zoomOut: WindowMetrics.launchZoomOutStartScale
                case .zoomIn: WindowMetrics.launchZoomInEndScale
            }
            scale = startScale
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: WindowMetrics.launchZoomOutDuration)) {
                    scale = 1.0
                }
            }
            appModel.hasShownLauncher = true
        }
    }
}

private struct SecondaryOverlayBackground: View {
    let appModel: AppModel
    
    var body: some View {
            VisualEffectBackground(appModel: appModel)

            .ignoresSafeArea()
            .opacity(appModel.overlayOpacity)
            .contentShape(Rectangle())
            .onTapGesture {
                StatusBarManager.shared.hideWindow()
            }
    }
}
