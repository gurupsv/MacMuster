import AppKit

@MainActor
class ApplicationService {
    static let shared = ApplicationService()
    
    private init() {}
    
    @discardableResult
    func launchApplication(at path: String, appModel: AppModel? = nil) -> Bool {
        let url = URL(fileURLWithPath: path)
        let didLaunch = NSWorkspace.shared.open(url)
        
        // Record the launch for recent apps tracking
        if didLaunch, let appModel = appModel {
            appModel.recordAppLaunch(at: path)
        }
        
        return didLaunch
    }
}
