import AppKit
import SwiftUI

extension Notification.Name {
    static let launcherDidShow = Notification.Name("launcherDidShow")
}

// MARK: - Glow Effect View (SwiftUI overlay for glowing edges)

struct GlowEffectView: View {
    let appModel: AppModel
    
    /// Maximum opacity for the glow at the very edge
    private let glowMaxOpacity: CGFloat = 1.0
    
    var body: some View {
        if appModel.glowEnabled && appModel.glowIntensity > 0 {
            let color = appModel.glowColor
            let intensity = appModel.glowIntensity
            let glowInset = appModel.glowWidth
            
            Rectangle()
                .fill(.clear)
                // Top edge glow: brightest at top, fades inward
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(intensity * glowMaxOpacity),
                                    color.opacity(intensity * glowMaxOpacity * 0.6),
                                    color.opacity(intensity * glowMaxOpacity * 0.15),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: glowInset)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
                // Bottom edge glow
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(intensity * glowMaxOpacity),
                                    color.opacity(intensity * glowMaxOpacity * 0.6),
                                    color.opacity(intensity * glowMaxOpacity * 0.15),
                                    .clear,
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: glowInset)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
                // Left edge glow
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(intensity * glowMaxOpacity),
                                    color.opacity(intensity * glowMaxOpacity * 0.6),
                                    color.opacity(intensity * glowMaxOpacity * 0.15),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: glowInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
                // Right edge glow
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(intensity * glowMaxOpacity),
                                    color.opacity(intensity * glowMaxOpacity * 0.6),
                                    color.opacity(intensity * glowMaxOpacity * 0.15),
                                    .clear,
                                ],
                                startPoint: .trailing,
                                endPoint: .leading
                            )
                        )
                        .frame(width: glowInset)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                )
                .allowsHitTesting(false)
                .drawingGroup(opaque: false)
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
}

@MainActor
class OverlayWindowManager {
    static let shared = OverlayWindowManager()

    private var window: OverlayWindow?
    private var backgroundWindows: [NSWindow] = []
    private weak var appModel: AppModel?
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var arrowKeyEventMonitor: Any?
    private var displayChangeObserver: NSObjectProtocol?
    private var searchFieldSelectionFixMonitor: Any?

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
        let backgroundColor = NSColor.black.withAlphaComponent(appModel.overlayOpacity)
        window?.backgroundColor = backgroundColor
        window?.hasShadow = false
        
        // Set minimum size for content
        window?.minSize = NSSize(width: kWindowMinWidth, height: kWindowMinHeight)
        
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

// Make the window visible, screen-sized, and key for input, and hide the dock/menu bar.
// enterLauncherPresentationMode() restores autoHideDock + autoHideMenuBar — previously
// commented out during Fix 2, but it is required for full-screen Launchpad-like behavior.
guard let targetScreen = preferredScreen(for: window) else { return }
// Use full frame for all screens to cover the entire display including the notch area.
let screenFrame: NSRect = targetScreen.frame

window.setFrame(screenFrame, display: true)
showBackgroundWindows(excluding: targetScreen)
window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        enterLauncherPresentationMode()

        // Ensure the hosting view resizes to match the new window frame.
        window.contentView?.frame = CGRect(origin: .zero, size: screenFrame.size)

        // Install a local event monitor to capture arrow keys even when search field is focused.
        // This is necessary because SwiftUI's TextField intercepts arrow keys before the
        // window's keyDown handler can see them.
        installArrowKeyMonitor()

        // Observe display configuration changes (monitor plugged in/out, resolution change, etc.)
        installDisplayChangeObserver()

        installSearchFieldSelectionFix()

