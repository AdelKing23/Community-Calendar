import SwiftUI

struct WhatsOnScreen: View {
    @AppStorage("communityCalendar.whatsOn.selectedTopic") private var selectedTopicID = ListingTopic.all.rawValue
    @AppStorage("communityCalendar.whatsOn.locationScope") private var selectedLocationScopeID = LocationScope.defaultID
    @AppStorage("communityCalendar.whatsOn.locationFocusScope") private var focusedLocationScopeID = LocationScope.defaultID
    @State private var selectedScope: DateScope = .today
    @State private var isShowingLocationFinder = false
    @State private var locationCatalog = LocationCatalog.local
    @State private var hasLoadedLocationCatalog = false
    @State private var isUsingBackendLocationFilter = false
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let eventService: PublishedEventFetching & LocationScopeFetching = SupabaseEventService()

    private var selectedLocationScope: LocationScope {
        locationCatalog.defaultScope(for: selectedLocationScopeID)
    }

    private var selectedLocationLadder: [LocationScope] {
        locationCatalog.displayLadder(selectedID: selectedLocationScopeID, focusID: focusedLocationScopeID)
    }

    private var selectedLocationWideningOptions: [LocationScope] {
        locationCatalog.wideningOptions(selectedID: selectedLocationScopeID, focusID: focusedLocationScopeID)
    }

