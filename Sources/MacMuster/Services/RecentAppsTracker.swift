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

    func recordAppLaunch(at path: String) {
        guard isEnabled else { return }
        recentAppLaunchTimes[path] = Date()
        appLaunchCounts[path, default: 0] += 1
        pruneRecentLaunchTimes()
        persistRecentLaunchTimes()
    }

    func pruneRecentLaunchTimes() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        if recentAppLaunchTimes.count > 500 {
            recentAppLaunchTimes = recentAppLaunchTimes.filter { $0.value > cutoff }
        }
        // Keep launch counts bounded in lockstep — drop counts for paths no longer tracked.
        if appLaunchCounts.count > 500 {
            appLaunchCounts = appLaunchCounts.filter { recentAppLaunchTimes[$0.key] != nil }
        }
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
