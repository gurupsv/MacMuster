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
        
        NSApp.unhide(nil)
        
        if !settingsWindow.isVisible {
            settingsWindow.center()
        }
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    func hide() {
        settingsWindow?.orderOut(nil)
    }
    
    private func createSettingsWindow() {
        guard let appModel else { return }
        
        let contentView = SettingsContentView(appModel: appModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // Use a larger initial size that accommodates the content comfortably
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first).map(\.visibleFrame) ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowX = screenFrame.midX - (WindowMetrics.settingsWindowWidth / 2)
        let windowY = screenFrame.midY - (WindowMetrics.settingsWindowHeight / 2)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: WindowMetrics.settingsWindowWidth, height: WindowMetrics.settingsWindowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.title = String(localized: "Settings")
        settingsWindow?.isRestorable = false
        settingsWindow?.hasShadow = true
        settingsWindow?.level = .floating
        settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsWindow?.isReleasedWhenClosed = false
        settingsWindow?.contentView = hostingView
        
        // Set minimum and maximum size to ensure content is always comfortably visible
        settingsWindow?.minSize = NSSize(width: WindowMetrics.settingsWindowMinWidth, height: WindowMetrics.settingsWindowMinHeight)
        settingsWindow?.maxSize = NSSize(width: WindowMetrics.settingsWindowMaxWidth, height: WindowMetrics.settingsWindowMaxHeight)
    }
}
