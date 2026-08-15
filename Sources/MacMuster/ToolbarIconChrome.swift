import SwiftUI

/// Shared chrome for the circular icon buttons in the launcher's top-right cluster — search,
/// sort, keyboard shortcuts, new folder, settings.
///
/// Beyond collapsing five copies of the same frame/material/circle stack, this exists so hover
/// feedback is uniform across them. These buttons sit directly on the launcher background, and
/// that background dismisses the window when clicked — so a target the user cannot see until
/// after committing to the click is an expensive one to miss.
struct ToolbarIconChrome: ViewModifier {
    /// Drawn as persistently highlighted. Search uses this while the search field is open.
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    /// Active wins over hover, so an already-highlighted button doesn't flicker under the pointer.
    private var fill: Color {
        if isActive { return Color.primary.opacity(LayoutMetrics.controlActiveOpacity) }
        if isHovered { return Color.primary.opacity(LayoutMetrics.controlHoverOpacity) }
        return .clear
    }

    private var foreground: Color {
        guard isEnabled else { return .secondary }
        return (isActive || isHovered) ? .primary : .secondary
    }

    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(foreground)
            .frame(width: LayoutMetrics.settingsButtonSize, height: LayoutMetrics.settingsButtonSize)
            .background(Circle().fill(fill))
            .background(.ultraThinMaterial, in: Circle())
            // Rectangle, not Circle: the visual is a circle, but a hit shape that matched it
            // would leave the frame's corners falling through to the launcher background — which
            // dismisses the window. Claiming the whole frame turns a near-miss into a hit.
            .contentShape(Rectangle())
            .onHover { hovering in
                // A disabled button is not clickable, so advertising it as such would be a lie.
                let next = hovering && isEnabled
                guard next != isHovered else { return }
                if reduceMotion {
                    isHovered = next
                } else {
                    withAnimation(.easeInOut(duration: LayoutMetrics.controlHoverAnimationDuration)) {
                        isHovered = next
                    }
                }
            }
            .onChange(of: isEnabled) { _, nowEnabled in
                // A button disabled from under the pointer must not keep its highlight.
                if !nowEnabled { isHovered = false }
            }
    }
}

extension View {
    /// Applies the launcher's circular toolbar-icon chrome, including hover feedback.
    func toolbarIconChrome(isActive: Bool = false) -> some View {
        modifier(ToolbarIconChrome(isActive: isActive))
    }
}
