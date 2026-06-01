import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var hoveredAppPath: String?
    @FocusState private var isSearchFocused: Bool
    
    // Track whether user has explicitly focused the search field
    @State private var hasFocusedSearchField: Bool = false
    
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
                let displayedApps = appModel.displayedApplications

                VStack(alignment: .leading, spacing: 16) {
                    // Keyboard shortcut hints
                    if !visibleApps.isEmpty {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard.fill")
                                    .font(.caption2)
                                Text("↑↓←→ Navigate")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                            
                            HStack(spacing: 4) {
                                Image(systemName: "return")
                                    .font(.caption2)
                                Text("Launch")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                            
                            HStack(spacing: 4) {
                                Image(systemName: "slash")
                                    .font(.caption2)
                                Text("Search")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                            
                            HStack(spacing: 4) {
                                Image(systemName: "escape")
                                    .font(.caption2)
                                Text("Unfocus/Close")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary.opacity(0.6))
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    // Top padding to account for notch/menubar area
                    Spacer()
                        .frame(height: 40)
                    
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.body)
                        TextField("Search applications...", text: $appModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($isSearchFocused, equals: true)
                            .onChange(of: isSearchFocused) { newValue in
                                if newValue {
                                    hasFocusedSearchField = true
                                }
                            }
                        
                        if !appModel.searchText.isEmpty {
                            Button {
                                appModel.searchText = ""
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
                    .frame(maxWidth: kSearchMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Header with sorting control and category tabs
                    HStack {
                        // Category tabs
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AppModel.AppCategory.allCases, id: \.self) { category in
                                    let count = appModel.categoryCounts[category, default: 0]
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            appModel.selectedCategory = category
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(category.rawValue)
                                                .font(.subheadline)
                                            Text("\(count)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, kCategoryTabPaddingHorizontal)
                                        .padding(.vertical, kCategoryTabPaddingVertical)
                                        .background(
                                            appModel.selectedCategory == category
                                                ? Color.white.opacity(0.2)
                                                : Color.clear
                                        )
                                        .background(
                                            RoundedRectangle(cornerRadius: kCategoryTabCornerRadius)
                                                .fill(appModel.selectedCategory == category ? Color.white.opacity(0.15) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(count == 0)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(visibleApps.count) apps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
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
                            HStack(spacing: 4) {
                                Text("Sort: \(appModel.sortOption.rawValue)")
                                    .font(.subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, kSortMenuPaddingHorizontal)
                            .padding(.vertical, kSortMenuPaddingVertical)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: kSortMenuCornerRadius))
                        }
                        
                        // Settings button
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
                    
                    // Recent Apps Section - use cached recent apps from model
                    let recentApps = appModel._recentApps
                    if !recentApps.isEmpty {
                        SectionView(title: "Recent", apps: recentApps, columns: Self.recentColumns) { app in
                            if ApplicationService.shared.launchApplication(at: app.path, appModel: appModel) {
                                StatusBarManager.shared.hideWindow()
                            }
                        }
                    }
                    
                    // App grid
                    if displayedApps.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: appModel.searchText.isEmpty ? "folder" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(appModel.searchText.isEmpty
                                 ? "No applications found"
                                 : "No results for \"\(appModel.searchText)\"")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: gridColumns,
                                spacing: 20
                            ) {
                                ForEach(Array(displayedApps.enumerated()), id: \.element.path) { index, app in
                                    AppIconView(
                                        app: app,
                                        isHovered: hoveredAppPath == app.path,
                                        hoveredAppInfo: hoveredAppPath == app.path ? app : nil,
                                        isSelected: appModel.selectedAppIndex == index
                                    )
                                    .onHover { isHovered in
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            hoveredAppPath = isHovered ? app.path : nil
                                        }
                                    }
                                    .onTapGesture {
                                        if ApplicationService.shared.launchApplication(at: app.path, appModel: appModel) {
                                            StatusBarManager.shared.hideWindow()
                                        }
                                    }
                                    .contextMenu {
                                        if app.isFolder {
                                            Button {
                                                // Open app folder in Finder
                                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                                            } label: {
                                                Label("Show in Finder", systemImage: "folder")
                                            }
                                        }
                                        
                                        Button {
                                            appModel.toggleHiddenApp(app.path)
                                        } label: {
                                            Label(appModel.isAppHidden(app.path) ? "Show App" : "Hide App", systemImage: appModel.isAppHidden(app.path) ? "eye" : "eye.slash")
                                        }
                                        
                                        if !app.isFolder {
                                            Button {
                                                // Open app folder in Finder
                                                let parentPath = (app.path as NSString).deletingLastPathComponent
                                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: parentPath)])
                                            } label: {
                                                Label("Show in Finder", systemImage: "folder")
                                            }
                                        }
                                        
                                        Button {
                                            // Copy app path to clipboard
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(app.path, forType: .string)
                                        } label: {
                                            Label("Copy Path", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(minWidth: kWindowMinWidth, minHeight: kWindowMinHeight)
                .padding(.horizontal)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            StatusBarManager.shared.hideWindow()
                        }
                )
                
                Spacer()
                    .frame(height: kWindowPadding)  // Bottom padding
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
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidShow)) { _ in
            // Don't auto-focus the search field - let arrow keys work immediately
            isSearchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusSearchField"))) { _ in
            // Focus search field when / key is pressed
            isSearchFocused = true
        }
    }
}

// MARK: - Section View (for Recent Apps)

struct SectionView: View {
    @EnvironmentObject var appModel: AppModel
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
                    AppIconView(app: app, isHovered: false, hoveredAppInfo: nil)
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
    @EnvironmentObject var appModel: AppModel
    let app: AppModel.Application
    var isHovered: Bool = false
    var hoveredAppInfo: AppModel.Application?
    var isSelected: Bool = false
    
    // Dark mode support
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: appModel.iconSize.value, height: appModel.iconSize.value)
                        .padding(kAppIconPadding)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .frame(width: appModel.iconSize.value, height: appModel.iconSize.value)
                        .padding(kAppIconPadding)
                }
                
                // Folder indicator badge
                if app.isFolder {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(.gray, in: Capsule())
                        }
                        Spacer()
                    }
                }
                
            }
            
            Text(app.name)
                .font(.system(size: appModel.fontSize, weight: appModel.fontWeight == "bold" ? .bold : .regular, design: .default))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 80)
                .foregroundStyle(isSelected || isHovered ? .primary : .primary)
            
            // App info on hover
            if isHovered {
                VStack(spacing: 2) {
                    if app.isFolder, let contained = app.containedApps, !contained.isEmpty {
                        Text("\(contained.count) apps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let size = app.appSize {
                        Text(size)
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
        }
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
    
    private func getCategoryDisplay(_ app: AppModel.Application) -> String? {
        switch appModel.getCategory(for: app) {
        case .system:
            return "System"
        case .utilities:
            return "Utilities"
        case .user:
            return nil
        }
    }
}
