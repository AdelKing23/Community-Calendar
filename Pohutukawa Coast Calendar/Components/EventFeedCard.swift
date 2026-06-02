import SwiftUI

struct EventFeedCard: View {
    let event: LocalEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DateTile(event: event)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(event.category.shortLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PCCTheme.pohutukawaOrange, in: Capsule())

                    if event.isPaidPush {
                        Text("Featured")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                    }

                    Spacer()

                    if event.isFree {
                        Text("Free")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PCCTheme.leafGreen, in: Capsule())
                    }
                }

                Text(event.title)
                    .font(.system(size: 21, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                Text(event.shortDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.67))
                    .lineLimit(2)
                    .lineSpacing(2)

                VStack(alignment: .leading, spacing: 6) {
                    Label(event.timeText, systemImage: "clock")
                    Label("\(event.venue), \(event.town.rawValue)", systemImage: "mappin.and.ellipse")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
            }
        }
        .padding(14)
        .pccCardStyle()
    }
}

struct DateTile: View {
    let event: LocalEvent

    var body: some View {
        VStack(spacing: 3) {
            Text(event.monthShort)
                .font(.caption2.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(event.dayNumber)
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .foregroundStyle(PCCTheme.ink)

            Text(event.weekdayShort)
                .font(.caption2.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
        }
        .frame(width: 62)
        .padding(.vertical, 11)
        .background(PCCTheme.cream.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PCCTheme.leafGreen.opacity(0.08), lineWidth: 1)
        )
    }
}
