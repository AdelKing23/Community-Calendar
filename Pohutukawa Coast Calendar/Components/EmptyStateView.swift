import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text("It’s a quiet time right now")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("List something to be the first thing this week.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .pccCardStyle()
    }
}
