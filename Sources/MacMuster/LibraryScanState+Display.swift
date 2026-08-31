import Foundation

// MARK: - Display Ordering & Category Management (extracted from LibraryScanState, Issue #7)

extension LibraryScanState {

    // MARK: Category Classification

    func getCategory(for app: Application) -> AppCategory {
        if app.path.hasPrefix("/System") { return .system }
        return .user
    }
    func isMostUsed(_ app: Application) -> Bool { return _mostUsedApps.contains { $0.path == app.path } }
    func isRecentlyLaunched(_ app: Application) -> Bool { return _recentApps.contains { $0.path == app.path } }
    func isNewlyInstalled(_ app: Application) -> Bool { Date().timeIntervalSince(app.installationDate) < ScanMetrics.newlyInstalledWindowSeconds }
    func matchesSelectedCategory(_ app: Application, selectedCategory: AppCategory) -> Bool {
        switch selectedCategory {
        case .all: return true
        case .system, .utilities, .user: return getCategory(for: app) == selectedCategory
        case .mostUsed: return isMostUsed(app)
        case .recentlyLaunched: return isRecentlyLaunched(app)
        case .newlyInstalled: return isNewlyInstalled(app)
        }
    }

    // MARK: Category Counts

    func updateFilteredApps() {
        cachedDisplayedApps = nil

        let displayedApps = getDisplayedApps(searchTerm: navigation?.searchTerm ?? "", showFoldersFirst: settings?.showFoldersFirst ?? false, customOrder: customOrder, sortOption: sortOption, selectedCategory: navigation?.selectedCategory ?? .all, columnCount: settings?.columnCount ?? 4)
        if displayedApps.isEmpty { navigation?.selectedAppIndex = -1 }

        var counts: [AppCategory: Int] = [:]
        let searchFilter = navigation?.searchTerm ?? ""
        let visible = visibleApplications
        let filtered = applySearchFilter(to: visible, searchTerm: searchFilter)
        for app in filtered {
            let cat = getCategory(for: app)
            counts[cat, default: 0] += 1
        }
        counts[.utilities] = 0
        counts[.all] = filtered.count
        let filteredPaths = Set(filtered.map(\.path))
        counts[.mostUsed] = _mostUsedApps.filter { filteredPaths.contains($0.path) }.count
        counts[.recentlyLaunched] = _recentApps.filter { filteredPaths.contains($0.path) }.count
        counts[.newlyInstalled] = filtered.filter { isNewlyInstalled($0) }.count
        navigation?.categoryCounts = counts
    }

    // MARK: Display Ordering

    func getDisplayedApps(searchTerm: String, showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory, columnCount: Int) -> [Application] {
        let query = DisplayQuery(version: dataVersion, searchTerm: searchTerm,
                                 showFoldersFirst: showFoldersFirst, sortOption: sortOption,
                                 selectedCategory: selectedCategory)
        if let cached = cachedDisplayedApps, cached.query == query { return cached.apps }
        let baseApps = getBaseAppsForCurrentContext()
        let appsWithFolderId = populateFolderIds(for: baseApps)
        let searchMatched = applySearchFilter(to: appsWithFolderId, searchTerm: searchTerm)
        let categoryMatched = applyCategoryFilter(to: searchMatched, selectedCategory: selectedCategory)
        let result = applyOrdering(to: categoryMatched, searchTerm: searchTerm, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory)
        cachedDisplayedApps = (query, result)
        return result
    }

    private func populateFolderIds(for apps: [Application]) -> [Application] {
        guard !folders.isEmpty else { return apps }
        let folderPathMap: [String: String] = folders.reduce(into: [String: String]()) { (map, folder) in for path in folder.appPaths { map[path] = folder.id } }
        var result: [Application] = []
        for app in apps {
            if !app.isFolder {
                let id = folderPathMap[app.path] ?? nil
                var a = app; a.folderId = id; result.append(a)
            } else {
                result.append(app)
            }
        }
        return result
    }

