import SwiftUI

/// Slim banner across the top of the launcher when a newer release is known. Shown only while the
/// opt-in update check is on and until the user closes it for that version; see `UpdateChecker`.
struct UpdateBannerView: View {
    let release: UpdateChecker.Release

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("MacMuster \(release.version) is available")
                .font(.callout.weight(.medium))
            Spacer()
            Button("View Release") { UpdateChecker.shared.openReleasePage() }
                .buttonStyle(FocusableButtonStyle())
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            Button {
                UpdateChecker.shared.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(FocusableButtonStyle())
            .accessibilityLabel("Dismiss update notice")
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        // The launcher background dismisses the window on click; absorb near-misses.
        .contentShape(Rectangle())
        .onTapGesture { }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}
