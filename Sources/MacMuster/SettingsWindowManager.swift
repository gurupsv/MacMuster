import Foundation
import AppKit
import SwiftUI

@MainActor
class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private weak var appModel: AppModel?
    
    var isVisible: Bool {
        settingsWindow?.isVisible == true
    }
    
    private init() {}
    
    func setup(appModel: AppModel) {
        self.appModel = appModel
    }
    
    func show() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        guard let settingsWindow else { return }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        
        if !settingsWindow.isVisible {
            settingsWindow.center()
        }
        
        DispatchQueue.main.async {
            settingsWindow.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
        }
    }
    
    func hide() {
        settingsWindow?.orderOut(nil)
    }
    
    private func createSettingsWindow() {
        guard let appModel else { return }
        
        let contentView = SettingsContentView()
            .environmentObject(appModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // Use a larger initial size that accommodates the content comfortably
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first!.visibleFrame
        let windowX = screenFrame.midX - (kSettingsWindowWidth / 2)
        let windowY = screenFrame.midY - (kSettingsWindowHeight / 2)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: kSettingsWindowWidth, height: kSettingsWindowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.title = "Settings"
        settingsWindow?.isRestorable = false
        settingsWindow?.hasShadow = true
        settingsWindow?.level = .modalPanel
        settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsWindow?.isReleasedWhenClosed = false
        settingsWindow?.contentView = hostingView
        
        // Set minimum and maximum size to ensure content is always comfortably visible
        settingsWindow?.minSize = NSSize(width: kSettingsWindowMinWidth, height: kSettingsWindowMinHeight)
        settingsWindow?.maxSize = NSSize(width: kSettingsWindowMaxWidth, height: kSettingsWindowMaxHeight)
    }
}
