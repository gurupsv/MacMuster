import Foundation
import AppKit

/// Tracks which apps are currently running, by observing `NSWorkspace` launch/terminate
/// notifications and snapshotting `runningApplications` on start.
///
/// This is Phase 2 of the app status indicator: a small "running" dot on each app cell
/// whose bundle path matches a currently-running process. The match is by **filesystem
/// path** (the existing `Application.id`), not bundle identifier — the rest of the app
/// identifies apps by path, so a path match keeps the running badge consistent with every
/// other per-app state (hidden, foldered, recently launched) without adding a bundle-id
/// lookup to the data model.
///
/// Singleton per `AGENTS.md`: `@MainActor`, `static let shared`, `private init()`. The
/// notification observers are installed in `start()` (called from `AppDelegate` on launch)
/// and removed in `stop()` (called from `LibraryScanState.cleanupTimerAndObservers` on
/// terminate) — the install/remove pair mirrors the appearance observer in `AppDelegate`.
@MainActor
final class RunningAppTracker {
    static let shared = RunningAppTracker()
    private init() {}

    /// Filesystem paths of currently-running app bundles. Drives the running dot in
    /// `AppIconView`. Left mutable (not `private(set)`) to mirror `RecentAppsTracker`'s
    /// convention — tests reset it in tearDown.
    var runningAppPaths: Set<String> = []

    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var didChangeScreenObserver: NSObjectProtocol?

    /// Snapshots the currently-running apps and installs launch/terminate observers.
    /// Idempotent — safe to call more than once; a second call just refreshes the snapshot
    /// and re-installs the observers (the previous ones are removed first).
    func start() {
        stop()
        refreshSnapshot()
        let center = NSWorkspace.shared.notificationCenter
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // `addObserver(...queue:.main...)` hands a `@Sendable` closure that runs on the main
            // queue but is not inferred as main-actor-isolated under Swift 6, so the mutation
            // hops through an explicit `Task { @MainActor }` — the same pattern AppDelegate uses
            // for its appearance observer. The path is extracted before the hop so the
            // `Notification` (a value type) is read in the closure's own context, not sent across
            // the actor boundary.
            let path = Self.appPath(from: notification)
            Task { @MainActor [weak self] in
                guard let self, let path else { return }
                self.runningAppPaths.insert(path)
            }
        }
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let path = Self.appPath(from: notification)
            Task { @MainActor [weak self] in
                guard let self, let path else { return }
                self.runningAppPaths.remove(path)
            }
        }
    }

    /// Removes the observers. Called on app termination. Leaves `runningAppPaths` in place
    /// (it's about to be discarded with the process anyway), so the next `start()` rebuilds
    /// from a fresh snapshot.
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver { center.removeObserver(launchObserver); self.launchObserver = nil }
        if let terminateObserver { center.removeObserver(terminateObserver); self.terminateObserver = nil }
    }

    /// Rebuilds `runningAppPaths` from `NSWorkspace.shared.runningApplications`. Called on
    /// `start()` and exposed for tests/refresh — the notification observers keep the set
    /// current after that, but the snapshot is the source of truth for apps that were
    /// already running before this launcher started (e.g. Finder, Dock).
    ///
    /// Only `.app` bundles are included — `NSRunningApplication.bundleURL` reports a bundle
    /// URL for *every* running process type (XPC services, `.appex` extensions, framework
    /// support daemons, plain executables in `/usr/libexec`), but the UI badge matches
    /// against `Application.path`, which is always a `.app` bundle. Including non-`.app`
    /// paths would bloat the set with entries that never match, so they're filtered here.
    func refreshSnapshot() {
        var paths = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let path = app.bundleURL?.path, path.hasSuffix(".app") {
                paths.insert(path)
            }
        }
        runningAppPaths = paths
    }

    func isRunning(_ path: String) -> Bool {
        runningAppPaths.contains(path)
    }

    /// Extracts the launched/terminated app's bundle path from an `NSWorkspace` notification.
    /// The notification's `userInfo` carries the app under `NSWorkspace.applicationUserInfoKey`.
    /// `nonisolated` so it can be called from the `@Sendable` observer closure before the
    /// main-actor hop — it only reads the notification's dictionary, no actor-isolated state.
    /// Returns nil for non-`.app` bundles (XPC services, `.appex` extensions, etc.) so the
    /// running set stays tight — see `refreshSnapshot` for the matching rationale.
    nonisolated private static func appPath(from notification: Notification) -> String? {
        guard let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return nil
        }
        guard let path = runningApp.bundleURL?.path, path.hasSuffix(".app") else { return nil }
        return path
    }
}