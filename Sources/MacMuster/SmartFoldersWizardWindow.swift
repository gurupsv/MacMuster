import AppKit
import SwiftUI

/// A titled panel that can still become key, so the wizard's buttons and toggles work. A plain
/// `NSPanel` is a utility window that refuses to become key by default; overriding this makes it a
/// normal interactive window while keeping the panel's floating behavior.
final class SmartFoldersWizardPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the Smart Folders Wizard window. Follows the `SettingsWindowManager`/`RestorePreviewPanel`
/// house pattern: a `@MainActor` singleton that creates an `NSPanel` hosting SwiftUI.
///
/// A fresh `SmartFoldersWizardViewModel` is built on every `show`, so each opening of the wizard
/// starts from a clean state (no leftover plan or undo token from a previous run).
@MainActor
final class SmartFoldersWizardWindow: NSObject, NSWindowDelegate {
    static let shared = SmartFoldersWizardWindow()

    private var window: SmartFoldersWizardPanelWindow?
    private var model: SmartFoldersWizardViewModel?

    private override init() { super.init() }

    var isVisible: Bool { window?.isVisible == true }

    func show(appModel: AppModel) {
        // Already open: bring it forward instead of stacking a second panel. A second panel used to
        // orphan the first, and closing either one cleared the references to the other, leaving
        // the survivor's Cancel/Done buttons unable to close it.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SmartFoldersWizardViewModel(appModel: appModel)
        self.model = model

        let content = SmartFoldersWizardPanel(model: model) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingView(rootView: content)

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first).map(\.visibleFrame)
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = screenFrame.midX - WizardMetrics.windowWidth / 2
        let y = screenFrame.midY - WizardMetrics.windowHeight / 2

        let panel = SmartFoldersWizardPanelWindow(
            contentRect: NSRect(x: x, y: y, width: WizardMetrics.windowWidth, height: WizardMetrics.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = String(localized: "Smart Folders")
        panel.isRestorable = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = hosting

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        Task { @MainActor in await model.start() }
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
    }

    /// The title-bar close button is a cancel: tear the window down so the next `show` is fresh.
    func windowWillClose(_ notification: Notification) {
        // Only react to the panel we currently own; a stale notification must not clear a live one.
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        model = nil
    }
}
