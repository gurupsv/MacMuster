import AppKit

@MainActor
class ApplicationService {
    static let shared = ApplicationService()
    
    private init() {}
    
    @discardableResult
    func launchApplication(at path: String, appModel: AppModel? = nil) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // Check if the app is already running
        let apps = NSWorkspace.shared.runningApplications
        if let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
           apps.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            // App is already running - bring it to front instead of minimizing
            if let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                app.activate(options: [.activateAllWindows])
                // Record the launch for recent apps tracking
                if let appModel = appModel {
                    appModel.recordAppLaunch(at: path)
                }
                return true
            }
        }
        
        // App is not running or we couldn't determine bundle ID - open normally
        let didLaunch = NSWorkspace.shared.open(url)
        
        // Record the launch for recent apps tracking
        if didLaunch, let appModel = appModel {
            appModel.recordAppLaunch(at: path)
        }
        
        return didLaunch
    }
}
