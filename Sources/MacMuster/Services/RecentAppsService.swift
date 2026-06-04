import AppKit
import Foundation

// MARK: - Service for reading macOS "Most Used", "Recently Launched", and "Newly Installed" data

@MainActor
final class RecentAppsService {
    static let shared = RecentAppsService()
    
    /// Cache for most-used apps
    private var cachedMostUsed: [MostUsedEntry] = []
    private var mostUsedCacheDate: Date?
    private let cacheTimeout: TimeInterval = 60
    
    /// Cache for recently launched apps
    private var cachedRecent: [RecentEntry] = []
    private var recentCacheDate: Date?
    
    private init() {}
    
    // MARK: - Data Models
    
    struct MostUsedEntry: Equatable {
        let path: String
        let name: String
        let itemCount: Int
        let lastUsedDate: Date
    }
    
    struct RecentEntry: Equatable {
        let path: String
        let name: String
        let lastUsedDate: Date
    }
    
    // MARK: - Most Used Apps
    
    /// Read Mru.plist from multiple possible locations and return apps sorted by MruItemCount.
    func getMostUsedApps(limit: Int = 64) -> [MostUsedEntry] {
        // Return cached result if still fresh
        if let cacheDate = mostUsedCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheTimeout,
           !cachedMostUsed.isEmpty {
            return cachedMostUsed
        }
        
        // Try multiple possible paths for Mru.plist
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.recentitems/Mru.plist"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.apple.recentitemsagent/Data/Library/Application Support/com.apple.recentitems/Mru.plist"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.apple.dock/Library/Application Support/com.apple.recentitems/Mru.plist"),
        ]
        
        var entries: [MostUsedEntry] = []
        
