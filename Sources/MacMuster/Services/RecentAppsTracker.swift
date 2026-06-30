import Foundation

/// Handles tracking recent app launches, pruning history, and persistence.
@MainActor
final class RecentAppsTracker {
    static let shared = RecentAppsTracker()
    private let defaults = UserDefaults.standard
    private let maxRecentApps = 8
    
    private enum Keys: String {
        case recentAppLaunchTimes = "recentAppLaunchTimes"
        case appLaunchCounts = "appLaunchCounts"
    }

    private init() {}

    /// Whether recent apps tracking is enabled. When disabled, history is cleared and no new launches are recorded.
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                clearHistory()
            }
        }
    }

    var recentAppLaunchTimes: [String: Date] = [:]
    /// Total launch count per app path, used to compute "Most Used".
    var appLaunchCounts: [String: Int] = [:]

    /// Coalesces rapid-succession launches (e.g. opening several apps in a row) into a single
    /// UserDefaults write instead of one synchronous encode+write per launch. The in-memory
    /// state is updated immediately so the UI stays responsive; only the disk flush is deferred.
    private var persistTask: Task<Void, Never>?
    private static let persistDebounceSeconds: UInt64 = 2_000_000_000 // 2s

    func recordAppLaunch(at path: String) {
        guard isEnabled else { return }
        recentAppLaunchTimes[path] = Date()
        appLaunchCounts[path, default: 0] += 1
        pruneRecentLaunchTimes()
        schedulePersistRecentLaunchTimes()
    }

    /// Schedules a single coalesced persist. Cancels any in-flight deferred write so only the
    /// latest state is flushed, and a burst of launches produces one encode+write rather than N.
    private func schedulePersistRecentLaunchTimes() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.persistDebounceSeconds)
            guard !Task.isCancelled, let self else { return }
            self.persistRecentLaunchTimes()
        }
    }

    func pruneRecentLaunchTimes() {
        // F-3: always enforce the retention window (previously only ran once the dict exceeded
        // 500 entries, which in practice almost never happened — so launch history was kept
        // indefinitely for most users, far beyond the 8 entries the UI ever displays).
        let cutoff = Date().addingTimeInterval(-kRecentAppsRetentionSeconds)
        recentAppLaunchTimes = recentAppLaunchTimes.filter { $0.value > cutoff }

        if recentAppLaunchTimes.count > kMaxStoredRecentApps {
            let kept = recentAppLaunchTimes.sorted { $0.value > $1.value }.prefix(kMaxStoredRecentApps)
            recentAppLaunchTimes = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }

        // Keep launch counts bounded in lockstep — drop counts for paths no longer tracked.
        appLaunchCounts = appLaunchCounts.filter { recentAppLaunchTimes[$0.key] != nil }
    }

    func persistRecentLaunchTimes() {
        guard isEnabled else { return }
        if let data = try? JSONEncoder().encode(recentAppLaunchTimes) {
            defaults.set(data, forKey: Keys.recentAppLaunchTimes.rawValue)
        }
        if let countData = try? JSONEncoder().encode(appLaunchCounts) {
            defaults.set(countData, forKey: Keys.appLaunchCounts.rawValue)
        }
    }

    func loadRecentLaunchTimes() {
        guard let data = defaults.data(forKey: Keys.recentAppLaunchTimes.rawValue),
              let times = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        recentAppLaunchTimes = times
        if let countData = defaults.data(forKey: Keys.appLaunchCounts.rawValue),
           let counts = try? JSONDecoder().decode([String: Int].self, from: countData) {
            appLaunchCounts = counts
        }
        pruneRecentLaunchTimes()
    }

    func clearHistory() {
        recentAppLaunchTimes.removeAll()
        appLaunchCounts.removeAll()
        persistRecentLaunchTimes()
    }

    func getRecentPaths() -> [String] {
        guard isEnabled else { return [] }
        let sortedLaunchTimes = recentAppLaunchTimes.sorted { $0.value > $1.value }
        return sortedLaunchTimes.prefix(maxRecentApps).map { $0.key }
    }

    /// Returns app paths ranked by total launch count, most-launched first.
    func getMostUsedPaths(limit: Int) -> [String] {
        guard isEnabled else { return [] }
        let sortedCounts = appLaunchCounts.sorted { $0.value > $1.value }
        return sortedCounts.prefix(limit).map { $0.key }
    }
}
