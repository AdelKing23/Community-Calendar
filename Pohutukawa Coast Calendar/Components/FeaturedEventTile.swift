import SwiftUI

struct FeaturedEventTile: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(event.category.shortLabel.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                Spacer()

                if event.isPaidPush {
                    Image(systemName: "star.fill")
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }
            }

            Text(event.title)
                .font(.system(size: 19, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)
                .lineLimit(2)

            Spacer()

            Text(event.dayText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.74))

            Text(event.venue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.55))
                .lineLimit(1)
        }
        .frame(width: 215, height: 145)
        .padding(16)
        .pccCardStyle()
    }
}
