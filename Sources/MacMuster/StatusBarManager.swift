import Foundation
import AppKit

@MainActor
class StatusBarManager {
    static let shared = StatusBarManager()
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    private init() {}
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let iconURL = Bundle.main.url(forResource: "MacMusterMenuBarTemplate", withExtension: "png"),
            let menuBarIcon = NSImage(contentsOf: iconURL) {
            menuBarIcon.isTemplate = true
            menuBarIcon.size = NSSize(width: 18, height: 18)
            if let button = statusItem?.button {
                button.image = menuBarIcon
                button.imagePosition = .imageOnly
                button.target = self
                button.action = #selector(toggleWindow)
            }
        }
        
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(title: "Show MacMuster", action: #selector(showWindow), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit MacMuster", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    func setAppModel(_ model: AppModel) {
        appModel = model
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
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
