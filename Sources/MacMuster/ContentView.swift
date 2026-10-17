import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @Bindable var appModel: AppModel
    @FocusState private var isSearchFocused: Bool
    @State private var showCreateFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var selectedAppPathsForFolder: [String] = []

    // Dark mode support — SwiftUI .primary/.secondary handle this automatically; colorScheme removed (Code Review Fix 8: unused)

    // No grid-column cache: it used to be @State written from inside `gridColumns`, which `body`
    // reads — a state mutation during view update, which SwiftUI treats as undefined behaviour and
    // warns about, and which can provoke another update pass. Building the array is a handful of
    // struct allocations; caching it was never worth a correctness hazard.
    // Tracks whether keyboard navigation has been used — controls selection ring visibility
    @State private var hasUsedKeyboard: Bool = false
    // Search bar is hidden until the user clicks the search icon or presses /
    @State private var isSearchExpanded: Bool = false
    @State private var showKeyboardHint = false
    // Hover, press and drop-target state live in `AppGridCell`, one per cell. They used to be
    // `@State` here, so every pointer enter/exit re-evaluated this whole body (and, because the
    // value was read from the `ForEach` content, re-ran the content closure for every
    // materialized cell). Now a hover change touches only the cell it happens in.
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LayoutMetrics.gridSpacing), count: appModel.columnCount)
    }
    
    var body: some View {
        ZStack {
            // The blur background and glow are rendered once by LaunchWrapperView (which
            // hosts this view), so they stay fixed during the launch zoom animation instead
            // of drawing twice. This clear layer only exists to catch taps outside the app
            // grid and dismiss the launcher.
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if appModel.currentFolderId != nil {
                        appModel.closeFolder()
                    } else {
                        StatusBarManager.shared.hideWindow()
                    }
                }

            if appModel.isLoading {
                // D-4: friendlier loading state — an app-like glyph above the spinner instead of
                // a bare spinner, matching the icon language used by the empty state below.
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    ProgressView()
                        .scaleEffect(1.1, anchor: .center)
                    Text("Loading applications…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                let displayedApps = appModel.getDisplayedApps()

                VStack(alignment: .leading, spacing: 10) {
                    // Top padding
                    Spacer()
                        .frame(height: 20)
                        .allowsHitTesting(false)
                    
                    // Keyboard hints pill (shown on first launch, or when Help button is clicked)
                    if appModel.library.hasVisibleApplications && (!appModel.hasShownLauncher || showKeyboardHint) {
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard.fill")
                                Text("↑↓←→ Navigate")
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "return")
                                Text("Launch")
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "slash")
                                Text("Search")
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "escape")
                                Text("Close")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal)
                    }
                    
                    // Breadcrumb or header
                    if let folder = appModel.currentFolder {
                        HStack(spacing: 4) {
                            Button {
                                appModel.closeFolder()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "house.fill")
                                        .font(.caption)
                                    Text("All Apps")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(FocusableButtonStyle())

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.5))
                            
                            Text(folder.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            Spacer()

                            HStack {
                                SearchIconButton(appModel: appModel, isSearchExpanded: $isSearchExpanded, isSearchFocused: $isSearchFocused)

                                ToolbarButtons(
                                    appModel: appModel,
                                    showKeyboardHint: $showKeyboardHint,
                                    newFolderName: $newFolderName,
                                    showCreateFolder: $showCreateFolder,
                                    selectedAppPathsForFolder: $selectedAppPathsForFolder
                                )
                            }
                            // Same hazard as the tab strip: the gaps between these buttons are
                            // launcher background, and clicking it dismisses. Absorb any tap the
                            // buttons themselves did not take so a near-miss costs nothing.
                            .contentShape(Rectangle())
                            .onTapGesture { }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    } else {
                        // Header with category tabs and action buttons
                        HStack {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // Which tabs exist is a model decision (see AppModel.visibleCategories).
                                    // Keyed by category rather than offset so tabs appearing or
                                    // disappearing with "Show Recent Apps" don't reuse each other's state.
                                    ForEach(appModel.visibleCategories, id: \.self) { category in
                                        CategoryTabButton(appModel: appModel, category: category)
                                    }
                                }
                                // The launcher background dismisses the window on click, and the
                                // gaps between these pills are that background. Missing a tab by
                                // a few points would close the launcher outright, so the strip
                                // swallows any tap its buttons did not take. Child buttons still
                                // win for their own area; this only catches the misses.
                                .padding(.vertical, LayoutMetrics.categoryTabStripHitPadding)
                                .contentShape(Rectangle())
                                .onTapGesture { }
                            }
                            
                            Spacer()

                            HStack {
                                SearchIconButton(appModel: appModel, isSearchExpanded: $isSearchExpanded, isSearchFocused: $isSearchFocused)

                                Menu {
                                    ForEach(ApplicationSorter.SortOption.allCases, id: \.self) { option in
                                        Button {
                                            appModel.setSortOption(option)
                                        } label: {
                                            HStack {
                                                Text(option.rawValue)
                                                if appModel.sortOption == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .toolbarIconChrome()
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Sort: \(appModel.sortOption.rawValue)")
                                .accessibilityLabel("Sort applications")

                                ToolbarButtons(
                                    appModel: appModel,
                                    showKeyboardHint: $showKeyboardHint,
                                    newFolderName: $newFolderName,
                                    showCreateFolder: $showCreateFolder,
                                    selectedAppPathsForFolder: $selectedAppPathsForFolder
                                )
                            }
                            // Same hazard as the tab strip: the gaps between these buttons are
                            // launcher background, and clicking it dismisses. Absorb any tap the
                            // buttons themselves did not take so a near-miss costs nothing.
                            .contentShape(Rectangle())
                            .onTapGesture { }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Search bar — shown only when expanded via icon or / key
                    if isSearchExpanded || !appModel.searchTerm.isEmpty {
                        SearchBarView(appModel: appModel, isSearchFocused: $isSearchFocused)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    
                      // Recent Apps Section. At root, the main grid only shows folder icons for
                      // foldered apps — never a foldered app's own path — so a recent app's path
                      // collides with `displayedApps` only when it's a loose, top-level app that's
                      // already sitting in the grid below. Deduping against that at root used to
                      // hide most/all recently-launched apps for anyone who keeps apps loose rather
                      // than foldered. Inside a folder, dedup still applies so a recent app that's a
                      // member of *this* folder doesn't show twice on the same screen.
                      if appModel.showRecentApps {
                          let recentApps = appModel.getRecentApps()
                          let displayedAppPaths = Set(displayedApps.map(\.path))
                          let uniqueRecentApps = recentApps.filter { !displayedAppPaths.contains($0.path) }
                          if !uniqueRecentApps.isEmpty {
                              let recentAppsToShow = Array(uniqueRecentApps.prefix(appModel.columnCount))
                              SectionView(appModel: appModel, title: "Recent", apps: recentAppsToShow, columns: gridColumns) { app in
                                  appModel.launchAndDismiss(app)
                              }
                          }
                      }
                    
                    // App grid
                    if displayedApps.isEmpty {
                        Spacer()
                        // D-4: distinguish "nothing here" (empty folder/category) from "no search
                        // match" with different icon/copy, and offer a way out of a dead-end search.
                        VStack(spacing: 12) {
                            Image(systemName: appModel.searchTerm.isEmpty ? "tray" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(appModel.searchTerm.isEmpty
                                 ? String(localized: "No applications here")
                                 : String(localized: "No results for \"\(appModel.searchTerm)\""))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            if !appModel.searchTerm.isEmpty {
                                Button("Clear Search") {
                                    appModel.searchTerm = ""
                                }
                                .buttonStyle(.plain)
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
LazyVGrid(
columns: gridColumns,
spacing: LayoutMetrics.gridSpacing
) {
                                    // Resolve the selected index to a path once, rather than materializing
                                    // Array(displayedApps.enumerated()) on every body evaluation.
                                    let selectedPath: String? = (hasUsedKeyboard && displayedApps.indices.contains(appModel.selectedAppIndex))
                                        ? displayedApps[appModel.selectedAppIndex].path
                                        : nil
                                    ForEach(displayedApps) { app in
                                        gridItemView(app: app, isSelected: app.path == selectedPath)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if appModel.currentFolder != nil {
                                        appModel.closeFolder()
                                    } else {
                                        StatusBarManager.shared.hideWindow()
                                    }
                                }
                                .padding()
                            }
                             .onChange(of: appModel.scrollTargetIndex) {
                                 if let newIndex = appModel.scrollTargetIndex, newIndex >= 0, newIndex < displayedApps.count {
                                     withAnimation(.easeInOut(duration: 0.2)) {
                                         proxy.scrollTo(displayedApps[newIndex].path, anchor: scrollAnchor)
                                     }
                                     appModel.clearScrollTarget()
                                 }
                             }
                        }
                    }
                    
                    // Bottom padding (moved inside VStack for symmetry)
                    Spacer()
                        .frame(height: 30)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if appModel.currentFolderId != nil {
                        appModel.closeFolder()
                    } else {
                        StatusBarManager.shared.hideWindow()
                    }
                }
                .frame(minWidth: WindowMetrics.windowMinWidth, minHeight: WindowMetrics.windowMinHeight)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            // Escape key: close folder first if inside one, otherwise dismiss the launcher
            if appModel.currentFolderId != nil {
                appModel.closeFolder()
            } else {
                StatusBarManager.shared.hideWindow()
            }
        }
        // Only focus search field when user explicitly types or clicks it
        // By default, keyboard events go to the window for arrow key navigation
        .task {
            await appModel.startLoading()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidShow)) { _ in
            isSearchFocused = false
            hasUsedKeyboard = false
            withAnimation(.easeInOut(duration: 0.2)) { isSearchExpanded = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyboardNavigationDidStart)) { _ in
            hasUsedKeyboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isSearchExpanded = true }
            isSearchFocused = true
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && appModel.searchTerm.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) { isSearchExpanded = false }
            }
        }
        .sheet(isPresented: $showCreateFolder) {
            createFolderSheet
        }
    }
    
    // MARK: - Create Folder Sheet
    private var createFolderSheet: some View {
        VStack(spacing: 16) {
            if appModel.currentFolderId != nil {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text("Cannot create folders inside another folder. Close this folder first.")
                        .font(.subheadline)
                }
            } else {
                Text(selectedAppPathsForFolder.isEmpty ? "Create New Folder" : "Add to Folder")
                    .font(.headline)
            }
            
            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .focused($isSearchFocused, equals: true)
            
            if !appModel.folders.isEmpty && !selectedAppPathsForFolder.isEmpty {
                // Show option to add to existing folders
                VStack(alignment: .leading) {
                    Text("Also add to:")
                        .font(.subheadline)
                    ForEach(appModel.folders, id: \.id) { folder in
                        Button {
                            appModel.addAppToFolder(selectedAppPathsForFolder.first ?? "", folderId: folder.id)
                        } label: {
                            HStack {
                                Text(folder.name)
                                Spacer()
                                Text(String(localized: "\(folder.appPaths.count) apps"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
        .disabled(appModel.currentFolderId != nil)
                        .foregroundStyle(.primary)
                    }
                }
            }
            
            // Show apps that will be added (when creating new folder)
            if !selectedAppPathsForFolder.isEmpty {
                VStack(alignment: .leading) {
                    Text("Apps to add:")
                        .font(.subheadline)
                    ForEach(selectedAppPathsForFolder, id: \.self) { path in
                        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    showCreateFolder = false
                }
                Button(selectedAppPathsForFolder.isEmpty ? "Create Folder" : "Add") {
                    if !selectedAppPathsForFolder.isEmpty {
                        if newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                            _ = appModel.createFolder(name: "Folder", appPaths: selectedAppPathsForFolder)
                        } else {
                            _ = appModel.createFolder(name: newFolderName, appPaths: selectedAppPathsForFolder)
                        }
                    }
                    showCreateFolder = false
                }
        .disabled(appModel.currentFolderId != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    // MARK: - Grid Item View (Fixes compiler timeout)
    @ViewBuilder
    private func gridItemView(app: Application, isSelected: Bool) -> some View {
        AppGridCell(
            appModel: appModel,
            app: app,
            isSelected: isSelected,
            accessibilityText: { accessibilityLabel(for: $0) },
            onTap: { handleAppTap(app) },
            onDrop: { items, location, cellWidth in
                acceptDrop(items, at: location, cellWidth: cellWidth, onto: app)
            },
            selectedAppPathsForFolder: $selectedAppPathsForFolder,
            newFolderName: $newFolderName,
            showCreateFolder: $showCreateFolder
        )
    }

    /// Handles something dropped on `app`'s cell: a reorder next to it, or a merge into a folder.
    /// `cellWidth` turns the drop's x-position into a leading/centre/trailing zone.
    private func acceptDrop(_ items: [String], at location: CGPoint, cellWidth: CGFloat, onto app: Application) -> Bool {

        guard let droppedPath = items.first else { return false }

        guard canReorderByDragging else {
            // Search results and the history tabs (Most Used, Recently Launched) don't have a
            // stable position to record, and a category filter like "System" would otherwise
            // persist positions computed from a partial app list, corrupting the full order
            // the next time "All" is shown. Inside a folder there's nothing sensible to fall
            // back to either — folders can't nest, so the merge sheet below would only offer a
            // disabled confirm button — so the drop is simply declined rather than accepted
            // into a dead end. At the root, the merge-into-folder gesture still works exactly
            // as before.
            guard appModel.currentFolderId == nil else { return false }
            handleDrop(of: droppedPath, onto: app)
            return true
        }

        // Folders are flat — an open folder's contents can never include another folder icon
        // (see FolderStore.appsInFolder) — so there's no merge gesture to reserve a center
        // zone for in here. Every drop reorders, split at the midpoint instead of the root
        // grid's narrower edge thirds, since a wide reorder target is strictly more usable
        // once merging isn't competing for the same gesture.
        if appModel.currentFolderId != nil {
            let fraction = cellWidth > 0 ? location.x / cellWidth : 0.5
            let side: ApplicationSorter.ReorderSide = fraction < 0.5 ? .before : .after
            handleReorderDrop(of: droppedPath, relativeTo: app, side: side)
            return true
        }

        if cellWidth > 0 {
            switch ApplicationSorter.dropZone(forXFraction: location.x / cellWidth) {
            case .leadingEdge:
                handleReorderDrop(of: droppedPath, relativeTo: app, side: .before)
                return true
            case .trailingEdge:
                handleReorderDrop(of: droppedPath, relativeTo: app, side: .after)
                return true
            case .center:
                break
            }
        }

        handleDrop(of: droppedPath, onto: app)
        return true
    }

    /// The spoken description of one grid cell, including any status the badges convey visually.
    ///
    /// The badges themselves stay `accessibilityHidden` — they are decorative overlays, and making
    /// each its own element would have VoiceOver announce three or four things per app. The status
    /// has to be folded in here instead, which is what was missing: each badge set an
    /// `accessibilityLabel` and then immediately applied `accessibilityHidden(true)`, which
    /// discards it. Running and recently-updated state was therefore invisible non-visually, in an
    /// app whose README lists screen-reader support as a feature.
    func accessibilityLabel(for app: Application) -> String {
        if app.isFolder {
            let count = app.containedApps?.count ?? 0
            return String(localized: "\(app.name) folder, \(count) app\(count == 1 ? "" : "s")")
        }

        var description = String(localized: "\(app.name), application")
        // Read from the app's own slot, so only this cell depends on its own status.
        let slot = appModel.library.iconSlot(for: app.path)
        if slot.isRunning {
            description += String(localized: ", running")
        }
        if slot.isRecentlyUpdated {
            description += String(localized: ", recently updated")
        }
        if let warning = app.provenanceWarning {
            description += ". " + warning
        }
        return description
    }

    private func handleAppTap(_ app: Application) {
        if app.isFolder, let folderId = app.folderId {
            if appModel.currentFolderId != folderId {
                appModel.openFolder(folderId)
            }
        } else {
            appModel.launchAndDismiss(app)
        }
    }
    
    private func handleDrop(of droppedPath: String, onto targetApp: Application) {
        // Prevent dropping an item on itself
        if droppedPath == targetApp.path {
            return
        }

        // Merging only makes sense at the root: folders are flat (no nesting), so an app-on-app
        // drop inside an open folder has nothing to merge into. The dropDestination closure above
        // already keeps this path from being reached under normal use — this is a backstop so a
        // future call site can't reopen the dead-end "Create Folder" sheet with its Add button
        // permanently disabled.
        guard appModel.currentFolderId == nil else { return }

        // The dragged payload is just a raw path string, not an Application, so we can't read
        // `.folderId` off it directly — look it up against known folder ids instead (a folder's
        // `path` is exactly its `AppFolder.id`, see FolderStore.getFolderApplication).
        let isDroppedPathAFolder = appModel.folders.contains { $0.id == droppedPath }

        // If dropping on a folder icon, add the dropped app to that folder
        if let targetFolderId = targetApp.folderId {
            // Only add if it's not already in the folder and it's a valid app
            if !isDroppedPathAFolder {
                appModel.addAppToFolder(droppedPath, folderId: targetFolderId)
            }
            return
        }

        // If dragging a folder icon (shouldn't happen in normal usage, but handle it)
        if isDroppedPathAFolder {
            // If dropping folder on app, add app to folder
            appModel.addAppToFolder(targetApp.path, folderId: droppedPath)
            // If dropping folder on folder, do nothing (or could merge folders)
            return
        }

        // If neither is a folder, dropping app on app should create a new folder
        // This matches the requirement: "dropping an application on another should create new Directory"
        if !targetApp.isFolder {
            // Set up to create new folder with both apps
            selectedAppPathsForFolder = [droppedPath, targetApp.path]
            newFolderName = String(localized: "Folder")
            showCreateFolder = true
            return
        }
        
        // Dropping app-on-folder-icon and folder-on-folder is handled above; every other
        // center-zone drop lands here, and the only case left is app-on-app, which merges.
    }

    /// Whether the grid — root or an open folder — is currently showing its natural, un-filtered
    /// order: the only state in which a drag-to-reorder position is meaningful and safe to
    /// persist.
    ///
    /// Search results order by match rank and the history tabs (Most Used, Recently Launched)
    /// order by launch stats — both already ignore `customOrder`, so reordering there would look
    /// like it did nothing. A category filter like "System" is worse than a no-op: `displayedApps`
    /// would only contain that category's apps, and persisting positions computed from that
    /// partial list (see `LibraryScanState.updateCustomOrder`) would corrupt the full order the
    /// next time "All" is shown, not just fail to change it. Category filtering and search both
    /// stay live while a folder is open, so this applies there too.
    private var canReorderByDragging: Bool {
        appModel.searchTerm.isEmpty && appModel.selectedCategory == .all
    }

    /// Moves `droppedPath` to sit next to `targetApp` in the currently displayed order (the root
    /// grid's loose apps + folder icons, or one open folder's contents — `getDisplayedApps`
    /// already resolves which) and persists that as the new custom order.
    ///
    /// The mutation is wrapped in `withAnimation` so the grid visibly slides icons into their new
    /// slots rather than snapping — `updateCustomOrder` only touches `@Observable` state
    /// (`customOrder`, `dataVersion`), and every icon keeps its identity across the reorder
    /// (`AppIconView` is `.id(app.path)`-tagged in `gridItemView`), which is exactly what lets
    /// SwiftUI interpolate each cell's new position instead of a full-grid cross-fade.
    private func handleReorderDrop(of droppedPath: String, relativeTo targetApp: Application, side: ApplicationSorter.ReorderSide) {
        let current = appModel.getDisplayedApps()
        let reordered = ApplicationSorter.reordered(current, moving: droppedPath, toSideOf: targetApp.path, side: side)
        guard reordered.map(\.path) != current.map(\.path) else { return }
        withAnimation(appModel.shouldReduceMotion ? nil : .easeInOut(duration: 0.25)) {
            appModel.updateCustomOrder(from: reordered)
        }
    }

    private var scrollAnchor: UnitPoint? {
        guard let anchor = appModel.scrollTargetAnchor else { return nil }
        switch anchor {
        case .top: return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }

    // MARK: - Context Menu Extraction (Fixes compiler timeout)
    // Extracted to AppContextMenu.swift and FolderContextMenu.swift

    // MARK: - Category Tab Extraction (Fixes compiler timeout)
    // Extracted to CategoryTabView.swift
}

// MARK: - Section View (for Recent Apps)

struct SectionView: View {
    @Bindable var appModel: AppModel
    let title: String
    let apps: [Application]
    let columns: [GridItem]
    let onLaunch: (Application) -> Void
    
    // Track hovered app path for glow effect
    @State private var hoveredAppPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            LazyVGrid(
                columns: columns,
                spacing: 16
            ) {
                ForEach(apps) { app in
                    AppIconView(appModel: appModel, app: app, isHovered: hoveredAppPath == app.path)
                        .accessibilityLabel(app.provenanceWarning.map { String(localized: "\(app.name), application. \($0)") } ?? String(localized: "\(app.name), application"))
                        .accessibilityAddTraits(.isButton)
                        .help(app.provenanceWarning.map { String(localized: "\(app.name) — \($0)") } ?? app.name)
                        .onTapGesture {
                            onLaunch(app)
                        }
                        .onHover { isHovered in
                            hoveredAppPath = isHovered ? app.path : nil
                        }
                }
            }
        }
    }
}

// MARK: - Focusable Button Style (G-4)

/// `.buttonStyle(.plain)` suppresses the system focus ring on macOS, so keyboard users tabbing
/// through the toolbar get no indication of which control has focus. This restores a visible ring
/// by reading `\.isFocused` from inside the style's own label, which SwiftUI keeps in sync with the
/// button's actual focus state without needing a `@FocusState` per button.
struct FocusableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        FocusableButtonLabel(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct FocusableButtonLabel: View {
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
    }
}

// MARK: - Visual Effect Background

/// NSVisualEffectView wrapper for a translucent, blurred background (like Launchpad).
/// Switches to solid opaque background when presentationMode is Sheet.
struct VisualEffectBackground: NSViewRepresentable {
    let appModel: AppModel

    /// Which AppKit views the current settings call for. Only a change in *this* needs the view
    /// tree rebuilt; everything else (the tint colour, its strength, the opacity feeding a sheet's
    /// colour) is a property of views that already exist and is updated in place.
    ///
    /// `updateNSView` used to rebuild unconditionally. It runs whenever any setting it reads
    /// changes, so each tick of the tint or opacity slider destroyed and recreated an
    /// `NSVisualEffectView` / `NSGlassEffectView` — a GPU-backed blur — instead of recolouring a
    /// layer.
    struct Structure: Equatable {
        enum Content: Equatable {
            case lowGpuGlass, liquidGlass, classicGlass, sheet
        }
        let content: Content
        /// Glass only: whether a tint layer sits above the material.
        let hasTint: Bool
    }

    final class Coordinator {
        var structure: Structure?
    }

    private static let tintIdentifier = NSUserInterfaceItemIdentifier("MacMuster.tint")

    /// The tint, as a real view stacked above the material. It used to be a bare `CALayer` added to
    /// the container's layer, and a hand-added sublayer is not reliably composited above the layers
    /// of the subviews AppKit manages — at full strength the tint drew nothing at all. A view's
    /// position in `subviews` is its stacking order. Clicks pass through it.
    private final class TintView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        apply(to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView, coordinator: context.coordinator)
    }

    private var structure: Structure {
        switch appModel.presentationMode {
        case .sheet:
            return Structure(content: .sheet, hasTint: false)
        case .glass:
            let settings = appModel.settings
            let content: Structure.Content
            if settings.simpleGlass {
                content = .lowGpuGlass
            } else if #available(macOS 26.0, *), settings.effectiveGlassStyle == .liquid {
                content = .liquidGlass
            } else {
                content = .classicGlass
            }
            return Structure(content: content, hasTint: appModel.tintStrength > 0)
        }
    }

    private func apply(to container: NSView, coordinator: Coordinator) {
        let wanted = structure
        if coordinator.structure != wanted {
            rebuild(container, as: wanted)
            coordinator.structure = wanted
        }
        refreshColors(in: container, for: wanted)
    }

    /// Replaces the container's contents with the views `structure` calls for.
    private func rebuild(_ container: NSView, as structure: Structure) {
        container.subviews.forEach { $0.removeFromSuperview() }
        container.layer?.backgroundColor = nil

        switch structure.content {
        case .sheet:
            break // An opaque fill on the container's own layer; `refreshColors` sets the colour.
        case .lowGpuGlass:
            // Low-GPU: an inactive, in-window material is a flat fill that still follows
            // light/dark; the live behind-window blur is what costs GPU every frame.
            let flat = NSVisualEffectView()
            flat.material = .fullScreenUI
            flat.blendingMode = .withinWindow
            flat.state = .inactive
            add(flat, to: container)
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .clear
                glass.cornerRadius = 0
                add(glass, to: container)
            }
        case .classicGlass:
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .fullScreenUI
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            add(visualEffect, to: container)
        }

        if structure.hasTint {
            let tint = TintView()
            tint.identifier = Self.tintIdentifier
            tint.wantsLayer = true
            add(tint, to: container) // Added last: above the material.
        }
    }

    private func add(_ material: NSView, to container: NSView) {
        material.frame = container.bounds
        material.autoresizingMask = [.width, .height]
        container.addSubview(material)
    }

    /// Sets the colours that vary without changing which views exist.
    private func refreshColors(in container: NSView, for structure: Structure) {
        let color = appModel.settings.tintedBackgroundColor().cgColor
        if structure.content == .sheet {
            container.layer?.backgroundColor = color
        } else if structure.hasTint {
            container.subviews.first { $0.identifier == Self.tintIdentifier }?.layer?.backgroundColor = color
        }
    }
}

// MARK: - App Icon View

struct AppIconView: View {
    @Bindable var appModel: AppModel
    let app: Application
    var isHovered: Bool = false
    var isSelected: Bool = false
    var isPressed: Bool = false
    var feedbackEnabled: Bool = true
    
    // Dark mode support
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        baseView
            .padding(LayoutMetrics.sectionViewPadding)
            .background(
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height)
                    RoundedRectangle(cornerRadius: LayoutMetrics.appIconCornerRadius)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
                        .frame(width: side, height: side)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            )
            .overlay(
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height)
                    RoundedRectangle(cornerRadius: LayoutMetrics.appIconCornerRadius)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                        .frame(width: side, height: side)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            )
            // Non-color selection cue (G-2): a checkmark badge so selection is legible without
            // relying on the accent-color tint/border alone (helps colorblind/low-contrast users).
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            // Phase 1: "recently updated" badge — fires when an app's bundle mtime jumped since
            // the previous scan (the moment an App Store/direct-download update completes). mtime
            // is the only public signal that an update landed; download-progress % is not reachable
            // via any public macOS API, so this badge is the buildable interpretation of "patching".
            // `monochrome` + a single accent color matches the provenance badge's rendering mode.
            .overlay(alignment: .topLeading) {
                if appModel.library.iconSlot(for: app.path).isRecentlyUpdated {
                    // A white copy of the glyph rendered slightly larger behind the accent-color
                    // one fakes an outline/stroke — SF Symbols have no native border modifier —
                    // matching the running dot's white ring for legibility on colored app icons.
                    ZStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: recentlyUpdatedBadgeSymbolSize + 2, weight: .heavy))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color.white)
                        Image(systemName: "sparkles")
                            .font(.system(size: recentlyUpdatedBadgeSymbolSize))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(4)
                    // Decorative: this state is spoken via accessibilityLabel(for:).
                    .accessibilityHidden(true)
                }
            }
            .scaleEffect(isSelected || (isPressed && feedbackEnabled) ? LayoutMetrics.appIconHoverScale : 1.0)
            .contentShape(Rectangle())
    }
    
    // Extracted to resolve compiler type-checking timeouts
    private var baseView: some View {
        VStack(alignment: .center, spacing: 8) {
            iconView
            appNameView
        }
    }
    
    // `LazyVGrid`'s `ForEach` does not reliably re-invoke this cell's content closure once it has
    // materialized a row for a given identity — a value change elsewhere in the array (an icon
    // finishing its async decode) does not by itself cause an already-on-screen cell to redraw;
    // only a fresh scroll-in or a wholesale identity-set change (e.g. opening/closing a folder,
    // which swaps the whole displayed set) does. `app.icon` alone therefore is not enough.
    //
    // Reading the icon from `appModel.library.iconSlot(for:)` instead of trusting the `app`
    // value snapshot handed down through the grid establishes a direct Observation dependency on
    // *this path's* icon: when it changes, this cell alone is invalidated and re-rendered,
    // independent of whatever the lazy grid's diffing decided. (It used to read `appPathIndex`,
    // which fixed the staleness but made every cell depend on the whole index, so each icon
    // batch re-rendered the entire grid.) Falls back to `app.icon` while the slot is empty —
    // e.g. a folder tile before its composite is first regenerated.
    //
    // Internal rather than `private` so `AppIconViewTests` can call it directly — this property
    // *is* the fix, and unlike the SwiftUI redraw it corrects for, its output is plain,
    // synchronously testable data.
    var currentIcon: NSImage? {
        appModel.library.iconSlot(for: app.path).icon ?? app.icon
    }

    private var iconView: some View {
        ZStack {
            if let icon = currentIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconContentSize, height: iconContentSize)
                    .frame(width: iconSize, height: iconSize)
                    .background(folderTileBackdrop)
                    .padding(LayoutMetrics.appIconPadding)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                    .background(folderTileBackdrop)
                    .padding(LayoutMetrics.appIconPadding)
            }

            // D-3: live badge count on folder icons, so the contained-app count is visible at a
            // glance instead of only on hover (see hoverInfoView).
            if app.isFolder, let count = app.containedApps?.count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: iconSize / 2.6, y: -iconSize / 2.6)
                    .accessibilityHidden(true)
            }
        }
        // Phase 2: "running" indicator — a dot, not a full badge, so it reads as ambient
        // status rather than an alert. Anchored to the icon itself (not the whole tile, which
        // also includes the app name label below) so it sits on the icon's bottom-left corner,
        // clear of the provenance triangle (`bottomTrailing`) and the checkmark (`topTrailing`).
        // Green is the conventional "running/online" color; on a colored app icon it stays
        // legible at small sizes without a ring.
        .overlay(alignment: .bottomLeading) {
            if appModel.library.iconSlot(for: app.path).isRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: runningDotSize, height: runningDotSize)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .padding(4)
                    // Decorative: this state is spoken via accessibilityLabel(for:).
                    .accessibilityHidden(true)
            }
        }
        // F-1: provenance badge — a bundle outside the OS-vetted install locations can be
        // named/iconed to impersonate a real app (e.g. a fake "Safari.app" in ~/Applications),
        // so flag anything not under /Applications or /System/Applications. Anchored to the
        // icon for the same reason as the running dot above.
        .overlay(alignment: .bottomTrailing) {
            if !app.isFromTrustedLocation {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            }
        }
    }

    private var appNameView: some View {
        Text(app.name)
            .font(getFontForAppName())
            .fontWeight(getFontWeight())
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(width: iconSize + 2 * LayoutMetrics.appIconPadding)
            .foregroundStyle(.primary)
    }

    private func getFontForAppName() -> Font {
        let weight = appModel.fontWeight == "bold" ? Font.Weight.bold : appModel.fontWeight == "light" ? Font.Weight.light : Font.Weight.regular
        if appModel.fontFamily == "SF Pro Rounded" {
            return .system(size: appModel.fontSize, weight: weight, design: .rounded)
        } else if appModel.fontFamily == "SF Pro" || appModel.fontFamily.starts(with: "SF Pro") {
            return .system(size: appModel.fontSize, weight: weight, design: .default)
        } else {
            return .custom(appModel.fontFamily, size: appModel.fontSize)
        }
    }

    private func getFontWeight() -> Font.Weight {
        appModel.fontWeight == "bold" ? .bold : appModel.fontWeight == "light" ? .light : .regular
    }
    
    // Safely resolve icon size without relying on a missing `.value` property
    private var iconSize: CGFloat {
        switch appModel.iconSize {
        case .small: return IconMetrics.iconSizeSmall
        case .medium: return IconMetrics.iconSizeMedium
        case .large: return IconMetrics.iconSizeLarge
        case .extraLarge: return IconMetrics.iconSizeExtraLarge
        }
    }

    // Scaled with iconSize (via UpdateMetrics' ratios) so the badges stay proportionate across
    // the Small/Medium/Large/Extra Large icon size setting instead of a fixed point size that
    // reads as tiny on large icons or oversized on small ones.
    private var recentlyUpdatedBadgeSymbolSize: CGFloat {
        iconSize * UpdateMetrics.recentlyUpdatedBadgeSymbolSizeRatio
    }

    private var runningDotSize: CGFloat {
        iconSize * UpdateMetrics.runningDotSizeRatio
    }

    // Folders inset their composited mini-grid so it sits inside the backdrop;
    // regular apps fill the full icon frame.
    private var iconContentSize: CGFloat {
        app.isFolder ? iconSize * (1 - 2 * LayoutMetrics.folderTileInsetRatio) : iconSize
    }

    // Launchpad-style containment for folder tiles: translucent rounded fill + faint
    // stroke. A flat Color (not a Material) keeps LazyVGrid scrolling cheap — a
    // backdrop-blur layer per tile would be paid across every visible tile.
    @ViewBuilder
    private var folderTileBackdrop: some View {
        if app.isFolder {
            let radius = iconSize * LayoutMetrics.folderTileCornerRadiusRatio
            RoundedRectangle(cornerRadius: radius)
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12),
                                lineWidth: LayoutMetrics.folderTileStrokeWidth)
                )
        }
    }

}

