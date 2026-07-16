import XCTest
import SwiftUI
import AppKit
@testable import MacMuster

/// Opt-in README screenshot generator. Renders the real ContentView / SettingsContentView
/// offscreen with sample apps + folders over a synthetic wallpaper, and writes PNGs into
/// the repo `Screenshots/` directory.
///
/// Skipped during normal `swift test`. Run explicitly with:
///     GEN_README_IMAGES=1 swift test --filter ReadmeImageGen
@MainActor
final class ReadmeImageGen: XCTestCase {

    /// Repo `Screenshots/` directory, derived from this source file's location
    /// (<repo>/Tests/ReadmeImageGen.swift) so the generator is portable across machines.
    private var outDir: String {
        URL(fileURLWithPath: #filePath)          // .../Tests/ReadmeImageGen.swift
            .deletingLastPathComponent()          // .../Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Screenshots")
            .path
    }

    private func requireOptIn() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GEN_README_IMAGES"] != nil,
                          "Set GEN_README_IMAGES=1 to generate README screenshots.")
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }

    // MARK: - Sample data

    /// Candidate system apps; filtered to those that actually exist so the set adapts to the
    /// macOS version and every icon is a real one.
    private static let candidatePaths: [String] = {
        let apps = [
            "App Store", "Automator", "Books", "Calculator", "Calendar", "Chess", "Clock",
            "Contacts", "Dictionary", "FaceTime", "Find My", "Font Book", "Freeform", "Home",
            "Mail", "Maps", "Messages", "Music", "News", "Notes", "Photo Booth", "Photos",
            "Podcasts", "Preview", "Reminders", "Shortcuts", "Stickies", "Stocks",
            "System Settings", "TV", "TextEdit", "Tips", "Voice Memos", "Weather", "Passwords",
        ].map { "/System/Applications/\($0).app" }
        let utils = [
            "Activity Monitor", "AirPort Utility", "Audio MIDI Setup", "Bluetooth File Exchange",
            "Boot Camp Assistant", "ColorSync Utility", "Console", "Digital Color Meter",
            "Disk Utility", "Grapher", "Keychain Access", "Screenshot", "System Information",
            "Terminal", "VoiceOver Utility",
        ].map { "/System/Applications/Utilities/\($0).app" }
        return (apps + utils).filter { FileManager.default.fileExists(atPath: $0) }
    }()

    private func displayName(for path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func application(_ path: String, installedDaysAgo: Double) -> Application {
        Application(
            id: path,
            name: displayName(for: path),
            path: path,
            icon: NSWorkspace.shared.icon(forFile: path),
            installationDate: Date().addingTimeInterval(-installedDaysAgo * 86_400),
            isFolder: false
        )
    }

    /// Build a fully-populated AppModel: real system-app icons, a few folders, recent apps.
    private func makeModel(scheme: ColorScheme) -> AppModel {
        let model = AppModel()
        let paths = Self.candidatePaths

        // Vary install dates: a handful are "newly installed" (< a few days), rest older.
        let apps = paths.enumerated().map { index, path -> Application in
            let days: Double = index % 9 == 0 ? 1.5 : Double(20 + index * 3)
            return application(path, installedDaysAgo: days)
        }

        func pathsFor(_ names: [String]) -> [String] {
            names.compactMap { name in paths.first { displayName(for: $0) == name } }
        }

        let folders: [AppFolder] = [
            AppFolder(name: "Utilities", appPaths: pathsFor([
                "Activity Monitor", "Terminal", "Console", "Disk Utility",
                "System Information", "Keychain Access", "ColorSync Utility", "Grapher", "Screenshot",
            ])),
            AppFolder(name: "Media", appPaths: pathsFor([
                "Music", "Podcasts", "TV", "Photos", "Books", "Photo Booth",
            ])),
            AppFolder(name: "Productivity", appPaths: pathsFor([
                "Notes", "Reminders", "Calendar", "Freeform", "Mail", "Contacts",
            ])),
            AppFolder(name: "Internet", appPaths: pathsFor([
                "Messages", "FaceTime", "News", "Maps",
            ])),
        ].filter { !$0.appPaths.isEmpty }

        // Folders must be known before setApplications so the path index / folder folding are consistent.
        model.folders = folders
        model.setApplications(apps)
        model.isLoading = false
        model.hasShownLauncher = true           // hide the first-launch keyboard-hint pill
        model.columnCount = 8
        model.iconSize = .medium
        model.showRecentApps = false
        // AppModel() loads persisted prefs from UserDefaults — including a currentFolderId left
        // by the real app on this machine, which would make the root grid render "inside" a
        // now-missing folder (empty). Reset navigation to a clean root state.
        model.currentFolderId = nil
        model.selectedCategory = .all
        model.searchTerm = ""

        // Recent apps: pick foldered members so they survive root-grid dedup and the strip shows.
        let recentNames = ["Terminal", "Music", "Notes", "Photos", "Calendar", "Reminders"]
        model._recentApps = pathsFor(recentNames).map { application($0, installedDaysAgo: 40) }

        return model
    }

    // MARK: - Rendering helpers

    private func writePNG(rep: NSBitmapImageRep, to name: String) throws {
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]), "no png for \(name)")
        try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }

    /// Rasterize through a real offscreen `NSHostingView` (not `ImageRenderer`): the AppKit
    /// layout pass materializes `ScrollView` / `LazyVGrid` content, which `ImageRenderer`
    /// leaves blank. Renders the layer tree at `scale`× for retina-sharp output.
    /// `cropHeight` (in points, measured from the top) trims dead space below the content while
    /// keeping the header. The SwiftUI layout is only reliable at a generous canvas height, so we
    /// render tall and crop rather than shrinking the frame (which clips the header).
    private func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, scale: CGFloat = 2, cropHeight: CGFloat? = nil, to name: String) throws {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let root = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: AnyView(root))
        // Pin the hosting view to exactly `size`. Without this, NSHostingView resizes itself to
        // its content's ideal size during the run-loop settle below, shifting/clipping the header.
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = appearance
        hosting.wantsLayer = true

        // A window context is what makes the SwiftUI ScrollViews actually lay out and draw.
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.orderBack(nil)

        // Give the run loop a beat so lazy grid cells and async icon layout settle.
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "no rep for \(name)")
        rep.size = size
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep), "no ctx for \(name)")
        if let layer = hosting.layer {
            layer.contentsScale = scale
            // CALayer geometry is top-left origin; the CG bitmap context is bottom-left, so
            // render() lands upside-down. Flip the context vertically to correct it.
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            layer.render(in: ctx.cgContext)
        }
        window.contentView = nil
        window.orderOut(nil)

        // Optionally crop dead space off the bottom, keeping the top `cropHeight` points.
        if let cropHeight, cropHeight < size.height, let cg = rep.cgImage {
            let cropPixels = Int(cropHeight * scale)
            if let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: cropPixels)) {
                let croppedRep = NSBitmapImageRep(cgImage: cropped)
                croppedRep.size = CGSize(width: size.width, height: cropHeight)
                try writePNG(rep: croppedRep, to: name)
                return
            }
        }
        try writePNG(rep: rep, to: name)
    }

    // Baked blurred-wallpaper images per scheme. The blur is rendered here via ImageRenderer
    // (which honours SwiftUI `.blur`) because the hosting-view `layer.render` path used for the
    // real UI ignores layer blur filters. Cached so we bake each scheme only once.
    private var wallpaperCache: [Bool: NSImage] = [:]

    private func bakedWallpaper(_ scheme: ColorScheme) -> NSImage {
        let isDark = scheme == .dark
        if let cached = wallpaperCache[isDark] { return cached }
        let size = CGSize(width: 1600, height: 1000)
        let renderer = ImageRenderer(content: wallpaperGradient(scheme).frame(width: size.width, height: size.height))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: size)
        wallpaperCache[isDark] = image
        return image
    }

    // Synthetic blurred wallpaper — stands in for the user's desktop behind the glass panel.
    private func wallpaperGradient(_ scheme: ColorScheme) -> some View {
        let top = scheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.20) : Color(red: 0.62, green: 0.70, blue: 0.86)
        let bottom = scheme == .dark ? Color(red: 0.03, green: 0.03, blue: 0.06) : Color(red: 0.36, green: 0.42, blue: 0.60)
        return ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.35, green: 0.20, blue: 0.55)).frame(width: 900, height: 900)
                .blur(radius: 160).opacity(0.55).offset(x: -320, y: -260)
            Circle().fill(Color(red: 0.90, green: 0.45, blue: 0.30)).frame(width: 700, height: 700)
                .blur(radius: 170).opacity(0.40).offset(x: 380, y: 300)
            Circle().fill(Color(red: 0.20, green: 0.45, blue: 0.70)).frame(width: 640, height: 640)
                .blur(radius: 150).opacity(0.45).offset(x: 260, y: -280)
        }
        .clipped()
    }

    // The baked wallpaper as a resizable SwiftUI image, for use inside the hosting composite.
    private func wallpaper(_ scheme: ColorScheme) -> some View {
        Image(nsImage: bakedWallpaper(scheme))
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    // The launcher glass panel content (scrim + real ContentView) over whatever background.
    private func launcherContent(_ model: AppModel, scheme: ColorScheme) -> some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.45 : 0.28)
            GlowEffectView(appModel: model)
            ContentView(appModel: model)
        }
    }

    // Full-bleed launcher (fullscreen / maximized presentation).
    private func fullscreenPoster(_ model: AppModel, scheme: ColorScheme) -> some View {
        ZStack {
            wallpaper(scheme)
            launcherContent(model, scheme: scheme)
        }
    }

    // Windowed launcher: a rounded, shadowed panel floating on the desktop.
    private func windowPoster(_ model: AppModel, scheme: ColorScheme, canvas: CGSize) -> some View {
        let panelW = canvas.width * 0.66
        let panelH = canvas.height * 0.72
        return ZStack {
            wallpaper(scheme)
            launcherContent(model, scheme: scheme)
                .frame(width: panelW, height: panelH)
                .background(scheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.09) : Color(red: 0.80, green: 0.84, blue: 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 24)
        }
    }

    // A settings window: rounded card with traffic-light dots on a soft backdrop.
    private func settingsPoster(_ model: AppModel, scheme: ColorScheme, canvas: CGSize) -> some View {
        let cardW = canvas.width * 0.86
        let cardH = canvas.height * 0.86
        return ZStack {
            wallpaper(scheme)
            VStack(spacing: 0) {
                SettingsContentView(appModel: model)
            }
            .frame(width: cardW, height: cardH)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 34, x: 0, y: 20)
        }
    }

    // MARK: - Image tests

    func testGenerateAllReadmeImages() throws {
        try requireOptIn()
        // Render tall (SwiftUI lays out reliably at this height) then crop off the bottom dead
        // space per shot so each image frames its content tightly without clipping the header.
        let screen = CGSize(width: 1600, height: 1000)

        // 1. Fullscreen / main launcher (hero) — dark, All category.
        let main = makeModel(scheme: .dark)
        try render(fullscreenPoster(main, scheme: .dark), size: screen, scheme: .dark, cropHeight: 780, to: "main-launcher.png")

        // 2. Windowed presentation — panel floating on the desktop.
        let windowed = makeModel(scheme: .dark)
        try render(windowPoster(windowed, scheme: .dark, canvas: screen), size: screen, scheme: .dark, cropHeight: 860, to: "window-mode.png")

        // 3. Search + filter.
        let search = makeModel(scheme: .dark)
        search.searchTerm = "cal"
        try render(fullscreenPoster(search, scheme: .dark), size: screen, scheme: .dark, cropHeight: 560, to: "search-filter.png")

        // 4. Folder view — inside the "Utilities" folder (breadcrumb). Fewer columns so the
        // folder's members fill more than a single row.
        let folderModel = makeModel(scheme: .dark)
        folderModel.columnCount = 6
        if let utilities = folderModel.folders.first(where: { $0.name == "Utilities" }) {
            folderModel.openFolder(utilities.id)
        }
        try render(fullscreenPoster(folderModel, scheme: .dark), size: screen, scheme: .dark, cropHeight: 520, to: "folder-view.png")

        // 5. Recent apps section visible at root — taller crop for the extra Recent strip.
        let recent = makeModel(scheme: .dark)
        recent.showRecentApps = true
        try render(fullscreenPoster(recent, scheme: .dark), size: screen, scheme: .dark, cropHeight: 940, to: "recent-apps.png")

        // 6. Settings window (General panel).
        let settings = makeModel(scheme: .light)
        try render(settingsPoster(settings, scheme: .light, canvas: CGSize(width: 1100, height: 760)),
                   size: CGSize(width: 1100, height: 760), scheme: .light, to: "settings.png")
    }
}
