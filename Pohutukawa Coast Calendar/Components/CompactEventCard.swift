import SwiftUI

struct CompactEventCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ListingRemoteImageView(
                image: event.primaryImage,
                context: "compact event=\(String(event.id.uuidString.prefix(8)))",
                contentMode: .fill
            ) {
                if event.isPoll {
                    PollImagePlaceholderView()
                } else {
                    EventImagePlaceholderView()
                }
            }
            .frame(height: 58)
            .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            HStack {
                Text(event.monthShort)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                Text(event.dayNumber)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Spacer()

                if event.isPoll {
                    Text("Poll")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PCCTheme.leafGreen, in: Capsule())
                } else {
                    Text(event.category.shortLabel)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }

            Text(event.organiserDisplayName)
                .font(.system(size: 15, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)
                .lineLimit(1)

            Text(event.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.78))
                .lineLimit(2)

            Spacer(minLength: 0)

            Text(event.startDate.formatted(.dateTime.hour().minute()))
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))

            Text(event.isPoll ? "Closes \(event.dateText)" : event.venue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 188)
        .padding(13)
        .pccCardStyle()
    }
}