        DispatchQueue.main.asyncAfter(deadline: .now() + kWindowAnimationDelay) {
            NotificationCenter.default.post(name: .launcherDidShow, object: window)
        }
    }
    
    func hide() {
        window?.orderOut(nil)
        hideBackgroundWindows()
        exitLauncherPresentationMode()
        appModel?.clearSearchState()
        removeArrowKeyMonitor()
        removeDisplayChangeObserver()
        removeSearchFieldSelectionFix()
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
case 53: // Escape: if search is focused, unfocus it; else close folder if inside one; else hide launcher
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
        case 51: // Backspace/Delete: go up one level when inside a folder (and not editing search text)
            if window?.firstResponder is NSTextView || window?.firstResponder is NSTextField {
                return false
            }
            if let appModel = appModel, appModel.currentFolderId != nil {
                appModel.closeFolder()
                return true
            }
            return false
        case 36, 76: // Return, Enter
            if let appModel = appModel, !appModel.searchTerm.isEmpty {
                let displayedApps = appModel.getDisplayedApps()
                if let first = displayedApps.first {
                    if first.isFolder, let folderId = first.folderId {
                        appModel.openFolder(folderId)
                        // Don't hide — user navigated into a folder
                        return true
                    }
                    ApplicationService.shared.launchApplication(at: first.path, appModel: appModel)
                }
            } else {
                if let appModel = appModel {
                    let displayedApps = appModel.getDisplayedApps()
                    let idx = appModel.selectedAppIndex
                    if idx >= 0, idx < displayedApps.count, displayedApps[idx].isFolder {
                        // Folder selected — navigate in, don't hide
                        appModel.launchSelectedApp()
                        return true
                    }
                }
                appModel?.launchSelectedApp()
            }
            hide()
            return true
        case 43: // Forward slash (/)
            // Focus search field when / is pressed
            NotificationCenter.default.post(name: NSNotification.Name("focusSearchField"), object: nil)
            return true
        case 123: // Left arrow - move selection left
            NotificationCenter.default.post(name: NSNotification.Name("keyboardNavigationDidStart"), object: nil)
            appModel?.selectAppLeft()
            return true
        case 124: // Right arrow - move selection right
            NotificationCenter.default.post(name: NSNotification.Name("keyboardNavigationDidStart"), object: nil)
            appModel?.selectAppRight()
            return true
        case 125: // Down arrow - move selection down
            NotificationCenter.default.post(name: NSNotification.Name("keyboardNavigationDidStart"), object: nil)
            appModel?.selectAppDown()
            return true
        case 126: // Up arrow - move selection up
            NotificationCenter.default.post(name: NSNotification.Name("keyboardNavigationDidStart"), object: nil)
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
                NotificationCenter.default.post(name: NSNotification.Name("focusSearchField"), object: nil)
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

    private func installArrowKeyMonitor() {
        removeArrowKeyMonitor()

        let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]  // Left, Right, Down, Up

        arrowKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard arrowKeyCodes.contains(event.keyCode) else { return event }

            // Only consume arrow keys when search is empty - allow cursor movement when searching
            if let appModel = self?.appModel, !appModel.searchTerm.isEmpty {
                // Search has content - pass event to TextField for cursor movement
                return event
            }

            // Let our handler process it
            _ = self?.handleKeyDown(event)

            // Return nil to consume the event (prevent TextField from seeing it)
            return nil
        }
    }

    private func removeArrowKeyMonitor() {
        if let monitor = arrowKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            arrowKeyEventMonitor = nil
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
        guard let targetScreen = preferredScreen(for: window) else { return }
        let newFrame = targetScreen.frame
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
            window.contentView?.frame = CGRect(origin: .zero, size: newFrame.size)
            showBackgroundWindows(excluding: targetScreen)
        }
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
    /// This handles all focus paths uniformly (type-to-search, the "/" shortcut, and clicking
    /// the search icon) and only intervenes when the *entire* string is selected — a manual
    /// cursor or partial selection is left alone.
    private func installSearchFieldSelectionFix() {
        removeSearchFieldSelectionFix()
        searchFieldSelectionFixMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.collapseSearchFieldSelectionIfSelectAll()
            return event
        }
    }

    private func removeSearchFieldSelectionFix() {
        if let monitor = searchFieldSelectionFixMonitor {
            NSEvent.removeMonitor(monitor)
            searchFieldSelectionFixMonitor = nil
        }
    }

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
        range.location == 0 && range.length == fieldLength
    }

    /// Moves the insertion point to the end of `fieldEditor`, clearing any selection (such as the
    /// select-all AppKit applies when a populated field becomes first responder). Split out from
    /// `collapseSearchFieldSelectionIfSelectAll()` so the selection math is unit-testable without
    /// a live window and first responder; internal for `@testable` access.
    nonisolated func collapseSelectionToEnd(of fieldEditor: NSText) {
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
            VisualEffectBackground()
                .ignoresSafeArea()
                .opacity(appModel.overlayOpacity)
            GlowEffectView(appModel: appModel)

            // Only content scales — zoom-out effect applied to UI grid
            ContentView(appModel: appModel)
                .scaleEffect(scale)
        }
        .onAppear {
            guard !appModel.hasShownLauncher else { return }
            // Set the starting scale *before* the next render tick so SwiftUI
            // picks up the initial value, then animate back to 1.0.
            scale = kLaunchZoomOutStartScale
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: kLaunchZoomOutDuration)) {
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
        VisualEffectBackground()
            .ignoresSafeArea()
            .opacity(appModel.overlayOpacity)
            .contentShape(Rectangle())
            .onTapGesture {
                StatusBarManager.shared.hideWindow()
            }
    }
}
