import SwiftUI

struct PCCSegmentedTabs: View {
    @Binding var selection: DateScope

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DateScope.allCases) { scope in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        selection = scope
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == scope ? .white : PCCTheme.leafGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selection == scope ? PCCTheme.leafGreen : .white.opacity(0.78),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
    }
}
