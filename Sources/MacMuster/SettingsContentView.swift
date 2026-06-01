import ServiceManagement
import SwiftUI

// MARK: - Settings Content View

struct SettingsContentView: View {
    @EnvironmentObject var appModel: AppModel
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
            
            // Section list
            ScrollView {
                VStack(alignment: .leading, spacing: kSidebarSectionSpacing) {
                    ForEach(SettingsSection.allCases) { section in
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
                    GeneralSettingsPanel()
                case .hotCorners:
                    HotCornersSettingsPanel()
                case .appearance:
                    AppearanceSettingsPanel()
                case .spaces:
                    SpacesSettingsPanel()
                case .hiddenApps:
                    HiddenAppsSettingsPanel()
                case .appDirectories:
                    AppDirectoriesSettingsPanel()
                case .backupRestore:
                    BackupRestoreSettingsPanel()
                case .updates:
                    UpdatesSettingsPanel()
                case .feedback:
                    FeedbackSettingsPanel()
                case .dangerZone:
                    DangerZoneSettingsPanel()
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
    case hotCorners
    case appearance
    case spaces
    case hiddenApps
    case appDirectories
    case backupRestore
    case updates
    case feedback
    case dangerZone
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .hotCorners: return "Hot Corners"
        case .appearance: return "Appearance"
        case .spaces: return "Spaces"
        case .hiddenApps: return "Hidden Apps"
        case .appDirectories: return "App Directories"
        case .backupRestore: return "Backup & Restore"
        case .updates: return "Updates & Info"
        case .feedback: return "Feedback"
        case .dangerZone: return "Danger Zone"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotCorners: return "square.2.layers.3d"
        case .appearance: return "paintpalette"
        case .spaces: return "apps"
        case .hiddenApps: return "eye.slash"
        case .appDirectories: return "folder.badge.plus"
        case .backupRestore: return "arrow.triangle.2.circlepath"
        case .updates: return "info.circle"
        case .feedback: return "envelope"
        case .dangerZone: return "exclamationmark.triangle"
        }
    }
}

// MARK: - General Settings Panel

struct GeneralSettingsPanel: View {
    @EnvironmentObject var appModel: AppModel
    @State private var startAtLogin = false
    @State private var startAtLoginError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: kSectionSpacing) {
            // Startup section
            settingsSection(title: "Startup") {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: kLabelSpacing) {
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
                            .onChange(of: startAtLogin) { newValue in
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
                            appModel.refreshDisplayOrder()
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
    @EnvironmentObject var appModel: AppModel
    @State private var selectedFontFamily: String = "SF Pro Display"
    
    // Available system fonts - these are actual font family names available on macOS
    private let availableFonts = [
        "SF Pro Display",
        "SF Pro Text",
        "Helvetica Neue",
        "Helvetica",
        "Arial",
        "Arial Hebrew",
        "Avenir",
        "Avenir Next",
        "Avenir Next Condensed",
        "Baskerville",
        "Chalkboard SE",
        "Chalkduster",
        "Cochin",
        "Copperplate",
        "Courier New",
        "Didot",
        "Futura",
        "Georgia",
        "Gill Sans",
        "Helvetica",
        "Helvetica Neue",
        "Herculanum",
        "Lucida Grande",
        "Menlo",
        "Noteworthy",
        "Optima",
        "Palatino",
        "STIXGeneral",
        "STIXIntegralsDF",
        "STIXNonUnicode",
        "STIXSizeOneSym",
        "Snell Roundhand",
        "Times",
        "Times New Roman",
        "Trattatello",
        "Zapfino"
    ]
    
    /// Get actual system font families and filter to only those that exist
    private var systemFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private let fontSizes = [10, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 48]
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
                .onChange(of: selectedFontFamily) { newValue in
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
                        .onChange(of: appModel.fontSize) { _ in
                            appModel.applyFontSettings()
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
                                    .font(.system(size: 14, weight: weightWeightFromString(weight.1)))
                                    .tag(weight.1)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .onChange(of: appModel.fontWeight) { newValue in
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
    
    private func weightWeightFromString(_ weight: String) -> Font.Weight {
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
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hidden Apps")
                .font(.system(size: 15, weight: .semibold))
            
            Text("Apps listed below are hidden from the launcher view.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            if appModel.displayOrder.isEmpty {
                Text("No applications found.")
                    .foregroundStyle(.secondary)
            } else {
                let hiddenApps = appModel.displayOrder.filter { $0.isHidden }
                
                if hiddenApps.isEmpty {
                    Text("No hidden apps")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, kHiddenAppsListPaddingVertical)
                } else {
                    List(hiddenApps, id: \.path) { app in
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }
                            Text(app.name)
                                .font(.system(size: 13))
                            Spacer()
                            Button("Show") {
                                appModel.toggleHiddenApp(app.path)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    .listStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - App Directories Settings Panel

struct AppDirectoriesSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App Directories")
                .font(.system(size: 15, weight: .semibold))
            Text("Configure which directories are scanned for applications.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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

// MARK: - Danger Zone Panel

struct DangerZoneSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Danger Zone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
            Text("Irreversible actions. Proceed with caution.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