    private var visibleEvents: [LocalEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        let locationScope = selectedLocationScope

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
            .filter { isUsingBackendLocationFilter || locationScope.matches($0) }
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

                        LocationScopeControl(
                            selectedScope: selectedLocationScope,
                            displayLadder: selectedLocationLadder,
                            eventCount: visibleEvents.count,
                            onChange: { isShowingLocationFinder = true },
                            onSelectScope: selectLocationScope
                        )

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

                                ScopedEventsContent(
                                    scope: selectedScope,
                                    locationScope: selectedLocationScope,
                                    wideningOptions: selectedLocationWideningOptions,
                                    events: visibleEvents,
                                    onSelectLocationScope: selectLocationScope
                                )
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
        .task(id: selectedLocationScopeID) {
            await loadEvents()
        }
        .refreshable {
            await loadEvents()
        }
        .sheet(isPresented: $isShowingLocationFinder) {
            LocationFinderSheet(
                selectedScope: selectedLocationScope,
                displayLadder: selectedLocationLadder,
                locationCatalog: locationCatalog,
                onSelectScope: { scope in
                    selectLocationScope(scope)
                    isShowingLocationFinder = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    private func selectLocationScope(_ scope: LocationScope) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            if selectedLocationLadder.contains(where: { $0.id == scope.id }) {
                focusedLocationScopeID = selectedLocationLadder.first?.id ?? scope.id
            } else {
                focusedLocationScopeID = scope.id
            }
            selectedLocationScopeID = scope.id
        }
    }

    @MainActor
    private func loadEvents() async {
        isLoading = events.isEmpty
        loadError = nil

        do {
            if !hasLoadedLocationCatalog {
                locationCatalog = (try? await eventService.fetchLocationCatalog()) ?? .local
                hasLoadedLocationCatalog = true
            }

            do {
                events = try await eventService.fetchPublishedEvents(locationScopeID: selectedLocationScope.id)
                    .filter(\.isPubliclyVisible)
                isUsingBackendLocationFilter = true
            } catch {
                events = try await eventService.fetchPublishedEvents()
                    .filter(\.isPubliclyVisible)
                isUsingBackendLocationFilter = false
            }
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
    let locationScope: LocationScope
    let wideningOptions: [LocationScope]
    let events: [LocalEvent]
    let onSelectLocationScope: (LocationScope) -> Void

    var body: some View {
        if events.isEmpty {
            EmptyScopedEventsCard(
                title: emptyTitle,
                message: emptyMessage,
                wideningOptions: Array(wideningOptions.prefix(3)),
                onSelectLocationScope: onSelectLocationScope
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
        "No approved listings are showing in \(locationScope.name) for this date range. Try widening the area."
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

struct LocationScopeControl: View {
    let selectedScope: LocationScope
    let displayLadder: [LocationScope]
    let eventCount: Int
    let onChange: () -> Void
    let onSelectScope: (LocationScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onChange) {
                HStack(spacing: 12) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(PCCTheme.leafGreen, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Showing \(selectedScope.name)")
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.ink)

                        Text("\(selectedScope.kind.rawValue) · \(eventCount) listing\(eventCount == 1 ? "" : "s")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
                .padding(14)
                .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayLadder) { scope in
                        Button {
                            onSelectScope(scope)
                        } label: {
                            Text(scope.name)
                                .font(.caption.weight(.black))
                                .foregroundStyle(scope.id == selectedScope.id ? .white : PCCTheme.leafGreen)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    scope.id == selectedScope.id ? PCCTheme.pohutukawaOrange : .white.opacity(0.74),
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

struct LocationFinderSheet: View {
    let selectedScope: LocationScope
    let displayLadder: [LocationScope]
    let locationCatalog: LocationCatalog
    let onSelectScope: (LocationScope) -> Void

    @State private var query = ""

    private var results: [LocationScope] {
        let matches = locationCatalog.scopes.filter { $0.matchesSearch(query) }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return locationCatalog.quickScopes + locationCatalog.scopes.filter { scope in
                !locationCatalog.quickScopes.contains(scope)
            }
        }
        return matches
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCTheme.cream.opacity(0.55).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Find events near...")
                                .font(.system(size: 32, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Start specific, then widen when you want more options.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(PCCTheme.ink.opacity(0.52))

                            TextField("Search place or area", text: $query)
                                .font(.body.weight(.bold))
                                .textInputAutocapitalization(.words)

                            if !query.isEmpty {
                                Button {
                                    query = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(PCCTheme.ink.opacity(0.38))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                        LocationLadderPreview(
                            selectedScope: selectedScope,
                            displayLadder: displayLadder,
                            onSelectScope: onSelectScope
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text(query.isEmpty ? "Quick areas" : "Matches")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.58))

                            if results.isEmpty {
                                LocationNoMatchesCard(
                                    query: query,
                                    fallbackScopes: fallbackScopes,
                                    onSelectScope: onSelectScope
                                )
                            } else {
                                ForEach(results) { scope in
                                    LocationScopeResultRow(
                                        scope: scope,
                                        displayLadder: locationCatalog.ladder(for: scope.id),
                                        isSelected: scope.id == selectedScope.id,
                                        onSelect: { onSelectScope(scope) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 26)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var fallbackScopes: [LocationScope] {
        [
            locationCatalog.scope(id: LocationScope.defaultID),
            locationCatalog.scope(id: "auckland"),
            locationCatalog.scope(id: "new-zealand")
        ]
        .compactMap { $0 }
        .uniquedByID()
    }
}

struct LocationLadderPreview: View {
    let selectedScope: LocationScope
    let displayLadder: [LocationScope]
    let onSelectScope: (LocationScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current ladder")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayLadder) { item in
                        Button {
                            onSelectScope(item)
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .lineLimit(1)

                                if item.id != displayLadder.last?.id {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.black))
                                }
                            }
                            .font(.caption.weight(.black))
                            .foregroundStyle(item.id == selectedScope.id ? .white : PCCTheme.leafGreen)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(item.id == selectedScope.id ? PCCTheme.pohutukawaOrange : .white.opacity(0.78), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 18)
            }
        }
        .padding(14)
        .background(PCCTheme.leafGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct LocationScopeResultRow: View {
    let scope: LocationScope
    let displayLadder: [LocationScope]
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.black))
                    .foregroundStyle(isSelected ? .white : PCCTheme.leafGreen)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? PCCTheme.leafGreen : PCCTheme.leafGreen.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.name)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(scope.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        .lineLimit(2)

                    Text(displayLadder.map(\.name).joined(separator: "  →  "))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PCCTheme.pohutukawaOrange.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .padding(13)
            .background(.white.opacity(isSelected ? 0.92 : 0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch scope.kind {
        case .place: return "mappin.and.ellipse"
        case .community: return "person.3.fill"
        case .widerArea: return "arrow.up.left.and.arrow.down.right"
        case .region: return "map.fill"
        case .country: return "globe.asia.australia.fill"
        }
    }
}

struct LocationNoMatchesCard: View {
    let query: String
    let fallbackScopes: [LocationScope]
    let onSelectScope: (LocationScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .frame(width: 32, height: 32)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("No exact place yet")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Try a wider area while this place is added to the location catalog.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.60))
                        .lineSpacing(2)
                }
            }

            if !fallbackScopes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fallbackScopes) { scope in
                            Button {
                                onSelectScope(scope)
                            } label: {
                                Text(scope.name)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(PCCTheme.leafGreen, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No exact match for \(query). Try a wider area.")
    }
}

private extension Array where Element == LocationScope {
    func uniquedByID() -> [LocationScope] {
        var seenIDs: Set<String> = []
        return filter { scope in
            seenIDs.insert(scope.id).inserted
        }
    }
}

struct EmptyScopedEventsCard: View {
    let title: String
    let message: String
    let wideningOptions: [LocationScope]
    let onSelectLocationScope: (LocationScope) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .multilineTextAlignment(.center)

            if !wideningOptions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(wideningOptions) { scope in
                        Button {
                            onSelectLocationScope(scope)
                        } label: {
                            Text(scope.name)
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(PCCTheme.leafGreen, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .pccCardStyle()
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
