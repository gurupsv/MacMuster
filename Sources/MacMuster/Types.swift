import Foundation
import AppKit
import SwiftUI

// MARK: - Application

struct Application: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    var icon: NSImage?
    let installationDate: Date
    let isFolder: Bool
    let containedApps: [String]?
    let appSize: String?
    let bundleDescription: String?
    /// The underlying `AppFolder.id` when this `Application` is a synthetic folder icon
    /// (`isFolder == true`); `nil` for real apps. Lets callers read the folder identity
    /// directly instead of parsing it back out of `path`/`id`.
    var folderId: String? = nil

    var lowercaseName: String { name.lowercased() }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Application, rhs: Application) -> Bool {
        return lhs.id == rhs.id
    }

    /// Matches `query` against this app's name (substring), its path (substring — catches vendor
    /// folder names), or as an in-order subsequence of the name (catches acronyms like "vsc").
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if lowercaseName.contains(query) { return true }
        if path.lowercased().contains(query) { return true }
        return query.isSubsequence(of: lowercaseName)
    }

    /// F-1: whether this app lives under one of the two locations macOS reserves for vetted
    /// installs (`/Applications`, `/System/Applications`). A bundle outside these — including
    /// `~/Applications` or any user-added custom directory — could be named/iconed to impersonate
    /// a real app, so callers use this to show a provenance warning rather than trusting name/icon
    /// alone. Folders are synthetic (no real install location) and are never flagged.
    var isFromTrustedLocation: Bool {
        guard !isFolder else { return true }
        return path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/")
    }

    /// F-1: a specific, human-readable explanation of *where* this app actually lives, for the
    /// provenance badge's tooltip. `nil` when the app is trusted (no badge shown, nothing to
    /// explain). Names the real containing folder rather than a generic "outside Applications"
    /// message, so the warning is actionable instead of just alarming.
    var provenanceWarning: String? {
        guard !isFromTrustedLocation else { return nil }
        let containingFolder = (path as NSString).deletingLastPathComponent
        let homeApplications = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if containingFolder == homeApplications {
            return "Installed in your personal Applications folder (~/Applications), not the system /Applications — verify this app's source."
        }
        return "Installed in \(containingFolder), not /Applications or /System/Applications — verify this app's source."
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

// MARK: - AppMetadata

struct AppMetadata {
    let modificationDate: Date?
    let size: Int?
    let bundleIdentifier: String?
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
}

// MARK: - IconSize

enum IconSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
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
    var parentFolderId: String? = nil
    let createdAt: Date
    var modifiedAt: Date

    init(id: String = UUID().uuidString,
         name: String,
         appPaths: [String],
         customIcon: String? = nil,
         parentFolderId: String? = nil) {
        self.id = id
        self.name = name
        self.appPaths = appPaths
        self.customIcon = customIcon
        self.parentFolderId = parentFolderId
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

// MARK: - OverlayOpacity

let kOverlayOpacityMin: Double = 0.1
let kOverlayOpacityMax: Double = 1.0
let kOverlayOpacityStep: Double = 0.05
