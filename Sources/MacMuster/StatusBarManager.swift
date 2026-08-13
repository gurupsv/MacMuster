import Foundation
import AppKit
import UniformTypeIdentifiers

// Inherits NSObject so it can be a valid NSMenuItem/NSStatusBarButton target-action receiver
// and so StatusBarManagerTests can call `.responds(to:)` (an NSObjectProtocol member).
@MainActor
class StatusBarManager: NSObject {
    static let shared = StatusBarManager()
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    // Deliberately NOT assigned to `statusItem.menu` directly — doing so makes AppKit pop up that
    // menu on *every* click (left and right), and the button's own target/action never fires at
    // all. Instead, `statusItemClicked` below inspects which mouse button was pressed and only
    // attaches/pops this menu for a right-click, so a left-click reaches `toggleWindow()`.
    private var rightClickMenu: NSMenu?
    private override init() {}

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshMenuBarIcon()

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: String(localized: "Show MacMuster"), action: #selector(showWindow), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let exportItem = NSMenuItem(title: String(localized: "Export Backup"), action: #selector(exportBackup), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        let restoreItem = NSMenuItem(title: String(localized: "Restore Backup"), action: #selector(restoreBackup), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: String(localized: "Settings"), action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: String(localized: "Quit MacMuster"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        rightClickMenu = menu
    }

    func setAppModel(_ model: AppModel) {
        appModel = model
    }

    func refreshMenuBarIcon() {
        guard let iconURL = Bundle.main.url(forResource: "MacMusterMenuBarTemplate", withExtension: "png"),
              let menuBarIcon = NSImage(contentsOf: iconURL) else { return }
        menuBarIcon.isTemplate = true
        menuBarIcon.size = NSSize(width: 18, height: 18)
        guard let button = statusItem?.button else { return }
        button.image = menuBarIcon
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem?.button else {
            toggleWindow()
            return
        }
        // Attach the menu only for this click, then detach it again — if it stayed attached,
        // the *next* left-click would also show it instead of reaching toggleWindow().
        statusItem?.menu = rightClickMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func toggleWindow() {
        // Toggle launcher visibility on menu bar button click
        if OverlayWindowManager.shared.isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    @objc func showWindow() {
        OverlayWindowManager.shared.show()
    }
    
    func hideWindow() {
        OverlayWindowManager.shared.hide()
    }
    
    @objc func exportBackup() {
        guard let url = BackupManager.shared.export() else { return }
        NSAlert.showInfo(String(localized: "Export Complete"), String(localized: "Backup saved to:\n\(url.path)"))
    }

    @objc func restoreBackup() {
        let jsonType = UniformTypeIdentifiers.UTType.json

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [jsonType]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.prompt = String(localized: "Open")
        openPanel.title = String(localized: "Restore MacMuster Backup")

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        guard let preview = BackupManager.shared.restore(from: url) else {
            NSAlert.showError(String(localized: "Invalid Archive"), String(localized: "The selected file is not a valid MacMuster backup."))
            return
        }

        if preview.missingAppPaths.isEmpty {
            BackupManager.shared.apply(preview: preview)
            NSAlert.showInfo(String(localized: "Restore Complete"), String(localized: "All data restored successfully."))
            return
        }

        let skippedCount = preview.missingAppPaths.count

        let previewPanel = RestorePreviewPanel(
            folderCount: preview.folderCount,
            appCount: preview.validAppPaths.count,
            missingCount: skippedCount,
            missingPaths: Array(preview.missingAppPaths)
        )
        Task { @MainActor in
            let result = await previewPanel.runModal()
            if result == .OK {
                BackupManager.shared.apply(preview: preview)
                NSAlert.showInfo(String(localized: "Restore Complete"), String(localized: "Data restored. \(skippedCount) app(s) skipped (no longer on disk)."))
            }
        }
    }

    @objc func showSettings() {
        SettingsWindowManager.shared.show()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
