import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text("No published events yet")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("New local listings will appear here once approved.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .pccCardStyle()
    }
}
