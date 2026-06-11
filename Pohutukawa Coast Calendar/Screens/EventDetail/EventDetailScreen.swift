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
                    if let organiserID = event.submittedBy {
                        EventOrganiserPanel(event: event, organiserID: organiserID)
                    }
                    EventAboutPanel(event: event)
                    PublicContactNotice()
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EventDetailHero: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListingRemoteImageView(
                image: event.primaryImage,
                context: "detail event=\(String(event.id.uuidString.prefix(8)))",
                contentMode: .fit
            ) {
                EventImagePlaceholderView()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 190)
            .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            HStack(alignment: .center, spacing: 10) {
                Text(event.category.rawValue.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                Spacer(minLength: 8)

                Text(event.town.rawValue)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.leafGreen.opacity(0.08), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(event.shortDescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.70))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if event.isPaidPush {
                Text("Featured local listing")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PCCTheme.leafGreen, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}

struct EventOrganiserPanel: View {
    let event: LocalEvent
    let organiserID: UUID

    var body: some View {
        NavigationLink {
            OrganiserEventsScreen(
                organiserID: organiserID,
                organiserName: event.organiserDisplayName
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(PCCTheme.leafGreen, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("More from")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.46))

                    Text(event.organiserDisplayName)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(2)

                    Text("See their upcoming listings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
            .padding(18)
            .pccCardStyle()
        }
        .buttonStyle(.plain)
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

struct OrganiserEventsScreen: View {
    let organiserID: UUID
    let organiserName: String
    private let service: PublishedEventFetching

    @State private var events: [LocalEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        organiserID: UUID,
        organiserName: String,
        service: PublishedEventFetching = SupabaseEventService()
    ) {
        self.organiserID = organiserID
        self.organiserName = organiserName
        self.service = service
    }

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    OrganiserHeaderCard(
                        organiserName: organiserName,
                        eventCount: events.count,
                        isLoading: isLoading
                    )

                    if isLoading {
                        OrganiserLoadingCard()
                    } else if let errorMessage {
                        OrganiserMessageCard(
                            icon: "wifi.exclamationmark",
                            title: "Could not load listings",
                            message: errorMessage
                        )
                    } else if events.isEmpty {
                        OrganiserMessageCard(
                            icon: "calendar.badge.clock",
                            title: "Nothing coming up yet",
                            message: "\(organiserName) has no published upcoming listings showing right now."
                        )
                    } else {
                        ForEach(dayGroups) { group in
                            OrganiserDaySection(group: group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .navigationTitle("Organiser")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEvents()
        }
        .refreshable {
            await loadEvents()
        }
    }

    private var dayGroups: [OrganiserDayGroup] {
        let calendar = Calendar.current
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        let groupedByDay = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }

        return groupedByDay.keys.sorted().map { day in
            let dayEvents = groupedByDay[day, default: []]
            let buckets = OrganiserTimeBucket.allCases.compactMap { bucket -> OrganiserEventBucket? in
                let bucketEvents = dayEvents.filter { bucket.contains($0.startDate) }
                guard !bucketEvents.isEmpty else { return nil }
                return OrganiserEventBucket(kind: bucket, events: bucketEvents)
            }

            return OrganiserDayGroup(date: day, buckets: buckets)
        }
    }

    @MainActor
    private func loadEvents() async {
        isLoading = true
        errorMessage = nil

        do {
            events = try await service.fetchPublishedEvents(submittedBy: organiserID)
                .sorted { $0.startDate < $1.startDate }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

struct OrganiserHeaderCard: View {
    let organiserName: String
    let eventCount: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(PCCTheme.leafGreen)

                VStack(alignment: .leading, spacing: 7) {
                    Text(organiserName)
                        .font(.system(size: 31, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Upcoming listings, soonest first")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.64))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Label(isLoading ? "Loading" : "\(eventCount) upcoming", systemImage: "calendar")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                Label("Tap a card for details", systemImage: "hand.tap")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}

struct OrganiserDaySection: View {
    let group: OrganiserDayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            ForEach(group.buckets) { bucket in
                VStack(alignment: .leading, spacing: 10) {
                    Label(bucket.kind.title, systemImage: bucket.kind.icon)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)

                    ForEach(bucket.events) { event in
                        NavigationLink {
                            EventDetailScreen(event: event)
                        } label: {
                            EventFeedCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct OrganiserLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(PCCTheme.leafGreen)

            Text("Finding their upcoming listings...")
                .font(.body.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))

            Spacer()
        }
        .padding(20)
        .pccCardStyle()
    }
}

struct OrganiserMessageCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(title)
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .pccCardStyle()
    }
}

struct OrganiserDayGroup: Identifiable {
    let date: Date
    let buckets: [OrganiserEventBucket]

    var id: Date { date }

    var title: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct OrganiserEventBucket: Identifiable {
    let kind: OrganiserTimeBucket
    let events: [LocalEvent]

    var id: OrganiserTimeBucket { kind }
}

enum OrganiserTimeBucket: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .later: return "Later"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "sunset"
        case .later: return "moon.stars"
        }
    }

    func contains(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)

        switch self {
        case .morning:
            return (5..<12).contains(hour)
        case .afternoon:
            return (12..<17).contains(hour)
        case .evening:
            return (17..<22).contains(hour)
        case .later:
            return hour < 5 || hour >= 22
        }
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
