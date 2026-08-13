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
        if let cached = cachedDisplayedApps, cached.version == dataVersion { return cached.apps }
        let baseApps = getBaseAppsForCurrentContext()
        let appsWithFolderId = populateFolderIds(for: baseApps)
        let filtered = applySearchFilter(to: appsWithFolderId, searchTerm: searchTerm)
        let result = applyOrdering(to: filtered, searchTerm: searchTerm, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory)
        cachedDisplayedApps = (dataVersion, result)
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
        if let folderId = currentFolderId { return getAllAppsIncludingChildFolders(for: folderId) }

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
        if currentFolderId == nil { return rankedBySearchMatch(visibleApplications, query: lower) }
        return rankedBySearchMatch(apps, query: lower)
    }

    private func rankedBySearchMatch(_ apps: [Application], query: String) -> [Application] {
        apps.compactMap { app -> (Application, Int)? in
            guard let rank = app.searchMatchRank(query) else { return nil }
            return (app, rank)
        }
        .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.lowercaseName < rhs.0.lowercaseName }
        .map(\.0)
    }

    private func applyOrdering(to apps: [Application], searchTerm: String, showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        guard !searchTerm.isEmpty else { return applyNonSearchOrdering(to: apps, showFoldersFirst: showFoldersFirst, customOrder: customOrder, sortOption: sortOption, selectedCategory: selectedCategory) }
        return apps
    }

    private func applyNonSearchOrdering(to apps: [Application], showFoldersFirst: Bool, customOrder: [String: Int], sortOption: ApplicationSorter.SortOption, selectedCategory: AppCategory) -> [Application] {
        var ordered = apps
        var folderFirstApplied = false
        if showFoldersFirst && !ordered.isEmpty {
            let folderApps = ordered.filter { $0.isFolder }
            let nonFolderApps = ordered.filter { !$0.isFolder }
            if !folderApps.isEmpty && !nonFolderApps.isEmpty { ordered = folderApps + nonFolderApps; folderFirstApplied = true }
        }
        if !customOrder.isEmpty {
            return ordered.sorted {
                let a = customOrder[$0.path], b = customOrder[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av < bv }
            }
        }
        if folderFirstApplied { return ordered }
        switch selectedCategory {
        case .system, .utilities, .user:
            ordered = ordered.filter { matchesSelectedCategory($0, selectedCategory: selectedCategory) }
        default: break
        }
        if selectedCategory == .recentlyLaunched {
            return ordered.sorted {
                let a = RecentAppsTracker.shared.recentAppLaunchTimes[$0.path], b = RecentAppsTracker.shared.recentAppLaunchTimes[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av > bv }
            }
        }
        if selectedCategory == .mostUsed {
            return ordered.sorted {
                let a = RecentAppsTracker.shared.appLaunchCounts[$0.path], b = RecentAppsTracker.shared.appLaunchCounts[$1.path]
                switch (a, b) { case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true; case (let av?, let bv?): return av > bv }
            }
        }
        return sortedApplications(ordered)
    }
}
