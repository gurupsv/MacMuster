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
    let isHidden: Bool
    
    var lowercaseName: String { name.lowercased() }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Application, rhs: Application) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - AppMetadata

struct AppMetadata {
    let modificationDate: Date?
    let size: Int?
    let bundleIdentifier: String?
}

// MARK: - AppScanResult

struct AppScanResult {
    let metadata: [String: AppMetadata]
    let apps: [Application]
}

// MARK: - AppCategory

enum AppCategory: String, CaseIterable {
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
