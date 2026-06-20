import Foundation

/// Handles tracking recent app launches, pruning history, and persistence.
@MainActor
final class RecentAppsTracker {
    static let shared = RecentAppsTracker()
    private let defaults = UserDefaults.standard
    private let maxRecentApps = 8
    
    private enum Keys: String {
        case recentAppLaunchTimes = "recentAppLaunchTimes"
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
    
    func recordAppLaunch(at path: String) {
        guard isEnabled else { return }
        recentAppLaunchTimes[path] = Date()
        pruneRecentLaunchTimes()
        persistRecentLaunchTimes()
    }
    
    func pruneRecentLaunchTimes() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        if recentAppLaunchTimes.count > 500 {
            recentAppLaunchTimes = recentAppLaunchTimes.filter { $0.value > cutoff }
        }
    }
    
    func persistRecentLaunchTimes() {
        guard isEnabled else { return }
        if let data = try? JSONEncoder().encode(recentAppLaunchTimes) {
            defaults.set(data, forKey: Keys.recentAppLaunchTimes.rawValue)
        }
    }
    
    func loadRecentLaunchTimes() {
        guard let data = defaults.data(forKey: Keys.recentAppLaunchTimes.rawValue),
              let times = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        recentAppLaunchTimes = times
        pruneRecentLaunchTimes()
    }
    
    func clearHistory() {
        recentAppLaunchTimes.removeAll()
        persistRecentLaunchTimes()
    }
    
    func getRecentPaths() -> [String] {
        guard isEnabled else { return [] }
        let sortedLaunchTimes = recentAppLaunchTimes.sorted { $0.value > $1.value }
        return sortedLaunchTimes.prefix(maxRecentApps).map { $0.key }
    }
}