        for mruPath in possiblePaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: mruPath.path)),
                  let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let mruArray = root["MruArray"] as? [[String: Any]] else {
                continue
            }
            
            for entry in mruArray {
                guard let urlString = entry["LSApplicationURLString"] as? String,
                      let name = entry["LSApplicationName"] as? String,
                      let itemCount = entry["MruItemCount"] as? Int,
                      let lastUsed = entry["LastUsedDate"] as? Date else { continue }
                
                let path = URL(string: urlString)?.path
                    ?? urlString
                    .replacingOccurrences(of: "file://", with: "")
                
                entries.append(MostUsedEntry(path: path, name: name, itemCount: itemCount, lastUsedDate: lastUsed))
            }
            
            // If we found data, break and return
            if !entries.isEmpty { break }
        }
        
        // Sort by item count descending, then by last used date
        entries.sort { lhs, rhs in
            if lhs.itemCount != rhs.itemCount { return lhs.itemCount > rhs.itemCount }
            return lhs.lastUsedDate > rhs.lastUsedDate
        }
        
        cachedMostUsed = Array(entries.prefix(limit))
        mostUsedCacheDate = Date()
        return cachedMostUsed
    }
    
    // MARK: - Recently Launched Apps
    
    /// Read recents data from multiple possible locations and return apps sorted by last used date.
    func getRecentlyLaunchedApps(limit: Int = 64) -> [RecentEntry] {
        // Return cached result if still fresh
        if let cacheDate = recentCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheTimeout,
           !cachedRecent.isEmpty {
            return cachedRecent
        }
        
        // Try multiple possible paths for recents data
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.recentitems.plist"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.apple.recentitemsagent/Data/Library/Preferences/com.apple.recentitems.plist"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.apple.corerecents.recentsd/Data/Library/Preferences/com.apple.corerecents.recentsd.plist"),
        ]
        
        var entries: [RecentEntry] = []
        
        for recentPath in possiblePaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: recentPath.path)),
                  let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }
            
            // Try ApplicationItems first (older format)
            if let appItems = root["ApplicationItems"] as? [[String: Any]] {
                entries = parseRecentItems(appItems)
            }
            
            // Try ApplicationRecents (newer format)
            if entries.isEmpty, let recents = root["ApplicationRecents"] as? [[String: Any]] {
                entries = parseRecentRecents(recents)
            }
            
            // If we found data, break
            if !entries.isEmpty { break }
        }
        
        // Sort by last used date descending
        entries.sort { $0.lastUsedDate > $1.lastUsedDate }
        
        cachedRecent = Array(entries.prefix(limit))
        recentCacheDate = Date()
        return cachedRecent
    }
    
    /// Parse ApplicationItems format from recents plist
    private func parseRecentItems(_ items: [[String: Any]]) -> [RecentEntry] {
        var entries: [RecentEntry] = []
        for item in items {
            guard let urlString = item["LSItemContentURL"] as? String,
                  let name = item["LSItemContentName"] as? String,
                  let lastUsed = item["LastUsedDate"] as? Date else { continue }
            
            let path = URL(string: urlString)?.path
                ?? urlString
                .replacingOccurrences(of: "file://", with: "")
            
            entries.append(RecentEntry(path: path, name: name, lastUsedDate: lastUsed))
        }
        return entries
    }
    
    /// Parse ApplicationRecents format from recents plist
    private func parseRecentRecents(_ recents: [[String: Any]]) -> [RecentEntry] {
        var entries: [RecentEntry] = []
        for recent in recents {
            // Recents may have a "Recents" array inside
            if let recentsArray = recent["Recents"] as? [[String: Any]] {
                for item in recentsArray {
                    guard let urlString = item["LSItemContentURL"] as? String,
                          let name = item["LSItemContentName"] as? String,
                          let lastUsed = item["LastUsedDate"] as? Date else { continue }
                    
                    let path = URL(string: urlString)?.path
                        ?? urlString
                        .replacingOccurrences(of: "file://", with: "")
                    
                    entries.append(RecentEntry(path: path, name: name, lastUsedDate: lastUsed))
                }
            }
        }
        return entries
    }
    
    // MARK: - Newly Installed Apps
    
    /// Return apps sorted by modification date (newly installed/updated first).
    func getNewlyInstalledApps(from apps: [AppModel.Application], limit: Int = 64) -> [AppModel.Application] {
        let sorted = apps.sorted { lhs, rhs in
            lhs.installationDate > rhs.installationDate
        }
        return Array(sorted.prefix(limit))
    }
    
    // MARK: - Refresh Cache
    
    func invalidateCache() {
        cachedMostUsed = []
        mostUsedCacheDate = nil
        cachedRecent = []
        recentCacheDate = nil
    }
    
    // MARK: - Helper: Convert MostUsedEntry to Application
    
    func toApplication(_ entry: MostUsedEntry, iconCache: NSCache<NSString, NSImage>?) -> AppModel.Application {
        let icon: NSImage?
        if let iconCache = iconCache, let cached = iconCache.object(forKey: entry.path as NSString) {
            icon = cached
        } else {
            icon = NSWorkspace.shared.icon(forFile: entry.path)
        }
        
        return AppModel.Application(
            id: entry.path, name: entry.name,
            path: entry.path,
            icon: icon,
            installationDate: entry.lastUsedDate,
            isFolder: false,
            containedApps: nil,
            appSize: nil,
            bundleDescription: nil,
            isHidden: false
        )
    }
    
    // MARK: - Helper: Convert RecentEntry to Application
    
    func toApplication(_ entry: RecentEntry, iconCache: NSCache<NSString, NSImage>?) -> AppModel.Application {
        let icon: NSImage?
        if let iconCache = iconCache, let cached = iconCache.object(forKey: entry.path as NSString) {
            icon = cached
        } else {
            icon = NSWorkspace.shared.icon(forFile: entry.path)
        }
        
        return AppModel.Application(
            id: entry.path, name: entry.name,
            path: entry.path,
            icon: icon,
            installationDate: entry.lastUsedDate,
            isFolder: false,
            containedApps: nil,
            appSize: nil,
            bundleDescription: nil,
            isHidden: false
        )
    }
}