    private func getBaseAppsForCurrentContext() -> [Application] {
        if let folderId = currentFolderId { return appsInFolder(for: folderId) }

        let appsInAnyFolder: Set<String> = {
            if let cached = cachedAppsInAnyFolder { return cached }
            let set = folders.reduce(into: Set<String>()) { $0.formUnion($1.appPaths) }
            cachedAppsInAnyFolder = set
            return set
        }()
        let looseApps = visibleApplications.filter { !appsInAnyFolder.contains($0.path) }
        let folderIcons: [Application] = folders.compactMap { folder in
            let showAll = settings?.showHiddenApps ?? false
            let hasVisible = folder.appPaths.contains { path in
                guard !Self.permanentlyHiddenAppPaths.contains(path), appPathIndex[path] != nil else { return false }
                if showAll { return true }
                return !hiddenAppPaths.contains(path)
            }
            return hasVisible ? getFolderApplication(folder) : nil
        }
        return looseApps + folderIcons
    }

    private func applySearchFilter(to apps: [Application], searchTerm: String) -> [Application] {
        guard !searchTerm.isEmpty else { return apps }
        let lower = searchTerm.lowercased()
        guard currentFolderId == nil else { return rankedBySearchMatch(apps, query: lower) }

        // At root level neither list is searchable on its own, which is why this used to substitute
        // one for the other and lose half the answer.
        //
        // `apps` is loose apps plus one entry per folder, so searching it alone never finds an app
        // that lives *inside* a folder — the reason the substitution was there. But
        // `visibleApplications` contains every real app and no folder entries at all, so searching
        // that alone means a folder can never be found by name. Search the union: every app,
        // wherever it lives, plus the folders themselves.
        //
        // No duplicates to worry about — `visibleApplications` holds only real apps and the
        // entries added here are only folders.
        return rankedBySearchMatch(visibleApplications + apps.filter(\.isFolder), query: lower)
    }

    private func rankedBySearchMatch(_ apps: [Application], query: String) -> [Application] {
        apps.compactMap { app -> (Application, Int)? in
            guard let rank = app.searchMatchRank(query) else { return nil }
            return (app, rank)
        }
        .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.lowercaseName < rhs.0.lowercaseName }
        .map(\.0)
    }

    /// Narrows the list to the selected category.
    ///
    /// This is a filtering step in its own right, applied before ordering. It used to live inside
    /// `applyNonSearchOrdering`, below two early returns and a `switch` that only handled three of
    /// the six categories — so "Newly Installed", "Most Used" and "Recently Launched" were never
    /// filtered at all, and *no* category filtered once the user had drag-reordered or turned on
    /// "Show Folders First". Ordering decisions have no business deciding which apps exist.
    private func applyCategoryFilter(to apps: [Application], selectedCategory: AppCategory) -> [Application] {
        guard selectedCategory != .all else { return apps }
        return apps.filter { matchesSelectedCategory($0, selectedCategory: selectedCategory) }
    }

    private func applyOrdering(to apps: [Application], searchTerm: String, showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        guard !searchTerm.isEmpty else { return applyNonSearchOrdering(to: apps, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory) }
        return apps
    }

    private func applyNonSearchOrdering(to apps: [Application], showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        let ordered = apps
        // Category filtering happens in `applyCategoryFilter`, before this function runs.
        // The two launch-history categories order by their own history rather than by the
        // configured sort, so they are handled before the general path below.
        if selectedCategory == .recentlyLaunched {
            return ordered.sorted { lhs, rhs in
                let a = RecentAppsTracker.shared.recentAppLaunchTimes[lhs.path]
                let b = RecentAppsTracker.shared.recentAppLaunchTimes[rhs.path]
                switch (a, b) {
                case let (a?, b?) where a != b: return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                // Same launch instant, or neither launched: still needs a deterministic answer,
                // or an unstable sort can reorder these between renders.
                default: return ApplicationSorter.isOrderedBefore(lhs, rhs, by: sortOption)
                }
            }
        }
        if selectedCategory == .mostUsed {
            return ordered.sorted { lhs, rhs in
                let a = RecentAppsTracker.shared.appLaunchCounts[lhs.path]
                let b = RecentAppsTracker.shared.appLaunchCounts[rhs.path]
                switch (a, b) {
                case let (a?, b?) where a != b: return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                // Equal launch counts are the common case here, so the tiebreak matters more than
                // it does for timestamps — without it the grid reshuffles on every render.
                default: return ApplicationSorter.isOrderedBefore(lhs, rhs, by: sortOption)
                }
            }
        }
        // One call decides folders-first, drag order and the sort option together. Applying them
        // in sequence is what broke both: the folders-first arrangement was computed and then
        // discarded by a whole-list re-sort, and any custom order switched the sort option off.
        return ApplicationSorter.sort(ordered, by: sortOption, customOrder: customOrder, foldersFirst: showFoldersFirst)
    }
}
