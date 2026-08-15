import SwiftUI

struct CategoryTabButton: View {
    @Bindable var appModel: AppModel
    let category: AppCategory

    @State private var isHovered = false

    private var count: Int { appModel.categoryCounts[category, default: 0] }
    private var isSelected: Bool { appModel.selectedCategory == category }
    private var isEnabled: Bool { count > 0 }

    /// Selected wins over hover; an unselected tab under the pointer gets a faint tint so the
    /// clickable pill is visible *before* the click rather than only after it.
    private var capsuleFill: Color {
        if isSelected { return Color.primary.opacity(0.9) }
        if isHovered { return Color.primary.opacity(LayoutMetrics.controlHoverOpacity) }
        return .clear
    }

    private var labelColor: Color {
        if isSelected { return Color(nsColor: .windowBackgroundColor) }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appModel.selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(isSelected
                                     ? Color(nsColor: .windowBackgroundColor).opacity(0.7)
                                     : Color.secondary)
            }
            .padding(.horizontal, LayoutMetrics.categoryTabPaddingHorizontal)
            .padding(.vertical, LayoutMetrics.categoryTabPaddingVertical)
            .background(Capsule().fill(capsuleFill))
            .foregroundStyle(labelColor)
            // Without this the transparent parts of an unselected pill are not reliably
            // hit-tested, so a click lands on the launcher background — which dismisses.
            .contentShape(Capsule())
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: 16))
        .disabled(!isEnabled)
        .onHover { hovering in
            // A disabled tab is not clickable, so advertising it as such would be a lie.
            let next = hovering && isEnabled
            guard next != isHovered else { return }
            if appModel.shouldReduceMotion {
                isHovered = next
            } else {
                withAnimation(.easeInOut(duration: LayoutMetrics.controlHoverAnimationDuration)) {
                    isHovered = next
                }
            }
        }
        .onChange(of: isEnabled) { _, nowEnabled in
            // A tab that empties out from under the pointer must not keep its highlight.
            if !nowEnabled { isHovered = false }
        }
    }
}