// MARK: - Press Tracking via NSViewRepresentable

/// AppKit NSView that intercepts mouseDown/mouseUp to track press state
/// while forwarding the event to SwiftUI's gesture system via super.
private class PressTrackingView: NSView {
    var onPress: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPress?(true)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        onPress?(false)
        super.mouseUp(with: event)
    }
}

/// SwiftUI bridge for PressTrackingView.
/// Place as an overlay on a view to track its pressed state
/// without breaking .draggable or .onTapGesture.
private struct PressTracker: NSViewRepresentable {
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> PressTrackingView {
        let view = PressTrackingView()
        view.onPress = { pressed in
            context.coordinator.setPressed(pressed)
        }
        return view
    }

    func updateNSView(_ nsView: PressTrackingView, context: Context) {
        nsView.onPress = { pressed in
            context.coordinator.setPressed(pressed)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPressed: $isPressed)
    }

    class Coordinator: NSObject {
        @Binding var isPressed: Bool

        init(isPressed: Binding<Bool>) {
            _isPressed = isPressed
        }

        func setPressed(_ pressed: Bool) {
            isPressed = pressed
        }
    }
}

/// One cell of the app grid, owning its own hover / press / drop-target state.
///
/// That state used to be `@State` on `ContentView`, shared by every cell: each pointer enter or exit
/// re-evaluated `ContentView.body` and the `ForEach` content for all materialized cells. Held here,
/// a hover change re-evaluates only this cell. Everything that needs `ContentView` — the tap action,
/// the drop handling, the sheet bindings — comes in as a closure or binding.
private struct AppGridCell: View {
    let appModel: AppModel
    let app: Application
    let isSelected: Bool
    let accessibilityText: (Application) -> String
    let onTap: () -> Void
    /// Called with the dropped items, the drop location, and this cell's width.
    let onDrop: ([String], CGPoint, CGFloat) -> Bool
    @Binding var selectedAppPathsForFolder: [String]
    @Binding var newFolderName: String
    @Binding var showCreateFolder: Bool

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isDropTarget = false
    // Grid cells are uniform width (columns are `.flexible()` and split the row evenly), so this
    // cell's own width is what turns a drop's x-position into a leading/center/trailing zone. Used
    // only at drop time; a stale value from before a window resize just means a drop this instant
    // is misclassified by a few points, never wrong app or lost data.
    @State private var cellWidth: CGFloat = 0

