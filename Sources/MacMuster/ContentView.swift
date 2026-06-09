import SwiftUI

@MainActor
struct ContentView: View {
    @Bindable var appModel: AppModel
    @State private var hoveredAppPath: String?
    @FocusState private var isSearchFocused: Bool
    @State private var showCreateFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var selectedAppPathsForFolder: [String] = []
    
    // Dark mode support - use dynamic colors
    @Environment(\.colorScheme) private var colorScheme
    
    // Cache grid columns to avoid allocation on every body render.
    // Invalidates when columnCount changes.
    @State private var gridColumnCache: (count: Int, columns: [GridItem])?
    private static let recentColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: kGridSpacing), count: kRecentColumnCount)
    
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
            // Blurred translucent background (like Launchpad)
            VisualEffectBackground()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // If inside a folder, close the folder and return to root
                    if appModel.currentFolder != nil {
                        appModel.closeFolder()
                    } else {
                        StatusBarManager.shared.hideWindow()
                    }
                }
            
            // Glow effect rendered on top of VisualEffectBackground (visible) 
            // but behind content (non-hittable)
            GlowEffectView(appModel: appModel)
            
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
                    
                    // Keyboard hints pill (above categories, shown on first launch)
                    if !visibleApps.isEmpty {
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
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    } else {
                        // Header with category tabs and action buttons
                        HStack {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(AppModel.AppCategory.allCases.enumerated()), id: \.offset) { _, category in
                                        categoryTabButton(for: category)
                                    }
                                }
                            }
                            
                            Spacer()
                            
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
                                Text("Sort: \(appModel.sortOption.rawValue)")
                                    .font(.subheadline)
                                    .padding(.horizontal, kSortMenuPaddingHorizontal)
                                    .padding(.vertical, kSortMenuPaddingVertical)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: kSortMenuCornerRadius))
                            }
                            
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
                        }
                        .padding(.horizontal)
                    }
                    
                    // Search bar with integrated keyboard hints
                    searchBar
                    
                    // Recent Apps Section
                    let recentApps = appModel._recentApps
                    if !recentApps.isEmpty {
                        SectionView(appModel: appModel, title: "Recent", apps: recentApps, columns: Self.recentColumns) { app in
                            if ApplicationService.shared.launchApplication(at: app.path, appModel: appModel) {
                                StatusBarManager.shared.hideWindow()
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
                                    spacing: 20
                                ) {
                                    ForEach(Array(displayedApps.enumerated()), id: \.element.path) { index, app in
                                        gridItemView(app: app, index: index)
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
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appModel.currentFolder != nil {
                                appModel.closeFolder()
                            } else {
                                StatusBarManager.shared.hideWindow()
                            }
                        }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            // Escape key dismisses the launcher
            StatusBarManager.shared.hideWindow()
        }
        // Only focus search field when user explicitly types or clicks it
        // By default, keyboard events go to the window for arrow key navigation
        .task {
            await appModel.startLoading()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidShow)) { _ in
            // Don't auto-focus the search field - let arrow keys work immediately
            isSearchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusSearchField"))) { _ in
            // Focus search field when / key is pressed
            isSearchFocused = true
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
    
    private func getCategoryCount(for category: AppModel.AppCategory) -> Int {
        appModel.categoryCounts[category, default: 0]
    }
    
    // MARK: - Grid Item View (Fixes compiler timeout)
    @ViewBuilder
    private func gridItemView(app: AppModel.Application, index: Int) -> some View {
        AppIconView(
            appModel: appModel,
            app: app,
            isHovered: hoveredAppPath == app.path,
            hoveredAppInfo: hoveredAppPath == app.path ? app : nil,
            isSelected: appModel.selectedAppIndex == index
        )
        .id(app.path)
        .onHover { isHovered in
            hoveredAppPath = isHovered ? app.path : nil
        }
        .onTapGesture {
            handleAppTap(app)
        }
        .contextMenu { folderContextMenu(app) }
    }

    private func handleAppTap(_ app: AppModel.Application) {
        if app.path.hasPrefix("folder:") {
            let folderPath = app.path.dropFirst(7) // Remove "folder:"
            let folderId = String(folderPath)
            if appModel.currentFolderId != folderId {
                appModel.openFolder(folderId)
            }
        } else {
            if ApplicationService.shared.launchApplication(at: app.path, appModel: appModel) {
                StatusBarManager.shared.hideWindow()
            }
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
    @ViewBuilder
    private func folderContextMenu(_ app: AppModel.Application) -> some View {
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
    private func categoryTabButton(for category: AppModel.AppCategory) -> some View {
        Button {
            // Lazy load system categories when first selected
            switch category {
            case .mostUsed where appModel.mostUsedDirty:
                appModel.refreshMostUsedApps()
            case .recentlyLaunched where appModel.recentlyLaunchedDirty:
                appModel.refreshRecentlyLaunchedApps()
            case .newlyInstalled:
                // Newly installed is fast, always refresh
                appModel.refreshNewlyInstalledApps()
            default:
                break
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                appModel.selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Text(category.rawValue)
                    .font(.subheadline)
                Text("\(getCategoryCount(for: category))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, kCategoryTabPaddingHorizontal)
            .padding(.vertical, kCategoryTabPaddingVertical)
            .background(
                RoundedRectangle(cornerRadius: kCategoryTabCornerRadius)
                    .fill(appModel.selectedCategory == category ? Color.white.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(getCategoryCount(for: category) == 0)
    }
}

// MARK: - Section View (for Recent Apps)

struct SectionView: View {
    @Bindable var appModel: AppModel
    let title: String
    let apps: [AppModel.Application]
    let columns: [GridItem]
    let onLaunch: (AppModel.Application) -> Void
    
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
                    AppIconView(appModel: appModel, app: app, isHovered: false, hoveredAppInfo: nil)
                        .onTapGesture {
                            onLaunch(app)
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
    let app: AppModel.Application
    var isHovered: Bool = false
    var hoveredAppInfo: AppModel.Application?
    var isSelected: Bool = false
    
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
            .scaleEffect(isSelected || isHovered ? kAppIconHoverScale : 1.0)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.5) : (isHovered ? Color.accentColor.opacity(0.3) : Color.clear), radius: kAppIconShadowRadius, x: 0, y: kAppIconShadowOffsetY)
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
            if let icon = app.icon {
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
            .font(.system(size: appModel.fontSize, weight: appModel.fontWeight == "bold" ? .bold : .regular, design: .default))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: 80)
            .foregroundStyle(isSelected || isHovered ? .primary : .primary)
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
    
    private func getCategoryDisplay(_ app: AppModel.Application) -> String? {
        switch appModel.getCategory(for: app) {
        case .system:
            return "System"
        case .utilities:
            return "Utilities"
        case .user, .mostUsed, .recentlyLaunched, .newlyInstalled:
            return nil
        }
    }
}