import Foundation
import AppKit
import SwiftUI

// MARK: - Launch Mode

enum LaunchMode: String, CaseIterable, Identifiable {
    case window = "Window"
    case fullscreen = "Full Screen"
    case maximized = "Maximized"
    var id: String { rawValue }
}

// MARK: - Application

struct Application: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    var icon: NSImage?
    let installationDate: Date
    let isFolder: Bool
    let containedApps: [String]?
    let bundleDescription: String?
    /// The underlying `AppFolder.id` when this `Application` is a synthetic folder icon
    /// (`isFolder == true`); `nil` for real apps. Lets callers read the folder identity
    /// directly instead of parsing it back out of `path`/`id`.
    var folderId: String? = nil

    /// Pre-computed at init so the sort comparator and search ranker don't allocate a fresh
    /// lowercased copy of the name on every comparison (thousands of times per sort/search).
    let lowercaseName: String
    /// Pre-computed lowercased path so `searchMatchRank` doesn't allocate one per app per
    /// keystroke.
    let lowercasePath: String

    /// `path` with every symlink and `..` component resolved, or `path` itself when it cannot be
    /// resolved (it no longer exists, or is a synthetic folder entry). Computed once here rather
    /// than at each use: `isFromTrustedLocation` is read during view rendering, and resolving a
    /// path per cell per frame would be a syscall on the draw path.
    let resolvedPath: String

    init(id: String,
         name: String,
         path: String,
         icon: NSImage? = nil,
         installationDate: Date,
         isFolder: Bool,
         containedApps: [String]? = nil,
         bundleDescription: String? = nil,
         folderId: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.installationDate = installationDate
        self.isFolder = isFolder
        self.containedApps = containedApps
        self.bundleDescription = bundleDescription
        self.folderId = folderId
        self.lowercaseName = name.lowercased()
        self.lowercasePath = path.lowercased()
        // Folder entries carry a UUID in `path`, not a filesystem location, so there is nothing to
        // canonicalize and nothing to distrust.
        self.resolvedPath = isFolder ? path : Application.canonicalize(path)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Application, rhs: Application) -> Bool {
        return lhs.id == rhs.id
    }

    /// Matches `query` against this app's name (substring), its path (substring — catches vendor
    /// folder names), or as an in-order subsequence of the name (catches acronyms like "vsc").
    func matchesSearch(_ query: String) -> Bool {
        searchMatchRank(query) != nil
    }

    /// Ranks how well `query` matches this app — lower is better, `nil` means no match at all.
    /// Used to sort search results by match quality (an exact/prefix hit on the app's *name*
    /// should always outrank a coincidental substring hit somewhere in its install path), rather
    /// than leaving every match equally ranked and falling back to alphabetical/date order.
    func searchMatchRank(_ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if lowercaseName == query { return 0 }
        if lowercaseName.hasPrefix(query) { return 1 }
        if lowercaseName.contains(query) { return 2 }
        if lowercasePath.contains(query) { return 3 }
        if query.isSubsequence(of: lowercaseName) { return 4 }
        return nil
    }

    /// F-1: whether this app lives under one of the two locations macOS reserves for vetted
    /// installs (`/Applications`, `/System/Applications`). A bundle outside these — including
    /// `~/Applications` or any user-added custom directory — could be named/iconed to impersonate
    /// a real app, so callers use this to show a provenance warning rather than trusting name/icon
    /// alone. Folders are synthetic (no real install location) and are never flagged.
    ///
    /// Checked against `resolvedPath`, not `path`. A prefix test on the raw path is trivially
    /// defeated by the two things it most needs to catch: `/Applications/../tmp/Fake.app` has the
    /// trusted prefix as a string, and a symlink at `/Applications/Fake.app` can point anywhere at
    /// all. Both read as trusted, which is precisely the impersonation the badge exists to flag.
    var isFromTrustedLocation: Bool {
        guard !isFolder else { return true }
        return Self.trustedLocationPrefixes.contains { resolvedPath.hasPrefix($0) }
    }

    /// Locations macOS reserves for vetted installs, matched against the fully resolved path.
    ///
    /// The cryptex entry is not optional cleverness: on current macOS, `/Applications/Safari.app`
    /// resolves to `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`, so
    /// resolving paths without accounting for it would flag Safari — the most recognisable system
    /// app there is — as untrusted. That volume is SIP-protected and OS-managed, so it carries the
    /// same vetting as the two classic locations; it is simply where the OS now keeps some of them.
    static let trustedLocationPrefixes = [
        "/Applications/",
        "/System/Applications/",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/",
    ]

    /// F-1: a specific, human-readable explanation of *where* this app actually lives, for the
    /// provenance badge's tooltip. `nil` when the app is trusted (no badge shown, nothing to
    /// explain). Names the real containing folder rather than a generic "outside Applications"
    /// message, so the warning is actionable instead of just alarming.
    var provenanceWarning: String? {
        guard !isFromTrustedLocation else { return nil }
        let containingFolder = (resolvedPath as NSString).deletingLastPathComponent
        let homeApplications = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if containingFolder == homeApplications {
            return String(localized: "Installed in your personal Applications folder (~/Applications), not the system /Applications — verify this app's source.")
        }
        return String(localized: "Installed in \(containingFolder), not /Applications or /System/Applications — verify this app's source.")
    }
}

