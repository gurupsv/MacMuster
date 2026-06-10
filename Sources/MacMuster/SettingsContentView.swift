import ServiceManagement
import SwiftUI

// MARK: - Settings Content View

struct SettingsContentView: View {
    @Bindable var appModel: AppModel
    @State private var selectedSection: SettingsSection = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            settingsSidebar
                .frame(width: kSidebarWidth)
            
            // Divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            
            // Content area
            VStack(spacing: 0) {
                settingsHeader
                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                settingsFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Sidebar
    
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, kSidebarHeaderPaddingHorizontal)
                .padding(.vertical, kSidebarHeaderPaddingVertical)
            
            // Section list - only show enabled sections
            ScrollView {
                VStack(alignment: .leading, spacing: kSidebarSectionSpacing) {
                    ForEach(getVisibleSections()) { section in
                        settingsSectionButton(section)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Version info
            VStack(alignment: .leading, spacing: 2) {
                Text("Version 1.0.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Mac App Manager")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, kSidebarVersionPaddingHorizontal)
            .padding(.bottom, kSidebarVersionPaddingBottom)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func getVisibleSections() -> [SettingsSection] {
        // Only show sections that are fully implemented
        return [.general, .appearance, .hiddenApps, .appDirectories, .backupRestore, .updates, .feedback]
    }
    
    private func settingsSectionButton(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 13))
                .frame(width: 20)
            
            Text(section.title)
                .font(.system(size: 13))
        }
        .foregroundStyle(selectedSection == section ? .white : Color(nsColor: .labelColor))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, kSidebarSectionPaddingHorizontal)
        .padding(.vertical, kSidebarSectionPaddingVertical)
        .background(
            RoundedRectangle(cornerRadius: kSidebarSectionCornerRadius)
                .fill(selectedSection == section ? Color.blue : Color.clear)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Header
    
    private var settingsHeader: some View {
        HStack {
            Text(selectedSection.title)
                .font(.system(size: 22, weight: .semibold))
            
            Spacer()
            
            Button(action: { SettingsWindowManager.shared.hide() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, kHeaderPaddingHorizontal)
        .padding(.vertical, kHeaderPaddingVertical)
    }
    
    // MARK: - Content
    
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: kSectionSpacing) {
                switch selectedSection {
                case .general:
                    GeneralSettingsPanel(appModel: appModel)
                case .appearance:
                    AppearanceSettingsPanel(appModel: appModel)
                case .hiddenApps:
                    HiddenAppsSettingsPanel(appModel: appModel)
                case .appDirectories:
                    AppDirectoriesSettingsPanel(appModel: appModel)
                case .backupRestore:
                    BackupRestoreSettingsPanel()
                case .updates:
                    UpdatesSettingsPanel()
                case .feedback:
                    FeedbackSettingsPanel()
                }
            }
            .padding(.horizontal, kContentPaddingHorizontal)
            .padding(.vertical, kContentPaddingVertical)
        }
    }
    
    // MARK: - Footer
    
    private var settingsFooter: some View {
        HStack {
            Spacer()
            Button("Done") {
                SettingsWindowManager.shared.hide()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, kFooterPaddingHorizontal)
        .padding(.vertical, kFooterPaddingVertical)
    }
}

// MARK: - Settings Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case hiddenApps
    case appDirectories
    case backupRestore
    case updates
    case feedback
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .hiddenApps: return "Hidden Apps"
        case .appDirectories: return "App Directories"
        case .backupRestore: return "Backup & Restore"
        case .updates: return "Updates & Info"
        case .feedback: return "Feedback"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .hiddenApps: return "eye.slash"
        case .appDirectories: return "folder.badge.plus"
        case .backupRestore: return "arrow.triangle.2.circlepath"
        case .updates: return "info.circle"
        case .feedback: return "envelope"
        }
    }
}

// MARK: - General Settings Panel

