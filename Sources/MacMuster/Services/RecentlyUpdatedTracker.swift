import Foundation

/// Tracks which apps were "recently updated" by detecting bundle-mtime changes between scans.
///
/// This is the buildable interpretation of an App Store "patching progress" indicator: macOS
/// exposes no public API for App Store download progress, but when an update *completes* the
/// app's bundle mtime jumps. By persisting the last-seen mtime per app path and comparing on
/// each scan, this tracker flags apps whose bundle was rewritten since the previous scan —
/// the moment a patch lands.
///
/// The tracker is deliberately mtime-based and does not check for an App Store receipt
/// (`Contents/_MASReceipt`): the signal is "this app was patched", not "this app was patched by
/// the App Store", so it also fires for direct-download updates and manual reinstalls. That
/// matches the honest definition of the badge — a download-progress % is unreachable, but a
/// "this app just changed" badge is both reachable and useful.
///
/// Singleton per `AGENTS.md`: `@MainActor`, `static let shared`, `private init()`.
@MainActor
final class RecentlyUpdatedTracker {
    static let shared = RecentlyUpdatedTracker()
    private init() {}

    /// Per-app last-seen bundle mtime, persisted across launches so a relaunch doesn't
    /// re-badge every app as "updated" (without a baseline, the first scan would compare
    /// every app's current mtime against nothing and flag them all).
    ///
    /// Keyed by app path to match how the rest of the app identifies apps (the `Application.id`
    /// is the filesystem path). Values are mtimes at second granularity — subsecond precision
    /// would make the delta comparison noisy, and `IconCacheManager` already compares mtimes
    /// at second granularity for the same reason.
    ///
    /// Left mutable (not `private(set)`) to mirror `RecentAppsTracker.recentAppLaunchTimes` —
    /// tests seed stale state directly to exercise pruning and persistence, the same way
    /// `RecentAppsTrackerTests` does.
    var knownBundleMtimes: [String: Date] = [:]

    /// App paths currently flagged as recently updated, with the date the update was first
    /// noticed. Evicted after `UpdateMetrics.recentlyUpdatedBadgeSeconds`.
    var recentlyUpdated: [String: Date] = [:]

    private var persistenceTask: Task<Void, Never>?

    // MARK: - Detection

    /// Compares each app's current bundle mtime against the last-seen mtime, flagging apps
    /// whose mtime increased beyond `UpdateMetrics.mtimeDeltaEpsilonSeconds` as recently
    /// updated. Updates `knownBundleMtimes` to the new mtimes so the next call sees only
    /// further changes.
    ///
    /// `currentMtimesByPath` is passed in rather than read here so the caller can batch the
    /// filesystem stats once and share them with the icon cache, folder rebuild, etc. Apps
    /// that no longer appear (path absent from `currentMtimesByPath`) are pruned from both
    /// `knownBundleMtimes` and `recentlyUpdated` — a deleted app shouldn't keep a stale badge.
    func detectUpdatedApps(currentMtimesByPath: [String: Date], now: Date = Date()) {
        var updatedPaths: [String] = []

        for (path, currentMtime) in currentMtimesByPath {
            if let previousMtime = knownBundleMtimes[path] {
                let delta = currentMtime.timeIntervalSince(previousMtime)
                if delta > UpdateMetrics.mtimeDeltaEpsilonSeconds {
                    updatedPaths.append(path)
                }
            }
            // Update the baseline regardless of whether it fired, so the *next* delta is
            // measured from this scan, not the pre-update mtime.
            knownBundleMtimes[path] = currentMtime
        }

        // Prune apps that are gone from the current scan.
        let currentPaths = Set(currentMtimesByPath.keys)
        for path in knownBundleMtimes.keys where !currentPaths.contains(path) {
            knownBundleMtimes.removeValue(forKey: path)
        }
        for path in recentlyUpdated.keys where !currentPaths.contains(path) {
            recentlyUpdated.removeValue(forKey: path)
        }

        for path in updatedPaths {
            recentlyUpdated[path] = now
        }

        pruneExpired(now: now)
        schedulePersist()
    }

    /// Removes entries older than `UpdateMetrics.recentlyUpdatedBadgeSeconds` from
    /// `recentlyUpdated`. `knownBundleMtimes` is not pruned by age — it is the baseline
    /// against which future deltas are measured, so it must retain the most recent mtime
    /// for every app indefinitely.
    func pruneExpired(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds)
        for (path, detectedAt) in recentlyUpdated where detectedAt < cutoff {
            recentlyUpdated.removeValue(forKey: path)
        }
    }

    func isRecentlyUpdated(_ path: String) -> Bool {
        recentlyUpdated[path] != nil
    }

    /// Clears all tracked state. Used by tests and by "Clear Recently Updated" if ever exposed.
    func clearAll() {
        knownBundleMtimes.removeAll()
        recentlyUpdated.removeAll()
        schedulePersist()
    }

    // MARK: - Persistence

    /// Loads both maps from `UserDefaults`. Called once on startup before the first scan,
    /// so the first `detectUpdatedApps` call measures deltas against the pre-relaunch
    /// baseline instead of treating every app as new.
    func loadFromDefaults() {
        knownBundleMtimes = PreferencesStore.shared.loadKnownBundleMtimes() ?? [:]
        let savedRecentlyUpdated = PreferencesStore.shared.loadRecentlyUpdatedPaths() ?? [:]
        // Evict any persisted "recently updated" entries that have aged out while the app
        // was not running — otherwise a relaunch after >14 days would re-badge apps that
        // were updated just before the last quit.
        let now = Date()
        let cutoff = now.addingTimeInterval(-UpdateMetrics.recentlyUpdatedBadgeSeconds)
        recentlyUpdated = savedRecentlyUpdated.filter { $0.value >= cutoff }
    }

    /// Coalesces rapid successive `detectUpdatedApps` calls into one UserDefaults write,
    /// mirroring the debounced-persist pattern in `RecentAppsTracker.recordAppLaunch`.
    func schedulePersist() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            guard !Task.isCancelled else { return }
            self.persist()
        }
    }

    func persist() {
        PreferencesStore.shared.saveKnownBundleMtimes(knownBundleMtimes)
        PreferencesStore.shared.saveRecentlyUpdatedPaths(recentlyUpdated)
    }
}