private extension String {
    /// Whether every character of `self` appears in `other` in order (not necessarily contiguous).
    /// E.g. "vsc".isSubsequence(of: "visual studio code") is true.
    func isSubsequence(of other: String) -> Bool {
        var searchIndex = other.startIndex
        for char in self {
            guard let foundIndex = other[searchIndex...].firstIndex(of: char) else { return false }
            searchIndex = other.index(after: foundIndex)
        }
        return true
    }
}

// MARK: - AppCategory

enum AppCategory: String, CaseIterable {
    case all = "All"
    case mostUsed = "Most Used"
    case recentlyLaunched = "Recently Launched"
    case newlyInstalled = "Newly Installed"
    case system = "System"
    case utilities = "Utilities"
    case user = "User"

    /// Categories that are views onto launch history, and so have nothing to show once the user
    /// turns "Show Recent Apps" off. Both the tab strip and the fallback-selection logic read
    /// this, so there is exactly one definition of what that setting governs.
    static let launchHistoryCategories: Set<AppCategory> = [.mostUsed, .recentlyLaunched]
}

// MARK: - IconSize

enum IconSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
}

// MARK: - ScrollAnchor

enum ScrollAnchor {
    case top
    case center
    case bottom
}

// MARK: - AppFolder

struct AppFolder: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var appPaths: [String]
    var customIcon: String?
    let createdAt: Date
    var modifiedAt: Date

    init(id: String = UUID().uuidString,
          name: String,
          appPaths: [String],
          customIcon: String? = nil) {
        self.id = id
        self.name = name
        self.appPaths = appPaths
        self.customIcon = customIcon
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppFolder, rhs: AppFolder) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Application helpers

extension Application {
    /// Fully resolves `path` for trust decisions.
    ///
    /// Two steps, and both are load-bearing. `standardized` removes `..` components lexically,
    /// which is what catches `/Applications/../tmp/Fake.app` — `realpath` alone cannot, because it
    /// returns nil for a path that does not exist, and falling back to the raw string would hand
    /// back the very prefix the traversal was constructed to fake. `canonicalPath` then follows
    /// symlinks, which is what catches a link sitting at a trusted-looking name.
    static func canonicalize(_ path: String) -> String {
        let lexical = URL(fileURLWithPath: path).standardized.path
        return DirectoryWatcher.canonicalPath(lexical) ?? lexical
    }

    /// Strips trailing `.app` suffix from a path component to derive the display name.
    static func stripAppSuffix(_ item: String) -> String {
        item.hasSuffix(".app") ? String(item.dropLast(4)) : item
    }
}


