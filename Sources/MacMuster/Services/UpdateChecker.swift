import AppKit
import Observation

/// Opt-in update check — the app's only network access.
///
/// Off unless the user turns on "Check for updates" in Settings. It makes one anonymous `GET` to
/// the public GitHub Releases API (no cookies, no credentials, no identifiers, nothing about the
/// user's apps) and compares the newest release tag to the running version. Nothing is downloaded
/// or installed: a newer release only produces an alert with a button that opens the release page
/// in the browser.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Restores the release a previous check found, re-validated: persisted values are data, and
    /// the app may have been updated since, which makes the stored release stale.
    private init() {
        if let stored = PreferencesStore.shared.loadAvailableUpdate(),
           let url = URL(string: stored.url), Self.isReleaseURL(url),
           let current = currentVersion, Self.isNewer(latest: stored.version, than: current) {
            availableRelease = Release(version: stored.version, pageURL: url)
        }
        dismissedVersion = PreferencesStore.shared.loadDismissedUpdateVersion()
        lastCheckDate = PreferencesStore.shared.loadLastUpdateCheck()
    }

    struct Release: Equatable, Sendable {
        let version: String
        let pageURL: URL
    }

    enum Outcome: Equatable, Sendable {
        case updateAvailable(Release)
        case upToDate
        case failed
    }

    /// The newest known release when it is newer than the running app. Read by the launcher banner
    /// and the Settings "Updates" section.
    private(set) var availableRelease: Release?
    /// When a check was last attempted (success or not). Mirrors the persisted value so the
    /// Settings "Updates" section re-renders when a check finishes; `PreferencesStore` stays the
    /// source of truth across launches.
    private(set) var lastCheckDate: Date?
    private var dismissedVersion: String?
    @ObservationIgnored private var isChecking = false

    /// What the launcher banner should show: the available release, unless the user is opted out
    /// or already closed the banner for this version.
    func bannerRelease(enabled: Bool) -> Release? {
        guard enabled, let release = availableRelease, release.version != dismissedVersion else { return nil }
        return release
    }

    func dismissBanner() {
        guard let release = availableRelease else { return }
        dismissedVersion = release.version
        PreferencesStore.shared.saveDismissedUpdateVersion(release.version)
    }

    func openReleasePage() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.pageURL)
    }

    // MARK: - Pure helpers (unit-tested)

    /// Parses `tag_name` + `html_url` out of a GitHub "latest release" payload. The page URL must
    /// be an `https` github.com URL under this project's releases path: the payload is data from
    /// the network, and its link is later handed to `NSWorkspace.open`.
    nonisolated static func parseLatestRelease(from data: Data) -> Release? {
        guard data.count <= UpdateMetrics.maxResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let version = normalizedVersion(tag),
              let link = object["html_url"] as? String,
              let url = URL(string: link), isReleaseURL(url)
        else { return nil }
        return Release(version: version, pageURL: url)
    }

    nonisolated static func isReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix(UpdateMetrics.releasePathPrefix)
    }

    /// `"v1.0.13"` → `"1.0.13"`; nil unless every dot-separated component is a plain integer.
    nonisolated static func normalizedVersion(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= UpdateMetrics.maxVersionComponents,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCII) && Int($0) != nil })
        else { return nil }
        return text
    }

    /// True only when both strings are well-formed versions and `latest` is strictly greater.
    /// Missing trailing components count as zero (`1.1` == `1.1.0`).
    nonisolated static func isNewer(latest: String, than current: String) -> Bool {
        guard let latest = normalizedVersion(latest), let current = normalizedVersion(current) else { return false }
        let a = latest.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Whether the automatic launch check is due: enabled, and at least `minInterval` since the last.
    nonisolated static func isCheckDue(enabled: Bool, lastCheck: Date?, now: Date,
                                       minInterval: TimeInterval = UpdateMetrics.automaticCheckInterval) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        // A last-check date in the future (clock change) must not suppress checks indefinitely.
        return now < lastCheck || now.timeIntervalSince(lastCheck) >= minInterval
    }

    // MARK: - Network

    var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func fetchLatest() async -> Release? {
        var request = URLRequest(url: UpdateMetrics.latestReleaseAPI)
        request.timeoutInterval = UpdateMetrics.requestTimeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Ephemeral: no cookies, cache or credential storage.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return await Task.detached(priority: .utility) { Self.parseLatestRelease(from: data) }.value
    }

    func check() async -> Outcome {
        guard !isChecking, let current = currentVersion else { return .failed }
        isChecking = true
        defer { isChecking = false }
        let attempted = Date()
        PreferencesStore.shared.saveLastUpdateCheck(attempted)
        lastCheckDate = attempted
        guard let release = await fetchLatest() else { return .failed }
        guard Self.isNewer(latest: release.version, than: current) else {
            availableRelease = nil
            PreferencesStore.shared.clearAvailableUpdate()
            return .upToDate
        }
        availableRelease = release
        PreferencesStore.shared.saveAvailableUpdate(version: release.version, url: release.pageURL.absoluteString)
        return .updateAvailable(release)
    }

    // MARK: - UI

    /// Launch-time check. Silent: a newer release surfaces as the launcher banner and in Settings,
    /// not as a modal alert interrupting whatever the user launched the app to do.
    func checkAutomaticallyIfDue(enabled: Bool) {
        guard Self.isCheckDue(enabled: enabled, lastCheck: PreferencesStore.shared.loadLastUpdateCheck(), now: Date()) else { return }
        Task { @MainActor in _ = await self.check() }
    }

    /// Menu-driven check: always reports the result.
    func checkManually() {
        Task { @MainActor in
            switch await self.check() {
            case .updateAvailable(let release): self.present(release)
            case .upToDate:
                NSAlert.showInfo(String(localized: "You're up to date"),
                                 String(localized: "MacMuster \(self.currentVersion ?? "") is the latest version."))
            case .failed:
                NSAlert.showError(String(localized: "Update Check Failed"),
                                  String(localized: "Could not reach GitHub. Check your connection and try again."))
            }
        }
    }

    private func present(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = String(localized: "MacMuster \(release.version) is available")
        alert.informativeText = String(localized: "You're running \(currentVersion ?? ""). Open the release page to download the update.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "View Release"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
            // Acted on; the banner would only repeat it. "Later" keeps the banner as a reminder.
            dismissBanner()
        }
    }
}