    var body: some View {
        let isLaunching = appModel.launchingAppPath == app.path

        AppIconView(
            appModel: appModel,
            app: app,
            isHovered: isHovered || isDropTarget,
            isSelected: isSelected,
            isPressed: (isDropTarget || isPressed) && appModel.pressFeedbackEnabled,
            feedbackEnabled: appModel.pressFeedbackEnabled
        )
        .id(app.path)
        .accessibilityLabel(accessibilityText(app))
        .accessibilityAddTraits(.isButton)
        .scaleEffect(isLaunching ? 0.95 : 1.0)
        .opacity(isLaunching ? 0.7 : 1.0)
        .animation(appModel.shouldReduceMotion ? .none : .easeInOut(duration: 0.2), value: isLaunching)
        .overlay(
            PressTracker(isPressed: $isPressed)
        )
        .onTapGesture {
            onTap()
        }
        .contextMenu { AppContextMenu(appModel: appModel, app: app, selectedAppPathsForFolder: $selectedAppPathsForFolder, newFolderName: $newFolderName, showCreateFolder: $showCreateFolder) }
        // Reports this cell's width so a later drop's x-position can be read as a fraction of the
        // cell rather than raw points — `.background` keeps it out of layout and off the icon's
        // own hit-testing, and it sits before `.draggable`/`.dropDestination` below so it measures
        // the exact frame `location` in that drop closure is relative to.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cellWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in cellWidth = newWidth }
            }
        )
        .draggable(app.path)
        .dropDestination(for: String.self) { items, location in
            onDrop(items, location, cellWidth)
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
        }
        // .onHover must come after .draggable/.dropDestination — on macOS, a drag-enabled view's
        // mouse-tracking setup otherwise suppresses the plain (non-drag) hover callback, which is
        // why regular grid icons weren't highlighting on hover while the (non-draggable) Recent
        // strip icons, using the same AppIconView, highlighted correctly.
        .onHover { hovering in
            isHovered = hovering
        }
        // Same reasoning applies to .help(): a tooltip set inside AppIconView would be nested
        // inside .draggable/.dropDestination above and wouldn't reliably show. Applied here,
        // outside drag support, instead — carries the name plus the F-1 provenance warning, if any.
        .help(app.provenanceWarning.map { "\(app.name) — \($0)" } ?? app.name)
    }
}

