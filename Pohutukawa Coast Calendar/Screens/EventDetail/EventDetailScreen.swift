import SwiftUI

struct EventDetailScreen: View {
    let event: LocalEvent

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    EventDetailHero(event: event)
                    EventInfoPanel(event: event)
                    EventAboutPanel(event: event)
                    PublicContactNotice()
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 124)
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EventDetailHero: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.category.rawValue.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(event.title)
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)
                .lineSpacing(-1)

            Text(event.shortDescription)
                .font(.title3.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)

            if event.isPaidPush {
                Text("Featured local listing")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PCCTheme.leafGreen, in: Capsule())
            }
        }
        .padding(22)
        .pccCardStyle()
    }
}

struct EventInfoPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(spacing: 12) {
            EventInfoRow(icon: "calendar", title: "Date", value: event.dateText)
            EventInfoRow(icon: "clock", title: "Time", value: event.timeText)
            EventInfoRow(icon: "mappin.and.ellipse", title: "Venue", value: "\(event.venue), \(event.town.rawValue)")
            EventInfoRow(icon: "dollarsign.circle", title: "Cost", value: event.priceLabel)
            EventInfoRow(icon: "person.2", title: "Good for", value: event.audience)
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct EventInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.45))

                Text(value)
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink)
            }

            Spacer()
        }
    }
}

struct EventAboutPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About this event")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(event.longDescription)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct PublicContactNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Public Contact")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("Contact details are shown only after review confirms they are intended for public event enquiries.")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(PCCTheme.ink.opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}
