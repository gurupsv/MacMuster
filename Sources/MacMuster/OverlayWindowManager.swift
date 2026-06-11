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

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
    
    // Track last screen frame to persist across launches
    private var lastScreenFrame: NSRect?
    
    func setup(appModel: AppModel) {
        self.appModel = appModel
        
        // Store reference for later use in StatusBarManager
        StatusBarManager.shared.setAppModel(appModel)
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        
        // Glow is rendered inside ContentView, on top of VisualEffectBackground
        let contentViewWithGlow = ContentView(appModel: appModel)
            .environment(appModel)
        
        window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
// Keep the launcher above ordinary app windows. Dock/menu bar hiding is
// handled with presentation options while the launcher is visible.
window?.level = .floating
        
        // Configure collection behavior for overlay behavior
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window?.isMovableByWindowBackground = false
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        
        // Set minimum size for content
        window?.minSize = NSSize(width: kWindowMinWidth, height: kWindowMinHeight)
        
        // Hide title bar buttons (should already be hidden with borderless)
        window?.standardWindowButton(.closeButton)?.isHidden = true
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Set SwiftUI content - use safe area inset to avoid notch
        let hostingView = NSHostingView(rootView: contentViewWithGlow)
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window?.contentView = hostingView
        
        window?.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }
    
    func show() {
        guard let window else { return }

// Make the window visible, screen-sized, and key for input.
window.level = .floating
enterLauncherPresentationMode()

let targetScreen = preferredScreen(for: window)
// Use visibleFrame for main screen to avoid menu bar overlap,
// use full frame for secondary displays to cover everything
let screenFrame: NSRect
if targetScreen == NSScreen.main {
    screenFrame = targetScreen.visibleFrame
} else {
    screenFrame = targetScreen.frame
}

window.setFrame(screenFrame, display: true)
showBackgroundWindows(excluding: targetScreen)
window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure the hosting view resizes to match the new window frame.
        window.contentView?.frame = CGRect(origin: .zero, size: screenFrame.size)

        // Install a local event monitor to capture arrow keys even when search field is focused.
        // This is necessary because SwiftUI's TextField intercepts arrow keys before the
        // window's keyDown handler can see them.
        installArrowKeyMonitor()

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
    }
    
    private func preferredScreen(for window: NSWindow) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        
        // First, check if the mouse is on any screen
        let allScreens = NSScreen.screens
        for screen in allScreens {
            // Use containsPoint to handle negative coordinates correctly
            // NSMouseInRect may not work correctly when screens have negative origins
            let rectInWindowCoords = CGRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.size.width, height: screen.frame.size.height)
            if rectInWindowCoords.contains(mouseLocation) {
                return screen
            }
        }
        
        // If mouse isn't over a screen (e.g., all screens covered by launcher),
        // use the window's current screen or main screen
        if let windowScreen = window.screen, allScreens.contains(windowScreen) {
            return windowScreen
        }
        
        if let mainScreen = NSScreen.main, allScreens.contains(mainScreen) {
            return mainScreen
        }
        
        // Fallback to first available screen
        return allScreens.first!
    }
    
    private func showBackgroundWindows(excluding targetScreen: NSScreen) {
        hideBackgroundWindows()
        
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
                backgroundWindow.backgroundColor = .clear
                backgroundWindow.hasShadow = false
                backgroundWindow.contentView = NSHostingView(rootView: SecondaryOverlayBackground())
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
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
case 53:
// Escape: if search is focused, unfocus it; otherwise hide launcher
if window?.firstResponder is NSTextView || window?.firstResponder is NSTextField {
// Search field is focused - unfocus it
window?.makeFirstResponder(nil)
return true
} else {
// Search is not focused - hide launcher
hide()
return true
}
        case 36, 76: // Return, Enter
            // Critical fix Issue 39: contextual Enter behavior
            // If search has results, launch first result; if navigating, launch selected app
            if let appModel = appModel, !appModel.searchTerm.isEmpty {
                let displayedApps = appModel.getDisplayedApps()
                if !displayedApps.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: displayedApps[0].path))
                    appModel.recordAppLaunch(at: displayedApps[0].path)
                }
            } else {
                appModel?.launchSelectedApp()
            }
            hide()
            return true
        case 43: // Forward slash (/)
            // Focus search field when / is pressed
            NotificationCenter.default.post(name: NSNotification.Name("focusSearchField"), object: nil)
            return true
        case 123: // Left arrow - move selection left
            appModel?.selectAppLeft()
            return true
        case 124: // Right arrow - move selection right
            appModel?.selectAppRight()
            return true
        case 125: // Down arrow - move selection down
            appModel?.selectAppDown()
            return true
        case 126: // Up arrow - move selection up
            appModel?.selectAppUp()
            return true
        default:
            return false
        }
    }

    // MARK: - Arrow Key Event Monitoring

    private func installArrowKeyMonitor() {
        removeArrowKeyMonitor()

        let keyCodesToMonitor: Set<UInt16> = [123, 124, 125, 126]  // Left, Right, Down, Up

        arrowKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard keyCodesToMonitor.contains(event.keyCode) else { return event }

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
}

private struct SecondaryOverlayBackground: View {
    var body: some View {
        VisualEffectBackground()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                StatusBarManager.shared.hideWindow()
            }
    }
}