import SwiftUI

struct HomeScreen: View {
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let eventService: PublishedEventFetching = SupabaseEventService()

    private var boardEvents: [LocalEvent] {
        events.sorted {
            if $0.isPaidPush != $1.isPaidPush {
                return $0.isPaidPush && !$1.isPaidPush
            }

            if $0.isFeatured != $1.isFeatured {
                return $0.isFeatured && !$1.isFeatured
            }

            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }

            return $0.startDate > $1.startDate
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HomeHero(eventCount: boardEvents.count)

                        if isLoading {
                            LoadingEventsCard()
                        } else if let loadError {
                            FeedMessageCard(
                                icon: "wifi.exclamationmark",
                                title: "Local board could not be loaded",
                                message: loadError
                            ) {
                                Task { await loadEvents() }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Local Board")
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(PCCTheme.ink)

                                Text("Recently listed around the coast")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.58))

                                if boardEvents.isEmpty {
                                    FeedMessageCard(
                                        icon: "newspaper",
                                        title: "No local listings yet",
                                        message: "Approved listings will appear here as the board fills up.",
                                        retry: nil
                                    )
                                } else {
                                    ForEach(boardEvents) { event in
                                        NavigationLink {
                                            EventDetailScreen(event: event)
                                        } label: {
                                            HomePostCard(event: event)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, PCCKeyboardSpacing.homeBottomPadding)
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

    @MainActor
    private func loadEvents() async {
        isLoading = events.isEmpty
        loadError = nil

        do {
            events = try await eventService.fetchPublishedEvents()
            isLoading = false
        } catch {
            isLoading = false
            loadError = "Please try again soon."
        }
    }
}

struct HomeHero: View {
    let eventCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pōhutukawa")
                        .font(.system(size: 31, weight: .black, design: .serif))
                        .minimumScaleFactor(0.86)
                        .lineLimit(1)

                    Text("Coast Board")
                        .font(.system(size: 36, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("\(eventCount)")
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("listed")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }
                .padding(12)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            Text("A calm local noticeboard for markets, music, family days, fundraisers and community happenings.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.70))
                .lineSpacing(3)
        }
        .foregroundStyle(PCCTheme.ink)
        .padding(20)
        .pccCardStyle()
    }
}
