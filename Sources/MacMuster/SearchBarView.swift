import SwiftUI

struct SearchBarView: View {
    @Bindable var appModel: AppModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField("Search applications...", text: $appModel.searchTerm)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)

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
        .padding(LayoutMetrics.searchPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LayoutMetrics.searchCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LayoutMetrics.searchCornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 400, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct SearchIconButton: View {
    @Bindable var appModel: AppModel
    @Binding var isSearchExpanded: Bool
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        Button {
            if appModel.shouldReduceMotion {
                isSearchExpanded.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { isSearchExpanded.toggle() }
            }
            if isSearchExpanded { isSearchFocused = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(isSearchExpanded || !appModel.searchTerm.isEmpty ? Color.primary : Color.secondary)
                .frame(width: LayoutMetrics.settingsButtonSize, height: LayoutMetrics.settingsButtonSize)
                .background(
                    Circle()
                        .fill(isSearchExpanded || !appModel.searchTerm.isEmpty
                              ? Color.primary.opacity(0.15)
                              : Color.clear)
                )
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: LayoutMetrics.settingsButtonSize / 2))
        .help("Search (/)")
        .accessibilityLabel("Search applications")
    }
}
