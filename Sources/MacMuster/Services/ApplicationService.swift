import AppKit

@MainActor
class ApplicationService {
    static let shared = ApplicationService()
    
    private init() {}
    
    @discardableResult
    func launchApplication(at path: String, appModel: AppModel? = nil) -> Bool {
        // Validate path exists and is a directory (safety check for stale folder data)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }

        let url = URL(fileURLWithPath: path)
        let resolvedURL = url.resolvingSymlinksInPath()

        // Match on bundle URL (path identity), not just bundle ID, so a rogue process
        // that claims the same bundle identifier doesn't intercept activation.
        let running = NSWorkspace.shared.runningApplications
        if let match = running.first(where: {
            guard let burl = $0.bundleURL else { return false }
            return burl.resolvingSymlinksInPath() == resolvedURL
        }) {
            match.activate(options: [.activateAllWindows])
            appModel?.recordAppLaunch(at: path)
            return true
        }

        let didLaunch = NSWorkspace.shared.open(url)
        if didLaunch { appModel?.recordAppLaunch(at: path) }
        return didLaunch
    }
}