struct ToolbarButtons: View {
    @Bindable var appModel: AppModel
    @Binding var showKeyboardHint: Bool
    @Binding var newFolderName: String
    @Binding var showCreateFolder: Bool
    @Binding var selectedAppPathsForFolder: [String]
    
    var body: some View {
        Button(action: {
            if appModel.shouldReduceMotion {
                showKeyboardHint.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { showKeyboardHint.toggle() }
            }
        }) {
            Image(systemName: "questionmark.circle")
                .toolbarIconChrome()
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: LayoutMetrics.settingsButtonSize / 2))
        .help("Keyboard shortcuts")
        .accessibilityLabel("Show keyboard shortcuts")

        Button {
            newFolderName = String(localized: "Folder")
            selectedAppPathsForFolder = []
            showCreateFolder = true
        } label: {
            Image(systemName: "folder.badge.plus")
                .toolbarIconChrome()
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: LayoutMetrics.settingsButtonSize / 2))
        .accessibilityLabel("Create new folder")
        .disabled(appModel.currentFolderId != nil)

        Button(action: {
            SettingsWindowManager.shared.show()
        }) {
            Image(systemName: "gearshape")
                .toolbarIconChrome()
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: LayoutMetrics.settingsButtonSize / 2))
        .accessibilityLabel("Open settings")
    }
}