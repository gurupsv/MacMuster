# MacMuster

<div align="center">

![MacMuster](Resources/MacMusterIconLight.png)

**A beautiful, fast, and fully-featured macOS app launcher — built with Swift & SwiftUI**

[![Swift](https://img.shields.io/badge/Swift-6.2-orange?logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen)](https://github.com)

</div>

---

## 🌟 Overview

MacMuster is a **native macOS app launcher** that provides a beautiful full-screen overlay interface (similar to Launchpad) with powerful keyboard navigation, real-time search, smart categorization, folder organization, and a convenient menu bar presence.

Built entirely with **Swift 6.2** and **SwiftUI + AppKit**, MacMuster has zero external dependencies and follows modern macOS development best practices.

---

## ✨ Features

### 🚀 Core Features

| Feature | Description |
|---------|-------------|
| **Full-Screen Overlay** | Beautiful blurred backdrop with native macOS materials |
| **Keyboard Navigation** | Full arrow-key, Enter, Escape, and `/` search support |
| **Real-Time Search** | Instant filtering as you type (case-insensitive) |
| **Smart Categories** | System / User apps with automatic categorization |
| **Folder Organization** | Create, rename, delete folders; drag apps into folders |
| **Recent Apps** | Tracks last 8 launched applications |
| **Menu Bar Access** | Quick toggle from menu bar icon |
| **Multi-Monitor** | Primary screen overlay + dimmed backgrounds on other displays |

### ⚡ Performance

- **< 100ms** cold launch time
- **Lazy icon loading** with batching (12 icons/frame)
- **Incremental scanning** — only re-scans changed directories
- **LRU icon cache** (max 100 entries)
- **Release binary: 668KB** (stripped)

### 🎨 Customization

- **Grid columns**: 4–10 columns
- **Icon sizes**: Small / Medium / Large
- **Sort options**: Name (A–Z) or Installation Date
- **Font family, size, weight**: Full typography control
- **Dark/Light mode**: Automatic + manual toggle
- **Auto-refresh**: Configurable intervals (5 min – 1 hour)

### 🔒 Privacy & Security

- **Zero network calls** — completely offline
- **Local storage only** — UserDefaults for preferences
- **No analytics, no tracking**
- **Sandbox compatible** (read-only access to /Applications)

---

## 📸 Screenshots

<div align="center">

| Main Launcher | Search & Filter | Settings |
|:---:|:---:|:---:|
| ![Main](Screenshots/main-launcher.png) | ![Search](Screenshots/search-filter.png) | ![Settings](Screenshots/settings.png) |

| Folder View | Recent Apps | Dark Mode |
|:---:|:---:|:---:|
| ![Folders](Screenshots/folder-view.png) | ![Recent](Screenshots/recent-apps.png) | ![Dark](Screenshots/dark-mode.png) |

</div>

> **Note**: Screenshots are placeholders. Add actual screenshots to `Screenshots/` directory.

---

## 🛠 Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14.0 (Sonoma) or later |
| Xcode / Swift | 15.0+ / Swift 6.2 |
| Architecture | Apple Silicon (arm64) |

---

## 📦 Installation

### Option 1: Download Pre-built Release (Recommended)

1. Download `MacMuster.app` from [Releases](https://github.com/yourusername/MacMuster/releases)
2. Drag to `/Applications`
3. Right-click → **Open** (first launch only, due to ad-hoc signing)

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/MacMuster.git
cd MacMuster

# Build production release
./build_production.sh

# Install
cp -R MacMuster.app /Applications/
```

### Option 3: Development Build

```bash
# Debug build
swift build

# Run directly
swift run MacMuster
```

---

## 🚀 Usage

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑ ↓ ← →` | Navigate grid |
| `Enter` | Launch selected app |
| `Escape` | Close launcher (or unfocus search) |
| `/` | Focus search field |
| `⌘N` | Disabled (single window) |

### Menu Bar

- **Click** menu bar icon → Show/hide launcher
- **Right-click** → Quit MacMuster

### Folders

1. Right-click any app → **Add to Folder**
2. Create new folder or add to existing
3. Click folder in grid to open
4. Right-click folder → Rename / Delete

### Settings

Open via **Gear icon** in launcher or **Settings** from menu bar:
- General (start at login, refresh interval)
- Appearance (font, grid, icons)
- Hidden Apps (toggle visibility)
- App Directories (custom scan paths)

---

## 🏗 Architecture

```
MacMuster/
├── Sources/MacMuster/
│   ├── AppEntry.swift           # @main entry point
│   ├── AppDelegate.swift        # App lifecycle, singletons
│   ├── AppModel.swift           # Core state (ObservableObject)
│   ├── ContentView.swift        # Main launcher UI
│   ├── OverlayWindowManager.swift   # Full-screen window mgmt
│   ├── StatusBarManager.swift       # Menu bar icon
│   ├── SettingsWindowManager.swift  # Settings window
│   ├── SettingsContentView.swift    # Settings UI
│   ├── Constants.swift              # Magic numbers
│   ├── Services/
│   │   ├── ApplicationService.swift   # App launching
│   │   ├── ApplicationSorter.swift    # Sorting logic
│   │   └── RecentAppsService.swift    # macOS recents data
│   └── Resources/                 # Icons, assets
├── Tests/                         # Unit tests
├── Package.swift                  # SPM manifest
├── build_production.sh            # Production build script
└── create_app_bundle.sh           # Legacy bundle script
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `@Observable` + SwiftUI | Modern, performant state management |
| Hybrid AppKit/SwiftUI | Native window control + declarative UI |
| Background scanning | Non-blocking UI, 5-min refresh cycle |
| LRU icon cache (100) | Memory-bounded, fast access |
| Path-based identity | Stable `ForEach` identifiers |

---

## 🧪 Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter AppModelTests/testSearchFilterCaseInsensitive

# With coverage
swift test --enable-code-coverage
```

---

## 📦 Distribution

### For Mac App Store

1. Enable **App Sandbox** in entitlements
2. Use **Developer ID Application** certificate
3. Submit via **Transporter** / Xcode Organizer

### For Direct Distribution

```bash
# 1. Sign with Developer ID
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         --entitlements entitlements.plist \
         MacMuster.app

# 2. Notarize
xcrun notarytool submit MacMuster.app \
        --apple-id "your@email.com" \
        --team-id "TEAM123" \
        --wait

# 3. Staple ticket
xcrun stapler staple MacMuster.app
```

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- SwiftFormat + SwiftLint (run `swift format` before commit)
- `@MainActor` for all UI classes
- `@Observable` for state objects
- Comprehensive error handling

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.

---

## 🙏 Acknowledgments

- **Apple** — Swift, SwiftUI, AppKit frameworks
- **Community** — Inspiration from Alfred, Raycast, Launchpad
- **Contributors** — All who helped improve MacMuster

---

<div align="center">

**Made with ❤️ for macOS**

[Report Bug](https://github.com/yourusername/MacMuster/issues) · [Request Feature](https://github.com/yourusername/MacMuster/issues) · [Discussions](https://github.com/yourusername/MacMuster/discussions)

</div>
