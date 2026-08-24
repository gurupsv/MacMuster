import AppKit

// MARK: - Shared AppModel Singleton

@MainActor
final class AppModelContainer {
    static let shared = AppModelContainer()
    let appModel = AppModel()
    
    private init() {}
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to .regular so the app shows in the dock.
        // Without this, macOS uses .prohibited for menu-bar-only apps and hides the dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        updateApplicationIcon()
        observeAppearanceChanges()

        let appModel = AppModelContainer.shared.appModel

        // Set up status bar with the app model
        StatusBarManager.shared.setup()
        StatusBarManager.shared.setAppModel(appModel)

        // Set up overlay window manager with the app model
        OverlayWindowManager.shared.setup(appModel: appModel)

        // Set up settings window manager with the app model
        SettingsWindowManager.shared.setup(appModel: appModel)

        // Start tracking running apps and seed the library's running-path set. The tracker's
        // notification observers keep it current after this; the initial snapshot catches
        // apps that were already running before the launcher started (Finder, Dock, etc.).
        RunningAppTracker.shared.start()
        appModel.library.runningAppPaths = RunningAppTracker.shared.runningAppPaths

        // Show the overlay window on launch
        OverlayWindowManager.shared.show()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
        
        // Cleanup app model when app terminates
        AppModelContainer.shared.appModel.cleanupTimerAndObservers()
        
        // Persist recent launch times on termination
        RecentAppsTracker.shared.persistRecentLaunchTimes()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // Called when the user clicks the dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SettingsWindowManager.shared.isVisible {
            SettingsWindowManager.shared.show()
        } else {
            OverlayWindowManager.shared.show()
        }
        return true
    }
    
    private func observeAppearanceChanges() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateApplicationIcon()
                StatusBarManager.shared.refreshMenuBarIcon()
                let appModel = AppModelContainer.shared.appModel
                appModel.library.handleAppearanceChange()
            }
        }
    }
    
    private func updateApplicationIcon() {
        let iconName = isDarkAppearance ? "MacMusterIconDark" : "MacMusterIconLight"
        
        guard let iconURL = Bundle.main.url(forResource: iconName, withExtension: "png"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        
        NSApp.applicationIconImage = icon
    }
    
    private var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}