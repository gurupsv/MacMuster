import Foundation
import Observation

/// Manages keyboard navigation, search state, and category selection.
@MainActor
@Observable
class NavigationSelection {
    var selectedAppIndex: Int = -1
    var scrollTargetIndex: Int?
    var scrollTargetAnchor: ScrollAnchor?
    var searchTerm: String = "" {
        didSet {
            guard searchTerm != oldValue else { return }
            searchDebounceTask?.cancel()
            if searchTerm.isEmpty {
                library?.dataVersion += 1
            } else {
                searchDebounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: AppMetrics.searchDebounceNanoseconds)
                    guard !Task.isCancelled, let self, let library else { return }
                    library.dataVersion += 1
                }
            }
        }
    }
    private var searchDebounceTask: Task<Void, Never>?
    var selectedCategory: AppCategory = .all {
        didSet { library?.dataVersion += 1; selectedAppIndex = -1 }
    }
    var categoryCounts: [AppCategory: Int] = [:]

    weak var library: LibraryScanState?
    weak var settings: SettingsAppearance?

    init() {
        categoryCounts = [:]
    }

    func selectAppUp() {
        guard let library else { return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 { selectedAppIndex = 0 }
        else if selectedAppIndex < (settings?.columnCount ?? 4) {
            let cc = settings?.columnCount ?? 4
            let rows = (apps.count + cc - 1) / cc
            selectedAppIndex = selectedAppIndex + (rows - 1) * cc
            if selectedAppIndex >= apps.count { selectedAppIndex = apps.count - 1 }
            scrollTargetAnchor = .bottom
        } else {
            selectedAppIndex -= (settings?.columnCount ?? 4)
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    func selectAppDown() {
        guard let library else { return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 { selectedAppIndex = 0 }
        else if selectedAppIndex >= apps.count - (settings?.columnCount ?? 4) {
            selectedAppIndex = selectedAppIndex % (settings?.columnCount ?? 4)
            if selectedAppIndex >= apps.count { selectedAppIndex = apps.count - 1 }
            scrollTargetAnchor = .top
        } else {
            selectedAppIndex += (settings?.columnCount ?? 4)
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    func selectAppLeft() {
        guard let library else { return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 { selectedAppIndex = 0 }
        else if selectedAppIndex % (settings?.columnCount ?? 4) == 0 {
            selectedAppIndex -= 1
            if selectedAppIndex < 0 {
                let cc = settings?.columnCount ?? 4
                let lastRowStart = ((apps.count - 1) / cc) * cc
                selectedAppIndex = min(lastRowStart + cc - 1, apps.count - 1)
                scrollTargetAnchor = .bottom
            } else {
                scrollTargetAnchor = .center
            }
        } else {
            selectedAppIndex -= 1
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    func selectAppRight() {
        guard let library else { return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { return }
        if selectedAppIndex < 0 { selectedAppIndex = 0 }
        else if selectedAppIndex % (settings?.columnCount ?? 4) == (settings?.columnCount ?? 4) - 1 {
            selectedAppIndex += 1
            if selectedAppIndex >= apps.count {
            selectedAppIndex = selectedAppIndex % (settings?.columnCount ?? 4)
                if selectedAppIndex >= apps.count { selectedAppIndex = 0 }
                scrollTargetAnchor = .top
            } else {
                scrollTargetAnchor = .center
            }
        } else {
            selectedAppIndex += 1
            scrollTargetAnchor = .center
        }
        scrollTargetIndex = selectedAppIndex
    }

    func clearScrollTarget() { scrollTargetIndex = nil; scrollTargetAnchor = nil }

    @discardableResult
    func launchSelectedApp() -> Bool {
        guard let library else { return false }
        let displayedApps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard selectedAppIndex >= 0, selectedAppIndex < displayedApps.count else { return false }
        let app = displayedApps[selectedAppIndex]
        if app.isFolder, let folderId = app.folderId {
            library.openFolder(folderId)
            return true
        }
        ApplicationService.shared.launchApplication(at: app.path, appModel: nil)
        return true
    }

    func clearSearchState() { searchTerm = ""; selectedAppIndex = -1 }

    func selectFirstApp() {
        guard let library else { selectedAppIndex = -1; return }
        guard !library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4).isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = 0
    }
    func selectLastApp() {
        guard let library else { selectedAppIndex = -1; return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        selectedAppIndex = apps.count - 1
    }
    func selectNextApp() {
        guard let library else { selectedAppIndex = -1; return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = (selectedAppIndex + 1) % apps.count
    }
    func selectPreviousApp() {
        guard let library else { selectedAppIndex = -1; return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard !apps.isEmpty else { selectedAppIndex = -1; return }
        selectedAppIndex = (selectedAppIndex - 1 + apps.count) % apps.count
    }
    func selectApp(at index: Int) {
        guard let library else { return }
        let apps = library.getDisplayedApps(searchTerm: searchTerm, showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: library.customOrder, sortOption: library.sortOption, selectedCategory: selectedCategory, columnCount: settings?.columnCount ?? 4)
        guard index >= 0, index < apps.count else { return }
        selectedAppIndex = index
    }
}
