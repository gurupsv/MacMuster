import AppKit
import SwiftUI

extension Notification.Name {
    static let launcherDidShow = Notification.Name("launcherDidShow")
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
    
    func setup(appModel: AppModel) {
        self.appModel = appModel
        
        // Store reference for later use in StatusBarManager
        StatusBarManager.shared.setAppModel(appModel)
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        
        let contentView = ContentView(appModel: appModel)
        
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
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = frame
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
        let screenFrame = targetScreen.frame

        window.setFrame(screenFrame, display: true)
        showBackgroundWindows(excluding: targetScreen)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // Ensure the hosting view resizes to match the new window frame.
        if let hostingView = window.contentView as? NSHostingView<ContentView> {
            hostingView.frame = screenFrame
        }

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
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first!
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
            if window?.firstResponder is NSTextView {
                // Search field is focused - unfocus it
                window?.makeFirstResponder(nil)
                return true
            } else {
                // Search is not focused - hide launcher
                hide()
                return true
            }
        case 126: // Up arrow — move up by column count (previous row)
            appModel?.selectAppUp()
            return true
        case 125: // Down arrow — move down by column count (next row)
            appModel?.selectAppDown()
            return true
        case 123: // Left arrow — move left
            appModel?.selectAppLeft()
            return true
        case 124: // Right arrow — move right
            appModel?.selectAppRight()
            return true
        case 36, 76: // Return, Enter
            appModel?.launchSelectedApp()
            hide()
            return true
        case 43: // Forward slash (/)
            // Focus search field when / is pressed
            NotificationCenter.default.post(name: NSNotification.Name("focusSearchField"), object: nil)
            return true
        default:
            return false
        }
    }

    // MARK: - Arrow Key Event Monitoring

    private func installArrowKeyMonitor() {
        // Use a local event monitor to capture arrow keys even when TextField is focused.
        // This runs before the window's keyDown handler and before SwiftUI processes the event.
        let keyCodesToMonitor: Set<UInt16> = [123, 124, 125, 126]  // Left, Right, Down, Up

        arrowKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard keyCodesToMonitor.contains(event.keyCode) else { return event }

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
