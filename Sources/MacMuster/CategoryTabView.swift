import SwiftUI

struct CategoryTabButton: View {
    @Bindable var appModel: AppModel
    let category: AppCategory

    var body: some View {
        let isSelected = appModel.selectedCategory == category
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appModel.selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(appModel.categoryCounts[category, default: 0])")
                    .font(.caption)
                    .foregroundStyle(isSelected
                                     ? Color(nsColor: .windowBackgroundColor).opacity(0.7)
                                     : Color.secondary)
            }
            .padding(.horizontal, LayoutMetrics.categoryTabPaddingHorizontal)
            .padding(.vertical, LayoutMetrics.categoryTabPaddingVertical)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary.opacity(0.9) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
        }
        .buttonStyle(FocusableButtonStyle(cornerRadius: 16))
        .disabled((appModel.categoryCounts[category, default: 0]) == 0)
    }
}
