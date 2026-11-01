import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var appOpenAnalyticsStore: AppOpenAnalyticsStore
    @AppStorage("communityCalendar.home.locationScope") private var selectedLocationScopeID = LocationScope.defaultID
    @AppStorage("communityCalendar.home.locationFocusScope") private var focusedLocationScopeID = LocationScope.defaultID
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

    private var boardEvents: [LocalEvent] {
        events
            .filter { isUsingBackendLocationFilter || selectedLocationScope.matches($0) }
            .sorted(by: EventFeedOrdering.board)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                List {
                    HomeHero(
                        selectedScope: selectedLocationScope,
                        siblingScopes: locationCatalog.primaryChips(of: selectedLocationScopeID),
                        ancestorScopes: locationCatalog.ancestorScopes(of: selectedLocationScopeID),
                        eventCount: boardEvents.count,
                        weeklyViewCount: appOpenAnalyticsStore.weeklyOpenCount,
                        onChangeArea: { isShowingLocationFinder = true },
                        onSelectSibling: selectLocationScope
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 76, leading: 16, bottom: 12, trailing: 16))

                    if isLoading {
                        LoadingEventsCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else if let loadError {
                        FeedMessageCard(
                            icon: "wifi.exclamationmark",
                            title: "Local board could not be loaded",
                            message: loadError
                        ) {
                            Task { await loadEvents() }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else if boardEvents.isEmpty {
                        FeedMessageCard(
                            icon: "newspaper",
                            title: "It’s a quiet time right now",
                            message: "List something to be the first thing this week.",
                            retry: nil
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else {
                        ForEach(boardEvents) { event in
                            HomeBoardCard(
                                event: event,
                                onOpen: { openedEventID = event.id }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
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
        // Keyboard dismiss tap stolen Home card buttons; dismiss via scroll instead.
        .task {
            await appOpenAnalyticsStore.refreshWeeklyCount()
            await loadEvents()
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

    private func selectLocationScope(_ scope: LocationScope) {
        LocationRecentScopeStore.record(scope)

        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            if selectedLocationLadder.contains(where: { $0.id == scope.id }) {
                focusedLocationScopeID = selectedLocationLadder.first?.id ?? scope.id
            } else {
                focusedLocationScopeID = scope.id
            }
            selectedLocationScopeID = scope.id
            UserDefaults.standard.set(scope.id, forKey: "communityCalendar.whatsOn.locationScope")
            UserDefaults.standard.set(scope.id, forKey: "communityCalendar.whatsOn.locationFocusScope")
            UserDefaults.standard.set(scope.id, forKey: "communityCalendar.hosts.locationScope")

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
                print("[Home] scoped board ok scope=\(selectedLocationScope.id) count=\(events.count)")
            } catch {
                print("[Home] scoped board failed scope=\(selectedLocationScope.id) error=\(error)")
                do {
                    events = try await eventService.fetchPublishedEvents()
                        .filter(\.isPubliclyVisible)
                    isUsingBackendLocationFilter = false
                    print("[Home] unscoped board ok count=\(events.count)")
                } catch {
                    print("[Home] unscoped board failed error=\(error)")
                    throw error
                }
            }
            isLoading = false
        } catch {
            isLoading = false
            loadError = "Please try again soon."
            print("[Home] board dead: \(error)")
        }
    }
}

struct HomeHero: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    let selectedScope: LocationScope
    let siblingScopes: [LocationScope]
    let ancestorScopes: [LocationScope]
    let eventCount: Int
    let weeklyViewCount: Int?
    let onChangeArea: () -> Void
    let onSelectSibling: (LocationScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let greeting = PCCPersonalGreeting.line(name: userSessionStore.session?.greetingName) {
                Text(greeting)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(CommunityArea.appBrandName.components(separatedBy: " ").first ?? CommunityArea.appBrandName)
                    .font(.system(size: 38, weight: .black, design: .serif))
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)

                Text(CommunityArea.appBrandName.components(separatedBy: " ").dropFirst().joined(separator: " "))
                    .font(.system(size: 44, weight: .black, design: .serif))
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            Button(action: onChangeArea) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(selectedScope.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.black))
                }
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            if !siblingScopes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(siblingScopes) { scope in
                            Button {
                                onSelectSibling(scope)
                            } label: {
                                Text(scope.name)
                                    .lineLimit(1)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.78))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PCCTheme.ink.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !ancestorScopes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ancestorScopes) { scope in
                            Button {
                                onSelectSibling(scope)
                            } label: {
                                Text(scope.name)
                                    .lineLimit(1)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.leafGreen)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Your local guide to markets, music, family days, fundraisers and everything happening around \(selectedScope.name).")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.70))
                .lineSpacing(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    counterContent
                }

                VStack(spacing: 10) {
                    counterContent
                }
            }
        }
        .foregroundStyle(PCCTheme.ink)
        .padding(20)
        .pccCardStyle()
    }

    @ViewBuilder
    private var counterContent: some View {
        HeroCounter(
            value: weeklyViewText,
            label: "views this week",
            icon: "eye.fill"
        )

        HeroCounter(
            value: "\(eventCount)",
            label: eventCount == 1 ? "listing" : "listings",
            icon: "rectangle.stack.fill"
        )
    }

    private var weeklyViewText: String {
        guard let weeklyViewCount else { return "—" }
        return weeklyViewCount.formatted()
    }
}

private struct HeroCounter: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 34, height: 34)
                .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}


private struct HomeBoardCard: View {
    let event: LocalEvent
    let onOpen: () -> Void

    var body: some View {
        Group {
            if event.isPoll {
                PollPostCard(event: event, onOpen: onOpen)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onOpen) {
                        HomePostCard(event: event, showsEngagement: false)
                    }
                    .buttonStyle(.plain)

                    EngagementActionRow(event: event)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .zIndex(2)
                }
                .pccCardStyle()
            }
        }
        .compositingGroup()
    }
}