struct GeneralSettingsPanel: View {
    @Bindable var appModel: AppModel
    @State private var startAtLogin = false
    @State private var startAtLoginError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: kSectionSpacing) {
            // Startup section
            settingsSection(title: "Startup") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Start at Login")
                                .font(.system(size: 14, weight: .medium))
                            Text("Automatically launch MacMuster when you log in")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $startAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: startAtLogin) { _, newValue in
                                updateStartAtLogin(newValue)
                            }
                    }
                    .padding(kSectionContentPadding)
                    
                    if let startAtLoginError {
                        Text(startAtLoginError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(.horizontal, kErrorPaddingHorizontal)
                            .padding(.bottom, kErrorPaddingBottom)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            .onAppear {
                startAtLogin = SMAppService.mainApp.status == .enabled
            }
            
            // Folders section
            settingsSection(title: "Folders") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Show Folders First")
                                .font(.system(size: 14, weight: .medium))
                            Text("When enabled, folder icons appear at the top of the app list")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $appModel.showFoldersFirst)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(kSectionContentPadding)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            
            // App Management section
            settingsSection(title: "App Management") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Refresh Apps")
                                .font(.system(size: 14, weight: .medium))
                            Text("Scan for newly installed or removed applications")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                await appModel.refreshDisplayOrder()
                            }
                        } label: {
                            HStack(spacing: kButtonSpacing) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Now")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Auto Refresh")
                                .font(.system(size: 14, weight: .medium))
                            Text("Automatically scan for new apps at regular intervals")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(selection: $appModel.refreshInterval, label: EmptyView()) {
                            Text("5 minutes").tag(TimeInterval(300))
                            Text("15 minutes").tag(TimeInterval(900))
                            Text("30 minutes").tag(TimeInterval(1800))
                            Text("1 hour").tag(TimeInterval(3600))
                        }
                        .fixedSize()
                        .labelsHidden()
                        .onChange(of: appModel.refreshInterval) { _, _ in
                            appModel.setRefreshInterval(appModel.refreshInterval)
                        }
                    }
                }
                .padding(kSectionContentPadding)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
        }
    }
    
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: kSectionContentSpacing) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
    }
    
    private func updateStartAtLogin(_ isEnabled: Bool) {
        startAtLoginError = nil
        
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            startAtLoginError = error.localizedDescription
            startAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Glow Effect Settings Panel

struct GlowSettingsPanel: View {
    @Bindable var appModel: AppModel
    
    // Available colors for glow effect
    private let availableColors = [
        ("White", Color.white),
        ("Black", Color.black),
        ("Orange", Color(red: 1.0, green: 0.34, blue: 0.2)),
        ("Blue", Color(red: 0.2, green: 0.4, blue: 1.0)),
        ("Pink", Color(red: 1.0, green: 0.2, blue: 0.4)),
        ("Green", Color(red: 0.2, green: 1.0, blue: 0.34)),
        ("Cyan", Color(red: 0.2, green: 1.0, blue: 0.96)),
        ("Yellow", Color(red: 1.0, green: 0.96, blue: 0.2))
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: kSectionSpacing) {
            // Glow effect toggle
            settingsSection(title: "Glow Effect") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Enable Glow")
                                .font(.system(size: 14, weight: .medium))
                            Text("Show glowing edges around the overlay window")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $appModel.glowEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(kSectionContentPadding)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            
            // Color selection
            settingsSection(title: "Glow Color") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Select Glow Color")
                                .font(.system(size: 14, weight: .medium))
                            Text("Choose the color for the overlay window edges")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        
                        HStack(spacing: 8) {
                            ForEach(availableColors, id: \.0) { name, color in
                                Button(action: { appModel.glowColor = color }) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Circle()
                                                .stroke(appModel.glowColor == color ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(kSectionContentPadding)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            
            // Intensity slider
            settingsSection(title: "Glow Intensity") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Intensity")
                                .font(.system(size: 14, weight: .medium))
                            HStack(spacing: 4) {
                                Text("Glow strength:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(appModel.glowIntensity * 100))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        Spacer()
                        
                        Slider(value: $appModel.glowIntensity, in: 0...1) { _ in
                            // Intensity is clamped in AppModel
                        }
                    }
                    .padding(kSectionContentPadding)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            
            // Width slider
            settingsSection(title: "Glow Width") {
                VStack(alignment: .leading, spacing: kLabelSpacing) {
                    HStack(alignment: .top, spacing: kLabelSpacingVertical) {
                        VStack(alignment: .leading, spacing: kLabelSpacingVertical) {
                            Text("Width")
                                .font(.system(size: 14, weight: .medium))
                            HStack(spacing: 4) {
                                Text("Glow spread:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(appModel.glowWidth))pt")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        Spacer()
                        
                        Slider(value: $appModel.glowWidth, in: 10...100) { _ in
                            // Width is clamped in AppModel
                        }
                        .frame(width: 180)
                    }
                    .padding(kSectionContentPadding)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
        }
    }
    
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: kSectionContentSpacing) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
    }
}

// MARK: - Placeholder Panels

struct HotCornersSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hot Corners")
                .font(.system(size: 15, weight: .semibold))
            Text("Configure hot corner actions for multi-monitor workflows.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

struct AppearanceSettingsPanel: View {
    @Bindable var appModel: AppModel
    @State private var selectedFontFamily: String = "SF Pro Display"
    
    /// Get actual system font families (cached, computed once per process)
    private static let cachedFontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
    private var systemFontFamilies: [String] { Self.cachedFontFamilies }
    
    private let fontWeights = [
        ("Thin", "thin"),
        ("Ultra-Light", "ultralight"),
        ("Light", "light"),
        ("Regular", "normal"),
        ("Medium", "medium"),
        ("Semibold", "semibold"),
        ("Bold", "bold"),
        ("Heavy", "heavy"),
        ("Black", "black")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Glow Effect section (before Font)
            GlowSettingsPanel(appModel: appModel)
            
            Divider()
            
            // Font section
            settingsSection(title: "Font") {
                VStack(alignment: .leading, spacing: 14) {
                    // Font Family
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Font Family")
                            .font(.system(size: 14, weight: .medium))
                Picker(selection: $selectedFontFamily) {
                    ForEach(systemFontFamilies, id: \.self) { font in
                        Text(font)
                            .font(.system(size: 14, design: .default))
                            .tag(font)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .onChange(of: selectedFontFamily) { _, newValue in
                    appModel.setFontFamily(newValue)
                }
                .onAppear {
                    // Use the stored font family if it exists, otherwise default to first
                    if systemFontFamilies.contains(appModel.fontFamily) {
                        selectedFontFamily = appModel.fontFamily
                    } else if !systemFontFamilies.isEmpty {
                        selectedFontFamily = systemFontFamilies[0]
                        appModel.setFontFamily(selectedFontFamily)
                    }
                }
                    }
                    
                    Divider()
                    
                    // Font Size
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("\(Int(appModel.fontSize))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Slider(value: $appModel.fontSize, in: 10...48, step: 1) {
                            Text("Size")
                        }
                    }
                    
                    Divider()
                    
                    // Font Weight
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Font Weight")
                            .font(.system(size: 14, weight: .medium))
                        Picker(selection: $appModel.fontWeight) {
                            ForEach(fontWeights, id: \.1) { weight in
                                Text(weight.0)
                                    .font(.system(size: 14, weight: weightFromString(weight.1)))
                                    .tag(weight.1)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .onChange(of: appModel.fontWeight) { _, newValue in
                            appModel.setFontWeight(newValue)
                        }
                    }
                }
                .padding(kSectionContentPadding)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
            
            // Layout section
            settingsSection(title: "Layout") {
                VStack(alignment: .leading, spacing: 14) {
                    // Column Count
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Column Count")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("\(appModel.columnCount)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Text("Number of columns in the app grid")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        Slider(value: Binding(
                            get: { Double(appModel.columnCount) },
                            set: { newValue in
                                appModel.setColumnCount(Int(newValue.rounded()))
                            }
                        ), in: Double(kMinColumnCount)...Double(kMaxColumnCount), step: 1)
                    }
                    
                    Divider()
                    
                    // Icon Size
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Icon Size")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(appModel.iconSize.rawValue.uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Picker(selection: $appModel.iconSize) {
                            ForEach(AppModel.IconSize.allCases, id: \.self) { size in
                                Text(size.rawValue.capitalized)
                                    .tag(size)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appModel.iconSize) { _, _ in
                            appModel.setIconSize(appModel.iconSize)
                        }
                    }
                }
                .padding(kSectionContentPadding)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(kSectionContentCornerRadius)
            }
        }
    }
    
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: kSectionContentSpacing) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
    }
    
    private func weightFromString(_ weight: String) -> Font.Weight {
        switch weight {
        case "thin": return .thin
        case "ultralight": return .ultraLight
        case "light": return .light
        case "normal": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }
}

struct SpacesSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spaces")
                .font(.system(size: 15, weight: .semibold))
            Text("Configure behavior across macOS Spaces and desktops.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hidden Apps Settings Panel

struct HiddenAppsSettingsPanel: View {
    @Bindable var appModel: AppModel
    @State private var searchText: String = ""
    
    private var allApps: [AppModel.Application] {
        if searchText.isEmpty {
            return appModel.displayOrder
        }
        let lower = searchText.lowercased()
        return appModel.displayOrder.filter {
            $0.name.lowercased().contains(lower)
            || $0.path.lowercased().contains(lower)
        }
    }
    
    private var hiddenApps: [AppModel.Application] {
        allApps.filter { $0.isHidden }
    }
    
    private var visibleApps: [AppModel.Application] {
        allApps.filter { !$0.isHidden }
    }
    
    private var totalHiddenCount: Int {
        appModel.displayOrder.filter { $0.isHidden }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Hidden Apps")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(totalHiddenCount) hidden, \(appModel.displayOrder.count - totalHiddenCount) visible")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Text("Apps hidden from the launcher. Toggle visibility using the checkboxes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.body)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            
            if appModel.displayOrder.isEmpty {
                Text("No applications found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, kHiddenAppsListPaddingVertical)
            } else {
                // All apps list with checkboxes
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(allApps) { app in
                            HiddenAppRow(appModel: appModel, app: app) {
                                appModel.toggleHiddenApp(app.path)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                }
            }
        }
    }
}

// MARK: - Hidden App Row

struct HiddenAppRow: View {
    @Bindable var appModel: AppModel
    let app: AppModel.Application
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: app.isHidden ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(app.isHidden ? .blue : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            
            // App name
            Text(app.name)
                .font(.system(size: 13))
                .lineLimit(1)
            
            Spacer()
            
            // Category badge
            Text(categoryLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: Capsule())
            
            // Hidden indicator
            if app.isHidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                self.isHovered = isHovered
            }
        }
    }
    
    @State private var isHovered: Bool = false
    
    private var categoryLabel: String {
        switch appModel.getCategory(for: app) {
        case .system: return "System"
        case .utilities: return "Utilities"
        case .user, .mostUsed, .recentlyLaunched, .newlyInstalled: return "User"
        }
    }
}

// MARK: - Backup & Restore Panel

struct BackupRestoreSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Backup & Restore")
                .font(.system(size: 15, weight: .semibold))
            Text("Export and import your settings and preferences.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Updates & Info Panel

struct UpdatesSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Updates & Info")
                .font(.system(size: 15, weight: .semibold))
            Text("Application version and update information.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feedback Panel

struct FeedbackSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Feedback")
                .font(.system(size: 15, weight: .semibold))
            Text("Send feedback or report issues.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - App Directories Settings Panel

struct AppDirectoriesSettingsPanel: View {
    @Bindable var appModel: AppModel
    
    @State private var newDirectoryPath: String = ""
    @State private var showPicker = false
    @State private var searchFilter: String = ""
    
    private let kSearchPadding: CGFloat = 12
    private let kSearchCornerRadius: CGFloat = 10
    private let kSearchBG: Color = Color(nsColor: .controlBackgroundColor)
    private let kSearchBorder: Color = Color(nsColor: .textBackgroundColor)
    private let kSearchBorderFocused: Color = Color.blue
    
    var filteredDirectories: [String] {
        if searchFilter.isEmpty {
            return appModel.customDirectories
        }
        return appModel.customDirectories.filter {
            $0.localizedCaseInsensitiveContains(searchFilter)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Application Directories")
                    .font(.system(size: 15, weight: .semibold))
                Text("Custom directories to scan for additional applications.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            // Built-in directories info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Built-in directories (always scanned):")
                        .font(.system(size: 12, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"], id: \.self) { dir in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                            Text(dir)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: NSColor.separatorColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Custom directories section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    Text("Custom directories (\(filteredDirectories.count) added)")
                        .font(.system(size: 12, weight: .medium))
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Filter directories...", text: $searchFilter)
                        .textFieldStyle(.plain)
                    if !searchFilter.isEmpty {
                        Button(action: { searchFilter = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, kSearchPadding)
                .padding(.vertical, 10)
                .background(kSearchBG)
                .cornerRadius(kSearchCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: kSearchCornerRadius)
                        .stroke(searchFilter.isEmpty ? kSearchBorder : kSearchBorderFocused, lineWidth: 1)
                )
                
                // Directory list
                if filteredDirectories.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.quaternary)
                        Text(appModel.customDirectories.isEmpty ? "No custom directories added" : "No directories match your search")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 80)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(filteredDirectories, id: \.self) { dir in
                                AppDirectoryRow(
                                    path: dir,
                                    onRemove: {
                                        appModel.removeCustomDirectory(dir)
                                        if searchFilter.isEmpty || !searchFilter.contains(dir) {
                                            // no-op to trigger refresh
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 120)
                }
                
                // Add directory area
                HStack(spacing: 8) {
                    Button(action: { showPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                            Text("Add Directory")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                    .fileImporter(
                        isPresented: $showPicker,
                        allowedContentTypes: [.item],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            if let url = urls.first {
                                let shouldStopAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if shouldStopAccess { url.stopAccessingSecurityScopedResource() }
                                }
                                let path = url.path
                                // Verify it's a directory
                                if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
                                    appModel.addCustomDirectory(path)
                                    newDirectoryPath = ""
                                }
                            }
                        case .failure:
                            break
                        }
                    }
                    
                    Spacer()
                    
                    if !appModel.customDirectories.isEmpty {
                        Button(action: {
                            // Clear all custom directories
                            for dir in appModel.customDirectories {
                                appModel.removeCustomDirectory(dir)
                            }
                        }) {
                            Text("Clear All")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - App Directory Row

struct AppDirectoryRow: View {
    let path: String
    let onRemove: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow)
                .frame(width: 24)
            
            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                self.isHovered = isHovered
            }
        }
    }
}

// MARK: - Danger Zone Panel

struct DangerZoneSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Danger Zone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
            Text("These actions are irreversible. Proceed with caution.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}