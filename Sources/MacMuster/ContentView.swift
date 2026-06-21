import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @Bindable var appModel: AppModel
    @State private var hoveredAppPath: String?
    @FocusState private var isSearchFocused: Bool
    @State private var showCreateFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var selectedAppPathsForFolder: [String] = []
    
    // Dark mode support — SwiftUI .primary/.secondary handle this automatically; colorScheme removed (Code Review Fix 8: unused)
    
    // Cache grid columns to avoid allocation on every body render.
    // Invalidates when columnCount changes.
    @State private var gridColumnCache: (count: Int, columns: [GridItem])?
    // Tracks whether keyboard navigation has been used — controls selection ring visibility
    @State private var hasUsedKeyboard: Bool = false
    // Search bar is hidden until the user clicks the search icon or presses /
    @State private var isSearchExpanded: Bool = false
    @State private var isDraggingAppPath: String? = nil
    @State private var pressedAppPath: String? = nil
    
    private var gridColumns: [GridItem] {
        let count = appModel.columnCount
        if gridColumnCache?.count == count {
            return gridColumnCache!.columns
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: kGridSpacing), count: count)
        gridColumnCache = (count, columns)
        return columns
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
                    // Tap on background outside app grid - hide launcher
                    StatusBarManager.shared.hideWindow()
                }

            if appModel.isLoading {
                // Loading indicator
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.2, anchor: .center)
                    Text("Loading applications...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                let visibleApps = appModel.visibleApplications
                let displayedApps = appModel.getDisplayedApps()

                VStack(alignment: .leading, spacing: 10) {
                    // Top padding
                    Spacer()
                        .frame(height: 20)
                    
                    // Keyboard hints pill (above categories, shown only on first launch)
                    if !visibleApps.isEmpty && !appModel.hasShownLauncher {
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
                            .buttonStyle(.plain)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.5))
                            
                            Text(folder.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            Spacer()

                            searchIconButton

                            Button {
                                newFolderName = "Folder"
                                selectedAppPathsForFolder = []
                                showCreateFolder = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Create new folder")

                            Button(action: {
                                SettingsWindowManager.shared.show()
                            }) {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open settings")
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    } else {
                        // Header with category tabs and action buttons
                        HStack {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // .utilities is intentionally excluded — getCategory() folds it into .user,
                                    // so its count is always 0 (see AppModelTests).
                                    let visibleCategories: [AppCategory] = [.all, .system, .user, .mostUsed, .recentlyLaunched, .newlyInstalled]
                                    ForEach(Array(visibleCategories.enumerated()), id: \.offset) { _, category in
                                        categoryTabButton(for: category)
                                    }
                                }
                            }
                            
                            Spacer()

                            searchIconButton

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
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Sort: \(appModel.sortOption.rawValue)")
                            .accessibilityLabel("Sort applications")

                            Button {
                                newFolderName = "Folder"
                                selectedAppPathsForFolder = []
                                showCreateFolder = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Create new folder")

                            Button(action: {
                                SettingsWindowManager.shared.show()
                            }) {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open settings")
                        }
                        .padding(.horizontal)
                    }
                    
                    // Search bar — shown only when expanded via icon or / key
                    if isSearchExpanded || !appModel.searchTerm.isEmpty {
                        searchBar
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    
                      // Recent Apps Section
                      if appModel.showRecentApps {
                          let recentApps = appModel.getRecentApps()
                          if !recentApps.isEmpty {
                              let recentAppsToShow = Array(recentApps.prefix(appModel.columnCount))
                              SectionView(appModel: appModel, title: "Recent", apps: recentAppsToShow, columns: gridColumns) { app in
                                  if ApplicationService.shared.launchApplication(at: app.path, appModel: appModel) {
                                      StatusBarManager.shared.hideWindow()
                                  }
                              }
                          }
                      }
                    
                    // App grid
                    if displayedApps.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: appModel.searchTerm.isEmpty ? "folder" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(appModel.searchTerm.isEmpty
                                 ? "No applications found"
                                 : "No results for \"\(appModel.searchTerm)\"")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
LazyVGrid(
columns: gridColumns,
spacing: kGridSpacing
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
                }
                .frame(minWidth: kWindowMinWidth, minHeight: kWindowMinHeight)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("keyboardNavigationDidStart"))) { _ in
            hasUsedKeyboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusSearchField"))) { _ in
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
            Text(selectedAppPathsForFolder.isEmpty ? "Create New Folder" : "Add to Folder")
                .font(.headline)
            
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
                                Text("\(folder.appPaths.count) apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
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
                            appModel.createFolder(name: "Folder", appPaths: selectedAppPathsForFolder)
                        } else {
                            appModel.createFolder(name: newFolderName, appPaths: selectedAppPathsForFolder)
                        }
                    }
                    showCreateFolder = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    // MARK: - Search Bar Extraction
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)
            
            TextField("Search applications...", text: $appModel.searchTerm)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused, equals: true)
            
            if !appModel.searchTerm.isEmpty {
                Button {
                    appModel.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(kSearchPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: kSearchCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: kSearchCornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 400, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Search Icon Button
    private var searchIconButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isSearchExpanded.toggle() }
            if isSearchExpanded { isSearchFocused = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(isSearchExpanded || !appModel.searchTerm.isEmpty ? Color.primary : Color.secondary)
                .frame(width: kSettingsButtonSize, height: kSettingsButtonSize)
                .background(
                    Circle()
                        .fill(isSearchExpanded || !appModel.searchTerm.isEmpty
                              ? Color.primary.opacity(0.15)
                              : Color.clear)
                )
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Search (/)")
        .accessibilityLabel("Search applications")
    }

    private func getCategoryCount(for category: AppCategory) -> Int {
        appModel.categoryCounts[category, default: 0]
    }
    
    // MARK: - Grid Item View (Fixes compiler timeout)
    @ViewBuilder
    private func gridItemView(app: Application, isSelected: Bool) -> some View {
        let isDropTarget = isDraggingAppPath == app.path
        let isPressed = pressedAppPath == app.path
        AppIconView(
            appModel: appModel,
            app: app,
            isHovered: hoveredAppPath == app.path || isDropTarget,
            hoveredAppInfo: hoveredAppPath == app.path ? app : nil,
            isSelected: isSelected,
            isPressed: (isDropTarget || isPressed) && appModel.pressFeedbackEnabled,
            feedbackEnabled: appModel.pressFeedbackEnabled
        )
        .id(app.path)
        .accessibilityLabel(accessibilityLabel(for: app))
        .accessibilityAddTraits(.isButton)
        .onHover { isHovered in
            hoveredAppPath = isHovered ? app.path : nil
        }
        .overlay(
            PressTracker(pressedAppPath: $pressedAppPath, appPath: app.path)
        )
        .onTapGesture {
            handleAppTap(app)
        }
        .contextMenu { folderContextMenu(app) }
        .draggable(app.path)
        .dropDestination(for: String.self) { items, location in
            if let droppedPath = items.first {
                handleDrop(of: droppedPath, onto: app)
                return true
            }
            return false
        } isTargeted: { isTargeted in
            if isTargeted {
                isDraggingAppPath = app.path
            } else {
                isDraggingAppPath = nil
            }
        }
    }

    private func accessibilityLabel(for app: Application) -> String {
        if app.isFolder {
            let count = app.containedApps?.count ?? 0
            return "\(app.name) folder, \(count) app\(count == 1 ? "" : "s")"
        }
        return "\(app.name), application"
    }

    private func handleAppTap(_ app: Application) {
        if app.path.hasPrefix("folder:") {
            let folderPath = app.path.dropFirst(7) // Remove "folder:"
            let folderId = String(folderPath)
            if appModel.currentFolderId != folderId {
                appModel.openFolder(folderId)
            }
        } else {
            // Record the launch for recent apps
            appModel.recordAppLaunch(at: app.path)
            // Launch the application asynchronously to avoid blocking the UI
            Task {
                let launched = ApplicationService.shared.launchApplication(at: app.path, appModel: nil)
                await MainActor.run {
                    if launched {
                        StatusBarManager.shared.hideWindow()
                    }
                }
            }
        }
    }
    
    private func handleDrop(of droppedPath: String, onto targetApp: Application) {
        // Prevent dropping an item on itself
        if droppedPath == targetApp.path {
            return
        }
        
        // If dropping on a folder icon, add the dropped app to that folder
        if targetApp.path.hasPrefix("folder:") {
            let folderId = String(targetApp.path.dropFirst(7))
            // Only add if it's not already in the folder and it's a valid app
            if !droppedPath.hasPrefix("folder:") {
                appModel.addAppToFolder(droppedPath, folderId: folderId)
            }
            return
        }
        
        // If dragging a folder icon (shouldn't happen in normal usage, but handle it)
        if droppedPath.hasPrefix("folder:") {
            // If dropping folder on app, add app to folder
            if !targetApp.path.hasPrefix("folder:") {
                let folderId = String(droppedPath.dropFirst(7))
                appModel.addAppToFolder(targetApp.path, folderId: folderId)
            }
            // If dropping folder on folder, do nothing (or could merge folders)
            return
        }
        
        // If neither is a folder, dropping app on app should create a new folder
        // This matches the requirement: "dropping an application on another should create new Directory"
        if !targetApp.path.hasPrefix("folder:") && !droppedPath.hasPrefix("folder:") {
            // Set up to create new folder with both apps
            selectedAppPathsForFolder = [droppedPath, targetApp.path]
            newFolderName = "Folder"
            showCreateFolder = true
            return
        }
        
        // Note: True reordering (drop-between) requires more sophisticated drag handling
        // that detects drop position between items. For now, we prioritize folder creation
        // as specified in the requirements. Users can reorder apps through settings
        // or by using the custom order features accessible elsewhere in the UI.
    }
    
    private func updateCustomOrderAfterDrop(droppedPath: String, targetPath: String) {
        // Find indices of dropped and target apps
        guard let droppedIndex = appModel.displayOrder.firstIndex(where: { $0.path == droppedPath }),
              let targetIndex = appModel.displayOrder.firstIndex(where: { $0.path == targetPath }) else {
            return
        }
        
        // Create a new array with the dropped item moved to target position
        var newOrder = appModel.displayOrder
        let droppedItem = newOrder.remove(at: droppedIndex)
        newOrder.insert(droppedItem, at: targetIndex)
        
        // Update customOrder based on new positions
        appModel.updateCustomOrder(from: newOrder)
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
    @ViewBuilder
    private func folderContextMenu(_ app: Application) -> some View {
        if app.path.hasPrefix("folder:") {
            let folderPath = app.path.dropFirst(7)
            let folderId = String(folderPath)
            if let folder = appModel.folders.first(where: { $0.id == folderId }) {
                Menu {
                    ForEach(folder.appPaths, id: \.self) { appPath in
                        Button {
                            appModel.removeAppFromFolder(appPath, folderId: folderId)
                        } label: {
                            Label("Remove \(appPath.components(separatedBy: "/").last ?? appPath)", systemImage: "minus.circle")
                        }
                    }
                } label: {
                    Text("Manage Folder Contents")
                }
                Divider()
                Button {
                    newFolderName = folder.name
                    selectedAppPathsForFolder = []
                    showCreateFolder = true
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    appModel.deleteFolder(folderId: folderId)
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
        } else {
            if !app.isFolder {
                Button {
                    let parentPath = (app.path as NSString).deletingLastPathComponent
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: parentPath)])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            Button {
                selectedAppPathsForFolder = [app.path]
                newFolderName = "Folder"
                showCreateFolder = true
            } label: {
                Label("Add to Folder", systemImage: "folder.badge.plus")
            }
            if !appModel.folders.isEmpty {
                Menu {
                    ForEach(appModel.folders, id: \.id) { folder in
                        Button {
                            appModel.addAppToFolder(app.path, folderId: folder.id)
                        } label: {
                            Text("Add to \(folder.name)")
                        }
                    }
                } label: {
                    Label("Add to Existing Folder", systemImage: "folder")
                }
            }
            Button {
                appModel.toggleHiddenApp(app.path)
            } label: {
                Label(appModel.isAppHidden(app.path) ? "Show App" : "Hide App", systemImage: appModel.isAppHidden(app.path) ? "eye" : "eye.slash")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Category Tab Extraction (Fixes compiler timeout)
    private func categoryTabButton(for category: AppCategory) -> some View {
        let isSelected = appModel.selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appModel.selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(getCategoryCount(for: category))")
                    .font(.caption)
                    .foregroundStyle(isSelected
                                     ? Color(nsColor: .windowBackgroundColor).opacity(0.7)
                                     : Color.secondary)
            }
            .padding(.horizontal, kCategoryTabPaddingHorizontal)
            .padding(.vertical, kCategoryTabPaddingVertical)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary.opacity(0.9) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(getCategoryCount(for: category) == 0)
    }
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
                    AppIconView(appModel: appModel, app: app, isHovered: hoveredAppPath == app.path, hoveredAppInfo: nil)
                        .accessibilityLabel("\(app.name), application")
                        .accessibilityAddTraits(.isButton)
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

// MARK: - Visual Effect Background

/// NSVisualEffectView wrapper for a translucent, blurred background (like Launchpad)
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - App Icon View

struct AppIconView: View {
    @Bindable var appModel: AppModel
    let app: Application
    var isHovered: Bool = false
    var hoveredAppInfo: Application?
    var isSelected: Bool = false
    var isPressed: Bool = false
    var feedbackEnabled: Bool = true
    
    // Dark mode support
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        baseView
            .padding(kSectionViewPadding)
            .background(
                RoundedRectangle(cornerRadius: kAppIconCornerRadius)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: kAppIconCornerRadius)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isSelected || isHovered || (isPressed && feedbackEnabled) ? kAppIconHoverScale : 1.0)
            .shadow(color: (isSelected ? Color.accentColor.opacity(0.5) : (isHovered ? Color.accentColor.opacity(0.3) : (isPressed && feedbackEnabled ? Color.accentColor.opacity(0.3) : Color.clear))), radius: kAppIconShadowRadius, x: 0, y: kAppIconShadowOffsetY)
            .contentShape(Rectangle())
    }
    
    // Extracted to resolve compiler type-checking timeouts
    private var baseView: some View {
        VStack(alignment: .center, spacing: 8) {
            iconView
            appNameView
            if isHovered { hoverInfoView }
        }
    }
    
    private var iconView: some View {
        ZStack {
            // Read from appModel.loadedIconsByPath (not just app.icon) so this view reacts as
            // soon as the icon loads, independent of whether the containing ContentView re-renders.
            if let icon = appModel.loadedIconsByPath[app.path] ?? app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .padding(kAppIconPadding)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                    .padding(kAppIconPadding)
            }
            
        }
    }
    
    private var appNameView: some View {
        Text(app.name)
            .font(getFontForAppName())
            .fontWeight(getFontWeight())
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
    }

    private func getFontForAppName() -> Font {
        if appModel.fontFamily == "SF Pro" || appModel.fontFamily.starts(with: "SF Pro") {
            let weight = appModel.fontWeight == "bold" ? Font.Weight.bold : appModel.fontWeight == "light" ? Font.Weight.light : Font.Weight.regular
            return .system(size: appModel.fontSize, weight: weight, design: .default)
        } else {
            return .custom(appModel.fontFamily, size: appModel.fontSize)
        }
    }

    private func getFontWeight() -> Font.Weight {
        appModel.fontWeight == "bold" ? .bold : appModel.fontWeight == "light" ? .light : .regular
    }
    
    private var hoverInfoView: some View {
        VStack(spacing: 2) {
            if app.isFolder, let contained = app.containedApps, !contained.isEmpty {
                Text("\(contained.count) app\(contained.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let category = getCategoryDisplay(app) {
                Text(category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // Safely resolve icon size without relying on a missing `.value` property
    private var iconSize: CGFloat {
        switch appModel.iconSize {
        case .small: return kIconSizeSmall
        case .medium: return kIconSizeMedium
        case .large: return kIconSizeLarge
        }
    }
    
    private func getCategoryDisplay(_ app: Application) -> String? {
        switch appModel.getCategory(for: app) {
        case .system:
            return "System"
        case .utilities:
            return "Utilities"
        case .user, .mostUsed, .recentlyLaunched, .newlyInstalled, .all:
            return nil
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
    @Binding var pressedAppPath: String?
    let appPath: String

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
        Coordinator(pressedAppPath: $pressedAppPath, appPath: appPath)
    }

    class Coordinator: NSObject {
        @Binding var pressedAppPath: String?
        let appPath: String

        init(pressedAppPath: Binding<String?>, appPath: String) {
            _pressedAppPath = pressedAppPath
            self.appPath = appPath
        }

        func setPressed(_ pressed: Bool) {
            pressedAppPath = pressed ? appPath : nil
        }
    }
}