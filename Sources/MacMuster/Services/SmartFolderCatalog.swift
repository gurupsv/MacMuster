import Foundation

/// The nine smart folders the Smart Folders Wizard can create, keyed by a **stable** raw value
/// that survives renames and locales. That raw value is what gets stamped onto a folder as its
/// `smartCategoryKey` (see the feature plan), so a folder keeps matching across wizard reruns even
/// if the user renames it or the display name is localized differently.
///
/// The raw values are deliberately not the user-facing names: they are lowercase, hyphenated
/// identifiers chosen to be stable and readable in a persisted JSON value. The human-readable name
/// is `displayName`, which is localized through `Localizable.xcstrings`.
enum SmartFolderCategory: String, CaseIterable, Sendable {
    case productivity = "productivity"
    case development = "development"
    case designCreativity = "design-creativity"
    case internetCommunication = "internet-communication"
    case mediaEntertainment = "media-entertainment"
    case tools = "tools"
    case games = "games"
    case finance = "finance"
    case educationReference = "education-reference"

    /// Localized folder name shown in the wizard and used as the new folder's `name`.
    var displayName: String {
        switch self {
        case .productivity: String(localized: "Productivity")
        case .development: String(localized: "Development")
        case .designCreativity: String(localized: "Design & Creativity")
        case .internetCommunication: String(localized: "Internet & Communication")
        case .mediaEntertainment: String(localized: "Media & Entertainment")
        case .tools: String(localized: "Tools")
        case .games: String(localized: "Games")
        case .finance: String(localized: "Finance")
        case .educationReference: String(localized: "Education & Reference")
        }
    }
}

// MARK: - Override catalog

/// Offline app → category knowledge. Everything the wizard needs to classify an app lives here so
/// that no app metadata ever has to leave the Mac. This is hand-maintained (there is no generator
/// script): a new entry is a one-line addition. The data is intentionally an **overrides +
/// gap-fillers** catalog rather than a master list of every Mac app — the `LSApplicationCategoryType`
/// tier below already classifies the large majority, and these tables only cover what that hint
/// gets wrong or leaves blank.
///
/// Matching happens in four tiers (first hit wins); the tiers are ordered by how trustworthy the
/// signal is, most-first. The matching itself lives in `SmartFolderAssigner`; this file is only the
/// data plus its lookup tables.
extension SmartFolderCategory {

    /// Tier 1 — bundle-identifier → category. The strongest signal, and the one that matters most
    /// in practice: several major apps declare the *wrong* `LSApplicationCategoryType`, so the
    /// category tier alone would misfile them. The clearest example is `com.apple.Safari`,
    /// `com.apple.mail` and `org.mozilla.firefox`, which all ship with
    /// `public.app-category.productivity` — without these overrides a browser would land in
    /// Productivity.
    ///
    /// Keys are exact bundle identifiers in their natural case (`com.apple.Safari`); matching is
    /// case-insensitive because the assigner lowercases both sides. The Swift compiler warns on a
    /// duplicate literal key, and `SmartFolderCatalogTests` guards the rest.
    static let byBundleID: [String: SmartFolderCategory] = [
        // Internet & Communication
        "com.apple.Safari": .internetCommunication,
        "com.google.Chrome": .internetCommunication,
        "com.google.Chrome.Canary": .internetCommunication,
        "com.brave.Browser": .internetCommunication,
        "com.operasoftware.Opera": .internetCommunication,
        "com.vivaldi.Vivaldi": .internetCommunication,
        "com.microsoft.edgemac": .internetCommunication,
        "org.mozilla.firefox": .internetCommunication,
        "org.torproject.torbrowser": .internetCommunication,
        "com.apple.mail": .internetCommunication,
        "org.mozilla.thunderbird": .internetCommunication,
        "com.microsoft.Outlook": .internetCommunication,
        "com.tinyspeck.slackmacgap": .internetCommunication,
        "com.microsoft.teams2": .internetCommunication,
        "us.zoom.xos": .internetCommunication,

        // Development — a few ship with no usable LSApplicationCategoryType at all.
        "com.sublimetext.4": .development,
        "com.sublimemerge": .development,
        "org.apache.netbeans": .development,
        "epp.package.committers": .development,
        "com.kms.katalon.product.product": .development,
        "dev.zed.Zed": .development,
        "com.docker.docker": .development,

        // Finance — crypto wallets that (incorrectly) declare developer-tools.
        "com.binance.BinanceDesktop": .finance,
        "com.electron.exodus": .finance,
        "zeltechnologies.zelcore": .finance,

        // Media & Entertainment — a couple ship with no category.
        "com.apple.podcasts": .mediaEntertainment,
    ]

    /// Tier 2 — bundle-identifier *prefix* → category, for vendors whose apps all belong to one
    /// category. Only safe when the vendor is unambiguous: `com.jetbrains.` is all developer tools,
    /// but e.g. `com.microsoft.` is not (Office is productivity, Edge is communication, VS Code is
    /// development), so it is deliberately excluded.
    static let vendorPrefixes: [String: SmartFolderCategory] = [
        "com.jetbrains.": .development,
    ]

