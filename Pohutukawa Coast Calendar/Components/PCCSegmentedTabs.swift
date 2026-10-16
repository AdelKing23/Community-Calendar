import SwiftUI

struct PCCSegmentedTabs: View {
    @Binding var selection: DateScope

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DateScope.allCases) { scope in
                Button {
                    selection = scope
                } label: {
                    Text(scope.chipLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == scope ? .white : PCCTheme.leafGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 24)
                        .padding(.vertical, 12)
                        .background(
                            selection == scope ? PCCTheme.leafGreen : .white.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius + 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius + 5, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        )
    }
}
