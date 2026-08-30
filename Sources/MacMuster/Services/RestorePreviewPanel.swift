import AppKit
import SwiftUI

@MainActor
class RestorePreviewPanel: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<NSApplication.ModalResponse, Never>?

    let folderCount: Int
    let appCount: Int
    let missingCount: Int
    let missingPaths: [String]

    init(
        folderCount: Int,
        appCount: Int,
        missingCount: Int,
        missingPaths: [String]
    ) {
        self.folderCount = folderCount
        self.appCount = appCount
        self.missingCount = missingCount
        self.missingPaths = missingPaths
        super.init()

        let onApply: () -> Void = { [weak self] in
            self?.complete(with: .OK)
        }
        let onCancel: () -> Void = { [weak self] in
            self?.complete(with: .cancel)
        }

        let contentView = RestorePreviewView(
            folderCount: folderCount,
            appCount: appCount,
            missingCount: missingCount,
            missingPaths: missingPaths,
            onApply: onApply,
            onCancel: onCancel
        )

        let hostingView = NSHostingView(rootView: contentView)

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first).map(\.visibleFrame) ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowX = screenFrame.midX - 320
        let windowY = screenFrame.midY - 240

        window = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window?.title = String(localized: "Restore Preview")
        window?.isRestorable = false
        window?.hasShadow = true
        window?.level = .floating
        window?.isReleasedWhenClosed = false
        window?.contentView = hostingView
        window?.minSize = NSSize(width: 500, height: 350)
        // The style mask includes .closable, so the title-bar button can dismiss this window
        // without going through either of the buttons above. Without a delegate to notice that,
        // `runModal`'s continuation was never resumed and the restore flow hung for the rest of
        // the session (and Swift would warn about a leaked continuation).
        window?.delegate = self
    }

    /// Closing via the title-bar button is a cancel. Routed through `complete` so it cannot
    /// double-resume if a button was clicked first — `complete` clears the continuation.
    func windowWillClose(_ notification: Notification) {
        complete(with: .cancel)
    }

    /// True while `runModal` is suspended waiting for a response. Lets a caller — in practice a
    /// test — wait for the continuation to be installed rather than racing it.
    var isAwaitingResponse: Bool { continuation != nil }

    /// Whether the window will actually route its close button back to this object. Exposed
    /// because calling `windowWillClose` directly proves only that the handler works, not that
    /// AppKit would ever call it — the bug was the missing wiring, not the handler.
    var handlesWindowClose: Bool { window?.delegate === self }

    func runModal() async -> NSApplication.ModalResponse {
        guard let window else { return .cancel }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }

    /// Resolves `runModal` exactly once, whichever way the panel was dismissed — Apply, Cancel,
    /// or the title-bar close button. Taking the continuation before resuming makes a second
    /// call a no-op, which matters now that `windowWillClose` is also a completion path: clicking
    /// Cancel orders the window out, and that can deliver the close notification too.
    private func complete(with result: NSApplication.ModalResponse) {
        guard let pending = continuation else { return }
        continuation = nil
        window?.orderOut(nil)
        pending.resume(returning: result)
    }
}

struct RestorePreviewView: View {
    let folderCount: Int
    let appCount: Int
    let missingCount: Int
    let missingPaths: [String]
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Preview")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text("Folders to restore: \(folderCount)")
                }
                HStack {
                    Image(systemName: "app")
                        .foregroundStyle(.secondary)
                    Text("Valid apps to restore: \(appCount)")
                }
            }

            if !missingPaths.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(String(localized: "\(missingCount) app(s) will be skipped (not found on disk):"))
                            .font(.system(size: 13, weight: .medium))
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(missingPaths, id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply Restore", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
