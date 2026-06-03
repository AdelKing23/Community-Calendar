import SwiftUI

struct HomePostCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(event.category.shortLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                Text(event.town.rawValue)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)

                Spacer()

                if event.isPaidPush || event.isFeatured {
                    Label("Featured", systemImage: "star.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }
            }

            EventImagePlaceholderView()

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                Text(event.shortDescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineLimit(3)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(event.dateText, systemImage: "calendar")
                Label(event.timeText, systemImage: "clock")
                Label("\(event.venue), \(event.town.rawValue)", systemImage: "mappin.and.ellipse")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.62))

            Divider()
                .overlay(PCCTheme.ink.opacity(0.12))

            EngagementActionRow(event: event)
        }
        .padding(16)
        .pccCardStyle()
    }
}

struct EventImagePlaceholderView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .fill(PCCTheme.cream.opacity(0.78))

            HStack(spacing: 12) {
                PohutukawaBloom()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pōhutukawa Coast")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Local listing")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                }
            }
        }
        .frame(height: 138)
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.82), lineWidth: 1)
        )
    }
}
