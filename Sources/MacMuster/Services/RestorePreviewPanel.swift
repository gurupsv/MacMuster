import AppKit
import SwiftUI

@MainActor
class RestorePreviewPanel: NSObject {
    private var window: NSWindow?
    private let resultSemaphore = DispatchSemaphore(value: 0)
    private var _result = Int(NSApplication.ModalResponse.cancel.rawValue)

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
            self?.complete(with: NSApplication.ModalResponse.OK)
        }
        let onCancel: () -> Void = { [weak self] in
            self?.complete(with: NSApplication.ModalResponse.cancel)
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
        window?.title = "Restore Preview"
        window?.isRestorable = false
        window?.hasShadow = true
        window?.level = .floating
        window?.isReleasedWhenClosed = false
        window?.contentView = hostingView
        window?.minSize = NSSize(width: 500, height: 350)
    }

    func runModal() -> Int {
        guard let window else { return NSApplication.ModalResponse.cancel.rawValue }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        resultSemaphore.wait()
        return _result
    }

    private func complete(with result: NSApplication.ModalResponse) {
        _result = Int(result.rawValue)
        resultSemaphore.signal()
        window?.orderOut(nil)
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
                        Text("\(missingCount) app(s) will be skipped (not found on disk):")
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