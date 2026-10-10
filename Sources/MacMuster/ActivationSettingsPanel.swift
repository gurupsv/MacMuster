import SwiftUI
import AppKit

// MARK: - Activation Settings Panel

/// Global shortcut and hot-corner settings. Lives in its own file because `SettingsContentView`
/// is already ~1,700 lines.
struct ActivationSettingsPanel: View {
    @Bindable var appModel: AppModel
    @State private var isRecording = false
    @State private var recorder: Any?

    var body: some View {
        @Bindable var settings = appModel.settings
        return VStack(alignment: .leading, spacing: 28) {
            section(title: "Keyboard Shortcut") {
                Toggle("Open MacMuster with a global shortcut", isOn: $settings.globalHotkeyEnabled)
                HStack {
                    Text("Shortcut")
                    Spacer()
                    Button(isRecording
                           ? String(localized: "Press shortcut…")
                           : HotkeyFormatter.displayString(
                                keyCode: appModel.settings.hotkeyKeyCode,
                                modifiers: appModel.settings.hotkeyModifiers)) {
                        isRecording ? stopRecording() : startRecording()
                    }
                    .accessibilityLabel(Text("Record shortcut"))
                }
                .disabled(!appModel.settings.globalHotkeyEnabled)
                Text("Include ⌘, ⌃ or ⌥. Press Esc to cancel recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if appModel.settings.globalHotkeyEnabled && ActivationManager.shared.hotkeyRegistrationFailed {
                    Label("This shortcut is unavailable — another app may be using it.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            section(title: "Hot Corner") {
                Toggle("Open MacMuster by resting the pointer in a screen corner",
                       isOn: $settings.hotCornerEnabled)
                Picker("Corner", selection: $settings.hotCorner) {
                    ForEach(HotCorner.allCases) { corner in
                        Text(LocalizedStringKey(corner.rawValue)).tag(corner)
                    }
                }
                .disabled(!appModel.settings.hotCornerEnabled)
                Text("Applies to every display. If macOS already assigns an action to this corner in System Settings, both will fire.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func section<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionContentSpacing) {
            Text(title).font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(SettingsLayoutMetrics.sectionContentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: SettingsLayoutMetrics.sectionContentCornerRadius))
        }
    }

    private func startRecording() {
        isRecording = true
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(ActivationManager.allowedModifiers)
            let modifiers = Int(bitPattern: flags.rawValue)
            // Swallow keys without a usable modifier and keep recording.
            guard ActivationManager.isValidShortcut(modifiers: modifiers) else { return nil }
            appModel.settings.hotkeyKeyCode = Int(event.keyCode)
            appModel.settings.hotkeyModifiers = modifiers
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        isRecording = false
    }
}
