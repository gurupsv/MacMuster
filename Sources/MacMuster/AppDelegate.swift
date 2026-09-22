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

    /// The activation policy to launch with, given the persisted "Show in Dock" preference.
    /// `.regular` shows a Dock icon and app-switcher entry; `.accessory` is the menu-bar-only mode
    /// `DockSettingsPanel` switches to at runtime via the same mapping. Split into a pure,
    /// `nonisolated` function — rather than inlined in `applicationDidFinishLaunching` — so it's
    /// unit-testable without invoking that method, which the existing test suite deliberately
    /// avoids calling (it creates the status item, overlay window, and other live app state a
    /// unit test has no business triggering).
    nonisolated static func activationPolicy(showInDock: Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }

    /// Whether to auto-show the overlay window as part of this launch.
    ///
    /// The overlay used to appear unconditionally on every launch, including the silent relaunch
    /// macOS performs at login once "Start at Login" is enabled (`SMAppService.mainApp`) — there is
    /// no reliable way to distinguish that from a manual launch (parent-PID checks are not
    /// dependable post-Ventura, since Background Task Management launches login items indirectly),
    /// and trying to would need a separate helper-app login item target this project's SPM/bash
    /// build doesn't have.
    ///
    /// Sidestepping that: only the very first launch ever (fresh install, or prefs cleared) shows
    /// the window automatically, for onboarding. Every launch after that — login-triggered or
    /// not — stays silent; the user reveals it via the menu-bar click (`StatusBarManager
    /// .toggleWindow`) or the Dock/launcher icon (`applicationShouldHandleReopen`), both already
    /// wired up. `hasShownLauncher` already persists across launches and already flips to `true`
    /// the moment the window is shown once (`LaunchWrapperView.onAppear`), which is exactly the
    /// gate this needs — no new state to track.
    nonisolated static func shouldShowOverlayOnLaunch(hasShownLauncher: Bool) -> Bool {
        !hasShownLauncher
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registered first, before anything else in this method runs, and paired with an
        // immediate proactive sweep below. The always-shown overlay used to mask a latent race
        // here: AppKit can create and key the empty Settings-scene window (see
        // `windowDidBecomeKey`'s doc comment) before this method even starts, in which case an
        // observer registered later never sees that becomeKey event — the window quietly stayed
        // open, just hidden underneath the overlay's full-screen floating window. Now that a
        // typical launch shows no window at all (`shouldShowOverlayOnLaunch`), that stray window
        // would otherwise be the only thing on screen.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
        closeStraySettingsWindows()

        // Respect the persisted "Show in Dock" setting (DockSettingsPanel toggles between these
        // same two policies at runtime via PreferencesStore.saveShowInDock). Without reading it
        // here, a user who hid the Dock icon saw .regular applied unconditionally on every
        // relaunch — the toggle only ever took effect until the app quit. `.regular` shows a Dock
        // icon; `.accessory` is what a menu-bar-only app needs (the default, .prohibited, hides
        // both the Dock icon and the app switcher entry, which this app needs for the status item
        // to still work as a real UI surface).
        NSApp.setActivationPolicy(Self.activationPolicy(showInDock: PreferencesStore.shared.loadShowInDock()))
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

        // Start tracking running apps. The hook is installed *before* `start()` so the initial
        // snapshot — which catches apps already running before the launcher started (Finder,
        // Dock, etc.) — arrives through the same path as every later launch and quit.
        //
        // Assigning `RunningAppTracker.shared.runningAppPaths` across once is what this replaces:
        // a `Set` is a value type, so that copied a snapshot frozen at launch and the badge never
        // moved again.
        RunningAppTracker.shared.onChange = { [weak appModel] paths in
            appModel?.library.runningAppPaths = paths
        }
        RunningAppTracker.shared.start()

        // Show the overlay window only on the very first launch ever — see
        // `shouldShowOverlayOnLaunch`. Every later launch (including a silent "Start at Login"
        // relaunch) stays silent until the user clicks the menu-bar icon or the Dock/launcher icon.
        if Self.shouldShowOverlayOnLaunch(hasShownLauncher: appModel.hasShownLauncher) {
            OverlayWindowManager.shared.show()
        }

        // `MacMusterApp` declares a `Settings { EmptyView() }` scene purely to give SwiftUI a
        // Scene that (unlike `WindowGroup`) doesn't need a document/window to open with. That
        // was documented here as "never auto-opens a window on launch" — true when the app has
        // no other window-bearing scene, but this app also calls `setActivationPolicy(.regular)`
        // above with no `WindowGroup` anywhere in the Scene graph, and empirically (confirmed by
        // actually launching the built app) AppKit falls back to opening that Settings scene's
        // window as the "regular" app's initial window. So the empty window isn't only reachable
        // through the app-menu item below — it can appear unprompted, before this method (or its
        // deferred block) ever runs, which is why it's swept and observed for at the very top of
        // this method rather than here. The menu-item redirect below still matters on top of
        // that — without it, a user who explicitly chooses "Settings…" (⌘,) after the stray
        // window has already been closed once would just trigger AppKit into creating and
        // showing a fresh empty one again.
        DispatchQueue.main.async { [weak self] in
            self?.redirectSettingsMenuItem()
        }
    }

    /// Closes the OS-generated empty Settings window the instant it becomes key, wherever it came
    /// from — launch-time auto-open, or `showSettingsWindow:` firing before `redirectSettingsMenuItem`
    /// has retargeted its menu item. Matches purely on title (`"<process name> Settings"`, which is
    /// what AppKit names that window and title-cases from `ProcessInfo.processInfo.processName`,
    /// confirmed empirically against a real launch), since the window itself is otherwise
    /// indistinguishable from any other `NSWindow` from outside SwiftUI's private Settings-scene
    /// machinery. `SettingsWindowManager`'s own window is titled plainly "Settings" (no process
    /// name prefix) specifically so it can never collide with this check.
    ///
    /// Internal rather than private so a test can call it directly with a synthetic notification,
    /// the same way `redirectSettingsMenuItem` is opened up for its own tests below.
    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == "\(ProcessInfo.processInfo.processName) Settings" else { return }
        window.close()
    }

    /// Proactively closes any stray empty Settings window that already exists, by the same title
    /// match as `windowDidBecomeKey`. That observer only catches windows that become key *after*
    /// it is registered; this sweep catches one AppKit already created and keyed before this
    /// process got a chance to observe it — the scenario `windowDidBecomeKey`'s doc comment
    /// describes. Internal rather than `private` so a test can call it directly.
    func closeStraySettingsWindows() {
        for window in NSApp.windows where window.title == "\(ProcessInfo.processInfo.processName) Settings" {
            window.close()
        }
    }

    /// Retargets the OS-generated "Settings…" menu item (added because of the `Settings` scene
    /// in `MacMusterApp`) to `showSettings()` instead of the empty scene it defaults to.
    /// `showSettingsWindow:` is the selector AppKit gives that item; it isn't public API, so this
    /// is a best-effort swap — if the item isn't found (a macOS version that names or wires it
    /// differently), the item is simply left alone rather than crashing.
    ///
    /// Takes the app submenu explicitly (default: `NSApp`'s own) so a test can hand in a menu it
    /// built itself rather than depending on the real app menu's structure.
    func redirectSettingsMenuItem(in appMenu: NSMenu? = nil) {
        guard let appMenu = appMenu ?? NSApp.mainMenu?.items.first?.submenu else { return }
        for item in appMenu.items where item.action == Selector(("showSettingsWindow:")) {
            item.target = self
            item.action = #selector(showSettings)
        }
    }

    @objc func showSettings() {
        SettingsWindowManager.shared.show()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)

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