import SwiftUI

struct HomePostCard: View {
    let event: LocalEvent
    var showsEngagement: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                if event.isPoll {
                    PollBadge()
                }

                Text(event.category.shortLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                Text(event.displayLocationName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)

                Spacer()

                if event.isPromoted || event.isFeatured {
                    Label(event.isPromoted ? event.promotionBadgeTitle : "Featured", systemImage: "star.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }
            }

            ListingRemoteImageView(
                image: event.primaryImage,
                context: "home event=\(String(event.id.uuidString.prefix(8)))",
                contentMode: .fill
            ) {
                EventImagePlaceholderView()
            }
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(event.organiserDisplayName)
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(1)

                Text(event.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.84))
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
                Label("\(event.venue), \(event.displayLocationName)", systemImage: "mappin.and.ellipse")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.62))

            if let pollDetails = event.pollDetails {
                PollInlineResponseView(event: event, pollDetails: pollDetails)
            }

            if showsEngagement {
                Divider()
                    .overlay(PCCTheme.ink.opacity(0.12))
                EngagementActionRow(event: event)
            }
        }
        .padding(16)
        .modifier(PCCOptionalCardStyle(enabled: showsEngagement))
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
        .frame(maxWidth: .infinity, minHeight: 138)
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.82), lineWidth: 1)
        )
    }
}

struct PollImagePlaceholderView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .fill(PCCTheme.leafGreen.opacity(0.10))

            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(PCCTheme.leafGreen, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Community poll")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Have your say")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 138)
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.82), lineWidth: 1)
        )
    }
}


private struct PCCOptionalCardStyle: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.pccCardStyle()
        } else {
            content
        }
    }
}
