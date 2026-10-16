import SwiftUI

struct WhatsOnScreen: View {
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var locationPreferenceStore: UserLocationPreferenceStore
    @AppStorage("communityCalendar.whatsOn.selectedTopic") private var selectedTopicID = "All"
    @AppStorage("communityCalendar.whatsOn.locationScope") private var selectedLocationScopeID = LocationScope.defaultID
    @AppStorage("communityCalendar.whatsOn.locationFocusScope") private var focusedLocationScopeID = LocationScope.defaultID
    @AppStorage("communityCalendar.whatsOn.favoriteLocationScope") private var favoriteLocationScopeID = ""
    @State private var selectedScope: DateScope = .today
    @State private var isShowingLocationFinder = false
    @State private var locationCatalog = LocationCatalog.local
    @State private var hasLoadedLocationCatalog = false
    @State private var isUsingBackendLocationFilter = false
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var openedEventID: UUID?

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
        let locationScope = selectedLocationScope

        return events
            .filter { event in
                selectedScope.matches(event)
            }
            .filter { isUsingBackendLocationFilter || locationScope.matches($0) }
            .filter { $0.matches(topic: selectedTopic) }
            .sorted(by: EventFeedOrdering.discovery)
    }

    private var selectedTopic: EventCategory? {
        EventCategory(rawValue: selectedTopicID)
    }

    private var featuredEvents: [LocalEvent] {
        events
            .filter { $0.isFeatured || $0.isPromoted }
            .sorted(by: EventFeedOrdering.discovery)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                List {
                    WhatsOnHeader(reminderCount: reminderStore.activeReminderCount)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 76, leading: 16, bottom: 12, trailing: 16))

                    PCCSegmentedTabs(selection: $selectedScope)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    TopicPickerRow(selectedTopicID: $selectedTopicID)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    LocationScopeControl(
                        selectedScope: selectedLocationScope,
                        displayLadder: selectedLocationLadder,
                        eventCount: visibleEvents.count,
                        isFavorite: selectedLocationScope.id == favoriteLocationScopeID,
                        favoriteScope: locationCatalog.defaultScope(for: favoriteLocationScopeID),
                        locationMessage: locationPreferenceStore.locationMessage,
                        onChange: { isShowingLocationFinder = true },
                        onSelectScope: selectLocationScope,
                        onSaveFavorite: {
                            if favoriteLocationScopeID == selectedLocationScope.id {
                                favoriteLocationScopeID = ""
                            } else {
                                favoriteLocationScopeID = selectedLocationScope.id
                                locationPreferenceStore.saveFavorite(scope: selectedLocationScope)
                            }
                        },
                        onUseFavorite: {
                            selectLocationScope(locationCatalog.defaultScope(for: favoriteLocationScopeID))
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    if isLoading {
                        LoadingEventsCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    } else if let loadError {
                        FeedMessageCard(
                            icon: "wifi.exclamationmark",
                            title: "Events could not be loaded",
                            message: loadError
                        ) {
                            Task { await loadEvents() }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        HStack {
                            Text(feedTitle)
                                .pccScreenTitleStyle()

                            Spacer()

                            Text("\(visibleEvents.count)")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(PCCTheme.pohutukawaOrange, in: Capsule())
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        if visibleEvents.isEmpty {
                            EmptyScopedEventsCard(
                                title: {
                                    switch selectedScope {
                                    case .today: return "Nothing scheduled here today"
                                    case .thisWeek: return "A quiet week in this area"
                                    case .thisMonth: return "No listings match this month"
                                    case .upcoming: return "Nothing coming up in this area"
                                    }
                                }(),
                                message: "Try a wider area or another topic to discover more around \(selectedLocationScope.name).",
                                wideningOptions: Array(selectedLocationWideningOptions.prefix(3)),
                                onSelectLocationScope: selectLocationScope
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 176, trailing: 16))
                        } else {
                            CompactEventsOverview(events: visibleEvents, onOpen: { openedEventID = $0 })
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 176, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { openedEventID != nil },
                set: { if !$0 { openedEventID = nil } }
            )) {
                if let event = events.first(where: { $0.id == openedEventID }) {
                    EventDetailScreen(event: event)
                }
            }
        }
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
        let topicPrefix = selectedTopic.map { "\($0.shortLabel) · " } ?? ""

        switch selectedScope {
        case .today: return "\(topicPrefix)What's On Today"
        case .thisWeek: return "\(topicPrefix)This Week"
        case .thisMonth: return "\(topicPrefix)This Month"
        case .upcoming: return "\(topicPrefix)Upcoming"
        }
    }

    private func selectLocationScope(_ scope: LocationScope) {
        LocationRecentScopeStore.record(scope)

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
    let reminderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    headerText
                    Spacer(minLength: 8)
                    reminderBadge
                }

                VStack(alignment: .leading, spacing: 14) {
                    headerText
                    reminderBadge
                }
            }
        }
        .padding(20)
        .pccCardStyle()
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's On")
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            Text("Make a plan, discover something local, and never miss a good day out.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reminderBadge: some View {
        HStack(spacing: 9) {
            Image(systemName: reminderCount > 0 ? "alarm.waves.left.and.right.fill" : "alarm")
                .font(.headline.weight(.black))
                .foregroundStyle(reminderCount > 0 ? PCCTheme.pohutukawaOrange : PCCTheme.ink)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(reminderCount)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(reminderCount == 1 ? "reminder" : "reminders")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
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
            case .today, .upcoming:
                VStack(spacing: 12) {
                    ForEach(events) { event in
                        if event.isPoll {
                            PollFeedCard(event: event)
                        } else {
                            NavigationLink {
                                EventDetailScreen(event: event)
                            } label: {
                                EventFeedCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            case .thisWeek, .thisMonth:
                CompactEventsOverview(events: events)
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "Nothing scheduled here today"
        case .thisWeek: return "A quiet week in this area"
        case .thisMonth: return "No listings match this month"
        case .upcoming: return "Nothing coming up in this area"
        }
    }

    private var emptyMessage: String {
        "Try a wider area or another topic to discover more around \(locationScope.name)."
    }
}

struct CompactEventsOverview: View {
    let events: [LocalEvent]
    var onOpen: (UUID) -> Void = { _ in }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedDays, id: \.day) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.day)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.screenSectionTitle)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.events) { event in
                            Button {
                                onOpen(event.id)
                            } label: {
                                CompactEventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
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
    let isFavorite: Bool
    let favoriteScope: LocationScope
    let locationMessage: String?
    let onChange: () -> Void
    let onSelectScope: (LocationScope) -> Void
    let onSaveFavorite: () -> Void
    let onUseFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    favoriteButtons
                }

                VStack(spacing: 8) {
                    favoriteButtons
                }
            }

            if let locationMessage, !locationMessage.isEmpty {
                Text(locationMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.screenSubtitle)
                    .padding(.horizontal, 4)
            }

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

    @ViewBuilder
    private var favoriteButtons: some View {
        Button(action: onSaveFavorite) {
            Label(isFavorite ? "Favourite area" : "Save this area", systemImage: isFavorite ? "heart.fill" : "heart")
                .font(.caption.weight(.black))
                .foregroundStyle(isFavorite ? .white : PCCTheme.leafGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .background(isFavorite ? PCCTheme.leafGreen : .white.opacity(0.82), in: Capsule())
        }
        .buttonStyle(.plain)

        if favoriteScope.id != selectedScope.id {
            Button(action: onUseFavorite) {
                Label(favoriteScope.name, systemImage: "location.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct LocationFinderSheet: View {
    let selectedScope: LocationScope
    let displayLadder: [LocationScope]
    let locationCatalog: LocationCatalog
    let onSelectScope: (LocationScope) -> Void

    @EnvironmentObject private var locationPreferenceStore: UserLocationPreferenceStore
    @AppStorage(LocationRecentScopeStore.storageKey) private var recentScopeIDs = ""
    @State private var query = ""

    private var results: [LocationScope] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return suggestedScopes
        }

        return locationCatalog.searchScopes(matching: trimmed)
    }

    private var suggestedScopes: [LocationScope] {
        _ = recentScopeIDs
        let localScopes = locationCatalog.relatedScopes(for: selectedScope.id)
        let recentScopes = LocationRecentScopeStore.recentScopes(in: locationCatalog)
        let defaultScopes = locationCatalog.quickScopes

        if selectedScope.id != LocationScope.defaultID {
            return (localScopes + recentScopes + defaultScopes).uniquedByID().prefix(12).map { $0 }
        }

        return recentScopes.isEmpty ? defaultScopes : (recentScopes + defaultScopes).uniquedByID().prefix(12).map { $0 }
    }

    private var suggestedTitle: String {
        if selectedScope.id != LocationScope.defaultID {
            return "Areas near \(selectedScope.name)"
        }

        return suggestedScopes == locationCatalog.quickScopes ? "Suggested areas" : "Recent areas"
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

                            Text("Choose a local area, search a wider region, or let the app find where you belong.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                        }

                        Button {
                            locationPreferenceStore.requestCurrentLocation()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: locationPreferenceStore.isLocating ? "location.circle" : "location.fill")
                                    .font(.headline.weight(.black))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(locationPreferenceStore.isLocating ? "Finding your community" : "Find where you belong")
                                        .font(.headline.weight(.black))

                                    Text("Uses location only while the app is open.")
                                        .font(.caption.weight(.semibold))
                                        .opacity(0.78)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.black))
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(locationPreferenceStore.isLocating)

                        if let message = locationPreferenceStore.locationMessage {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                .lineSpacing(2)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(PCCTheme.ink.opacity(0.52))

                            TextField("Search place or area", text: $query)
                                .font(.body.weight(.bold))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)

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
                            Text(query.isEmpty ? suggestedTitle : "Matches")
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
            Text("Current area")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))

            HStack(spacing: 10) {
                Text(selectedScope.name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                Spacer(minLength: 0)
            }

            let widerAreas = displayLadder.dropFirst((displayLadder.firstIndex(where: { $0.id == selectedScope.id }) ?? -1) + 1)
            if !widerAreas.isEmpty {
                Text("Widen to")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(widerAreas.prefix(4))) { item in
                        Button {
                            onSelectScope(item)
                        } label: {
                            Text(item.name)
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.leafGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.82), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
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

                    Text(scope.kind == .community ? "Local community area" : parentHint)
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

    private var parentHint: String {
        guard let parent = displayLadder.dropFirst().first else {
            return "Everything currently listed"
        }

        return "Within \(parent.name)"
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(wideningOptions) { scope in
                            Button {
                                onSelectLocationScope(scope)
                            } label: {
                                Text(scope.name)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PCCTheme.leafGreen, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
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

    private var selectedTopic: EventCategory? {
        EventCategory(rawValue: selectedTopicID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Browse by topic")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer()

                if selectedTopic != nil {
                    Button("Clear") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            selectedTopicID = "All"
                        }
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            selectedTopicID = "All"
                        }
                    } label: {
                        Text("All")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(selectedTopic == nil ? .white : PCCTheme.leafGreen)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                selectedTopic == nil ? PCCTheme.pohutukawaOrange : .white.opacity(0.76),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(EventCategory.allCases) { topic in
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
