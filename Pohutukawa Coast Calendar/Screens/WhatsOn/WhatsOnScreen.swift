import SwiftUI

struct WhatsOnScreen: View {
    @AppStorage("communityCalendar.whatsOn.selectedTopic") private var selectedTopicID = ListingTopic.all.rawValue
    @State private var selectedScope: DateScope = .today
    @State private var selectedTown: CoastTown = .all
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let eventService: PublishedEventFetching = SupabaseEventService()

    private var visibleEvents: [LocalEvent] {
        let today = Calendar.current.startOfDay(for: Date())

        return events
            .filter { event in
                switch selectedScope {
                case .today:
                    return selectedScope.matches(event)
                case .thisWeek:
                    return selectedScope.matches(event) && event.startDate >= today
                case .thisMonth:
                    return selectedScope.matches(event) && event.startDate >= today
                }
            }
            .filter { selectedTown == .all || $0.town == selectedTown }
            .filter { $0.matches(topic: selectedTopic) }
            .sorted {
                if $0.isPaidPush != $1.isPaidPush {
                    return $0.isPaidPush && !$1.isPaidPush
                }
                return $0.startDate < $1.startDate
            }
    }

    private var selectedTopic: ListingTopic {
        ListingTopic(rawValue: selectedTopicID) ?? .all
    }

    private var featuredEvents: [LocalEvent] {
        events
            .filter { $0.isFeatured || $0.isPaidPush }
            .sorted {
                if $0.isPaidPush != $1.isPaidPush {
                    return $0.isPaidPush && !$1.isPaidPush
                }
                return $0.startDate < $1.startDate
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        WhatsOnHeader(eventCount: visibleEvents.count)
                            .padding(.top, 4)

                        PCCSegmentedTabs(selection: $selectedScope)

                        TopicPickerRow(selectedTopicID: $selectedTopicID)

                        TownPickerRow(selectedTown: $selectedTown)

                        if isLoading {
                            LoadingEventsCard()
                        } else if let loadError {
                            FeedMessageCard(
                                icon: "wifi.exclamationmark",
                                title: "Events could not be loaded",
                                message: loadError
                            ) {
                                Task { await loadEvents() }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(feedTitle)
                                        .font(.title2.weight(.black))
                                        .foregroundStyle(PCCTheme.ink)

                                    Spacer()

                                    Text("\(visibleEvents.count)")
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(PCCTheme.pohutukawaOrange, in: Capsule())
                                }

                                ScopedEventsContent(scope: selectedScope, events: visibleEvents)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.standardBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationBarHidden(true)
        }
        .pccDismissesKeyboardOnTap()
        .task {
            await loadEvents()
        }
        .refreshable {
            await loadEvents()
        }
    }

    private var feedTitle: String {
        let topicPrefix = selectedTopic == .all ? "" : "\(selectedTopic.shortLabel) · "

        switch selectedScope {
        case .today: return "\(topicPrefix)What's On Today"
        case .thisWeek: return "\(topicPrefix)This Week"
        case .thisMonth: return "\(topicPrefix)This Month"
        }
    }

    @MainActor
    private func loadEvents() async {
        isLoading = events.isEmpty
        loadError = nil

        do {
            events = try await eventService.fetchPublishedEvents()
                .filter(\.isPubliclyVisible)
            isLoading = false
        } catch {
            isLoading = false
            loadError = "Please try again soon."
        }
    }
}

struct WhatsOnHeader: View {
    let eventCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's On")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Find events by today, week or month.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("\(eventCount)")
                        .font(.title2.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("events")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }
                .padding(13)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
        }
        .padding(20)
        .pccCardStyle()
    }
}

struct ScopedEventsContent: View {
    let scope: DateScope
    let events: [LocalEvent]

    var body: some View {
        if events.isEmpty {
            FeedMessageCard(
                icon: "calendar",
                title: emptyTitle,
                message: emptyMessage,
                retry: nil
            )
        } else {
            switch scope {
            case .today:
                VStack(spacing: 12) {
                    ForEach(events) { event in
                        NavigationLink {
                            EventDetailScreen(event: event)
                        } label: {
                            EventFeedCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .thisWeek, .thisMonth:
                CompactEventsOverview(events: events)
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "Nothing published for today yet"
        case .thisWeek: return "No events published this week yet"
        case .thisMonth: return "No events published this month yet"
        }
    }

    private var emptyMessage: String {
        "Approved local listings will appear here."
    }
}

struct CompactEventsOverview: View {
    let events: [LocalEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groupedDays, id: \.day) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.day)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(group.events) { event in
                                NavigationLink {
                                    EventDetailScreen(event: event)
                                } label: {
                                    CompactEventCard(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 20)
                    }
                }
            }
        }
    }

    private var groupedDays: [(day: String, events: [LocalEvent])] {
        let grouped = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.startDate)
        }

        return grouped.keys.sorted().map { day in
            (
                day: day.formatted(.dateTime.weekday(.wide).month().day()),
                events: grouped[day, default: []].sorted { $0.startDate < $1.startDate }
            )
        }
    }
}

struct TownPickerRow: View {
    @Binding var selectedTown: CoastTown

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CoastTown.allCases) { town in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            selectedTown = town
                        }
                    } label: {
                        Text(town.rawValue)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(selectedTown == town ? .white : PCCTheme.leafGreen)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(
                                selectedTown == town ? PCCTheme.pohutukawaOrange : .white.opacity(0.76),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TopicPickerRow: View {
    @Binding var selectedTopicID: String

    private var selectedTopic: ListingTopic {
        ListingTopic(rawValue: selectedTopicID) ?? .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Browse by topic")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.64))

                Spacer()

                if selectedTopic != .all {
                    Button("Clear") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            selectedTopicID = ListingTopic.all.rawValue
                        }
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ListingTopic.allCases) { topic in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                selectedTopicID = topic.rawValue
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: topic.icon)
                                    .font(.caption.weight(.black))

                                Text(topic.shortLabel)
                                    .font(.subheadline.weight(.heavy))
                            }
                            .foregroundStyle(selectedTopic == topic ? .white : PCCTheme.leafGreen)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                selectedTopic == topic ? PCCTheme.pohutukawaOrange : .white.opacity(0.76),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 20)
            }
        }
    }
}

struct HappeningSoonStrip: View {
    let events: [LocalEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Happening Soon")
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(events) { event in
                            NavigationLink {
                                EventDetailScreen(event: event)
                            } label: {
                                FeaturedEventTile(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct LoadingEventsCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PCCTheme.pohutukawaOrange)

            Text("Loading local events")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .pccCardStyle()
    }
}

struct FeedMessageCard: View {
    let icon: String
    let title: String
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .multilineTextAlignment(.center)

            if let retry {
                Button(action: retry) {
                    Text("Try Again")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(PCCTheme.leafGreen, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .pccCardStyle()
    }
}
