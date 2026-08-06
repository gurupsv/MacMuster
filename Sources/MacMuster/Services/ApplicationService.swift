import AppKit

@MainActor
class ApplicationService {
    static let shared = ApplicationService()

    private init() {}

    /// Launches an application asynchronously via NSWorkspace.openApplication.
    ///
    /// This is the non-blocking variant: the synchronous `NSWorkspace.open(_:)` blocked the
    /// main thread for 283–963 ms depending on app weight. `openApplication` returns in <1 ms
    /// and reports the result on a completion handler, keeping the UI responsive.
    ///
    /// Launch recording happens exactly once, inside the completion handler, so `updateFilteredApps()`
    /// does not run on the click's critical path.
    ///
    /// - Parameters:
    ///   - path: full path to the `.app` bundle
    ///   - appModel: if provided, records the launch in completion handler
    ///   - onComplete: called on the main actor when LaunchServices returns, with `true` if successful
    func launchApplication(at path: String, appModel: AppModel? = nil, onComplete: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: configuration) { runningApp, error in
            Task { @MainActor in
                // Un-minimize if the app was running but hidden (see F-11)
                if let runningApp, runningApp.isHidden {
                    runningApp.unhide()
                }

                let success = error == nil
                if success {
                    appModel?.recordAppLaunch(at: path)
                }
                onComplete(success)
            }
        }
    }
}
