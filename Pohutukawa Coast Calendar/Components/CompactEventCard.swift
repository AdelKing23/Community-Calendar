import SwiftUI

struct CompactEventCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(event.monthShort)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                Text(event.dayNumber)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Spacer()

                Text(event.category.shortLabel)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
            }

            Text(event.title)
                .font(.system(size: 16, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)
                .lineLimit(2)

            Spacer(minLength: 0)

            Text(event.startDate.formatted(.dateTime.hour().minute()))
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))

            Text(event.venue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                .lineLimit(1)
        }
        .frame(width: 164, height: 132)
        .padding(13)
        .pccCardStyle()
    }
}