    /// Tier 3 — `public.app-category.*` UTI → category, read from the bundle's
    /// `LSApplicationCategoryType`. This is the workhorse: it classifies the large majority of apps
    /// with no per-app entry needed. The strings are the *actual* UTI values apps ship (verified on
    /// real bundles): design apps use `public.app-category.graphics-design` (not `graphics`),
    /// finance apps use `public.app-category.finance`, and there is a distinct
    /// `public.app-category.board-games`. UTIs with no sensible home among the nine folders
    /// (travel, weather, shopping, healthcare-fitness, …) are intentionally absent — an unmapped
    /// UTI means "no match", not a guess.
    static let byCategoryUTI: [String: SmartFolderCategory] = [
        // Productivity
        "public.app-category.productivity": .productivity,
        "public.app-category.business": .productivity,
        // Development
        "public.app-category.developer-tools": .development,
        "public.app-category.ai-tools": .development,
        // Design & Creativity
        "public.app-category.graphics-design": .designCreativity,
        "public.app-category.design": .designCreativity,
        "public.app-category.art": .designCreativity,
        "public.app-category.photography": .designCreativity,
        // Internet & Communication
        "public.app-category.social-networking": .internetCommunication,
        // Media & Entertainment
        "public.app-category.entertainment": .mediaEntertainment,
        "public.app-category.music": .mediaEntertainment,
        "public.app-category.video": .mediaEntertainment,
        // Tools
        "public.app-category.utilities": .tools,
        // Games
        "public.app-category.games": .games,
        "public.app-category.board-games": .games,
        // Finance
        "public.app-category.finance": .finance,
        "public.app-category.financial-management": .finance,
        // Education & Reference
        "public.app-category.education": .educationReference,
        "public.app-category.reference": .educationReference,
        "public.app-category.news": .educationReference,
        "public.app-category.books": .educationReference,
        "public.app-category.magazines-newspapers": .educationReference,
    ]

    /// Tier 4 — exact normalized app name → category. The last resort, for apps that expose neither
    /// a bundle identifier we know nor a category UTI. Keys are stored **already normalized**
    /// (lowercase, trimmed) because the matcher compares the app's normalized name against this
    /// table directly; matching is exact, never a prefix or substring, so a short common name like
    /// "mail" only ever matches an app actually named "Mail".
    static let byName: [String: SmartFolderCategory] = [
        // Internet & Communication
        "safari": .internetCommunication,
        "google chrome": .internetCommunication,
        "firefox": .internetCommunication,
        "brave": .internetCommunication,
        "opera": .internetCommunication,
        "vivaldi": .internetCommunication,
        "microsoft edge": .internetCommunication,
        "mail": .internetCommunication,
        "slack": .internetCommunication,
        "zoom.us": .internetCommunication,
        "microsoft teams": .internetCommunication,
        "whatsapp": .internetCommunication,
        "telegram": .internetCommunication,
        "signal": .internetCommunication,
        "discord": .internetCommunication,
        // Development
        "xcode": .development,
        "visual studio code": .development,
        "android studio": .development,
        "sublime text": .development,
        "github desktop": .development,
        "iterm": .development,
        "iterm2": .development,
        "postman": .development,
        "docker": .development,
        // Design & Creativity
        "figma": .designCreativity,
        "sketch": .designCreativity,
        "photoshop": .designCreativity,
        "illustrator": .designCreativity,
        "lightroom": .designCreativity,
        "gimp": .designCreativity,
        "affinity photo": .designCreativity,
        // Media & Entertainment
        "spotify": .mediaEntertainment,
        "vlc": .mediaEntertainment,
        "youtube": .mediaEntertainment,
        "netflix": .mediaEntertainment,
        "itunes": .mediaEntertainment,
        "garageband": .mediaEntertainment,
        // Productivity
        "microsoft word": .productivity,
        "microsoft excel": .productivity,
        "microsoft powerpoint": .productivity,
        "notion": .productivity,
        "obsidian": .productivity,
        "libreoffice": .productivity,
        // Tools
        "appcleaner": .tools,
        "the unarchiver": .tools,
    ]

    /// Restores untrusted folder data to a safe state: a `smartCategoryKey` that is not a known
    /// `SmartFolderCategory` raw value is dropped (set to nil) while the folder itself is kept.
    /// Called from both untrusted-data entry points — `BackupManager.apply` (backup/Launchie
    /// restore) and `PreferencesStore.loadFolders` (UserDefaults load) — so a hand-edited or
    /// tampered key can never reach the live state. Pure and nonisolated, so it is directly testable.
    static func sanitizedFolders(_ folders: [AppFolder]) -> [AppFolder] {
        folders.map { folder in
            guard let key = folder.smartCategoryKey, SmartFolderCategory(rawValue: key) == nil else {
                return folder
            }
            var cleaned = folder
            cleaned.smartCategoryKey = nil
            return cleaned
        }
    }
}
