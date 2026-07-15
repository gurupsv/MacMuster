import AppKit

@MainActor
class ApplicationService {
    static let shared = ApplicationService()

    private init() {}

    /// Cache of resolved (symlink-free) bundle URLs keyed by the raw bundle-URL path, so we don't
    /// call `resolvingSymlinksInPath()` (a syscall) once per running app on every launch. The
    /// cache is busted whenever the running-app count changes between calls — a cheap, stable
    /// signal that the running-app set has turned over — since a running app's bundle URL is
    /// stable for its lifetime, resolved URLs stay valid within a stable set.
    private var resolvedBundleURLCache: [String: URL] = [:]
    private var cachedRunningAppCount: Int = -1

    @discardableResult
    func launchApplication(at path: String, appModel: AppModel? = nil) -> Bool {
        // Validate path exists and is a directory (safety check for stale folder data)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }

        let url = URL(fileURLWithPath: path)
        let resolvedURL = url.resolvingSymlinksInPath()

        // Bust the resolved-URL cache when the running-app set has turned over.
        let running = NSWorkspace.shared.runningApplications
        if running.count != cachedRunningAppCount {
            resolvedBundleURLCache.removeAll()
            cachedRunningAppCount = running.count
        }

        // Match on bundle URL (path identity), not just bundle ID, so a rogue process
        // that claims the same bundle identifier doesn't intercept activation.
        if let match = running.first(where: {
            guard let burl = $0.bundleURL else { return false }
            let key = burl.path
            if let cached = resolvedBundleURLCache[key] {
                return cached == resolvedURL
            }
            let resolved = burl.resolvingSymlinksInPath()
            resolvedBundleURLCache[key] = resolved
            return resolved == resolvedURL
        }) {
            if match.isHidden { match.unhide() }
            match.activate(options: [.activateAllWindows])
            appModel?.recordAppLaunch(at: path)
            return true
        }

        let didLaunch = NSWorkspace.shared.open(url)
        if didLaunch { appModel?.recordAppLaunch(at: path) }
        return didLaunch
    }
}
