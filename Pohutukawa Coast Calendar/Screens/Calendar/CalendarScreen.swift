import SwiftUI

struct HostsScreen: View {
    @AppStorage("communityCalendar.hosts.locationScope") private var selectedLocationScopeID = LocationScope.defaultID
    @AppStorage("communityCalendar.hosts.locationFocusScope") private var focusedLocationScopeID = LocationScope.defaultID
    @State private var locationCatalog = LocationCatalog.local
    @State private var hosts: [HostDirectoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingLocationFinder = false

    private let service: (PublishedEventFetching & BusinessProfileFetching & LocationScopeFetching) = SupabaseEventService()

    private var selectedScope: LocationScope {
        locationCatalog.defaultScope(for: selectedLocationScopeID)
    }

    private var visibleHosts: [HostDirectoryItem] {
        let covered = locationCatalog.coveredScopeIDs(for: selectedScope.id)
            .union(LocationCatalog.local.coveredScopeIDs(for: selectedScope.id))
        return hosts
            .filter { host in
                if let areaID = host.profile?.areaScopeID, covered.contains(areaID) {
                    return true
                }
                return host.events.contains { selectedScope.matches($0) }
            }
            .sorted(by: HostDirectoryItem.recommendedSort)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HostsHeroCard(scope: selectedScope, hostCount: visibleHosts.count, onChangeArea: { isShowingLocationFinder = true })

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local hosts")
                                .pccScreenTitleStyle()

                            Text("Find schools, venues, clubs, groups and organisations publishing around \(selectedScope.name).")
                                .pccScreenSubtitleStyle()
                        }

                        if isLoading {
                            LoadingEventsCard()
                        } else if let errorMessage {
                            FeedMessageCard(
                                icon: "wifi.exclamationmark",
                                title: "Hosts could not be loaded",
                                message: errorMessage
                            ) {
                                Task { await loadHosts() }
                            }
                        } else if visibleHosts.isEmpty {
                            FeedMessageCard(
                                icon: "person.3",
                                title: "Hosts will appear here",
                                message: "As organisations publish listings around \(selectedScope.name), their public pages will collect here.",
                                retry: nil
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(visibleHosts) { host in
                                    NavigationLink {
                                        OrganiserEventsScreen(
                                            organiserID: host.ownerUserID,
                                            organiserName: host.name,
                                            profile: host.profile,
                                            profileID: host.profile?.id
                                        )
                                    } label: {
                                        HostDirectoryCard(host: host)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.homeBottomPadding)
                    .pccLocksHorizontalScrollWidth()
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.standardBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationBarHidden(true)
            .task {
                await loadHosts()
            }
            .refreshable {
                await loadHosts()
            }
        }
        .pccDismissesKeyboardOnTap()
        .sheet(isPresented: $isShowingLocationFinder) {
            LocationFinderSheet(
                selectedScope: selectedScope,
                displayLadder: locationCatalog.displayLadder(
                    selectedID: selectedLocationScopeID,
                    focusID: focusedLocationScopeID
                ),
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
            focusedLocationScopeID = scope.id
            selectedLocationScopeID = scope.id
        }
    }

    @MainActor
    private func loadHosts() async {
        isLoading = hosts.isEmpty
        errorMessage = nil

        do {
            locationCatalog = (try? await service.fetchLocationCatalog()) ?? .local

            async let profileResult = try? service.fetchApprovedBusinessProfiles()
            async let eventResult = try? service.fetchPublishedEvents()
            let profiles = await profileResult ?? []
            let events = (await eventResult ?? []).filter(\.isPubliclyVisible)

            hosts = HostDirectoryItem.build(profiles: profiles, events: events)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Please try again soon."
        }
    }
}

private struct HostDirectoryItem: Identifiable {
    let ownerUserID: UUID?
    let name: String
    let profile: PublicBusinessProfileRecord?
    let events: [LocalEvent]

    var id: String {
        if let profile {
            return "profile-\(profile.id.uuidString.lowercased())"
        }
        return "owner-\(ownerUserID?.uuidString.lowercased() ?? name.lowercased())"
    }

    var upcomingCount: Int {
        events.count
    }

    var pollCount: Int {
        events.filter(\.isPoll).count
    }

    var nextEvent: LocalEvent? {
        events.sorted { $0.startDate < $1.startDate }.first
    }

    var subtitle: String {
        if let profile, let about = cleaned(profile.bio) {
            return about
        }

        if let nextEvent {
            return "Next up: \(nextEvent.title)"
        }

        return profile == nil ? "Local organiser" : "Verified organisation"
    }

    var isVerified: Bool {
        profile != nil
    }

    var activityRank: Int {
        let listingWeight = min(upcomingCount, 8) * 10
        let pollWeight = min(pollCount, 4) * 4
        let profileWeight = isVerified ? 12 : 0
        return profileWeight + listingWeight + pollWeight
    }

    static func recommendedSort(_ lhs: HostDirectoryItem, _ rhs: HostDirectoryItem) -> Bool {
        if lhs.activityRank != rhs.activityRank {
            return lhs.activityRank > rhs.activityRank
        }

        let lhsNext = lhs.nextEvent?.startDate ?? .distantFuture
        let rhsNext = rhs.nextEvent?.startDate ?? .distantFuture
        if lhsNext != rhsNext {
            return lhsNext < rhsNext
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static func build(profiles: [PublicBusinessProfileRecord], events: [LocalEvent]) -> [HostDirectoryItem] {
        let eventsByProfile = Dictionary(grouping: events.compactMap { event -> (UUID, LocalEvent)? in
            guard let profileID = event.businessProfileID else { return nil }
            return (profileID, event)
        }, by: \.0).mapValues { pairs in
            pairs.map(\.1).sorted { $0.startDate < $1.startDate }
        }

        let eventsByOwner = Dictionary(grouping: events.compactMap { event -> (UUID, LocalEvent)? in
            guard event.businessProfileID == nil,
                  let ownerID = event.submittedBy else { return nil }
            return (ownerID, event)
        }, by: \.0).mapValues { pairs in
            pairs.map(\.1).sorted { $0.startDate < $1.startDate }
        }

        var items = profiles.map { profile in
            HostDirectoryItem(
                ownerUserID: nil,
                name: profile.displayName,
                profile: profile,
                events: eventsByProfile[profile.id, default: []]
            )
        }

        let fallbackItems = eventsByOwner.compactMap { ownerID, events -> HostDirectoryItem? in
            guard let firstEvent = events.first else { return nil }
            return HostDirectoryItem(
                ownerUserID: ownerID,
                name: firstEvent.organiserDisplayName,
                profile: nil,
                events: events
            )
        }

        items.append(contentsOf: fallbackItems)
        return items.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct HostsHeroCard: View {
    let scope: LocationScope
    let hostCount: Int
    var onChangeArea: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hosts")
                    .font(.system(size: 42, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)

                Text("Organisations")
                    .font(.system(size: 38, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            Text("Find schools, clubs, venues and groups around \(scope.name).")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.cardBody)
                .lineSpacing(3)

            HStack(spacing: 10) {
                HostHeroMetric(value: "\(hostCount)", label: hostCount == 1 ? "host" : "hosts", icon: "person.3.fill")
                Button(action: onChangeArea) {
                    HostHeroMetric(value: scope.name, label: "tap to change area", icon: "mappin.and.ellipse")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change area")
            }
        }
        .padding(20)
        .pccCardStyle()
    }
}

private struct HostHeroMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 34, height: 34)
                .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PCCTheme.cardMeta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

private struct HostDirectoryCard: View {
    let host: HostDirectoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            MemberAvatarImage(
                request: MemberProfileImageDelivery.request(path: host.profile?.avatarImagePath),
                name: host.name,
                isVerified: host.isVerified,
                positionX: host.profile?.avatarImagePositionX ?? 50,
                positionY: host.profile?.avatarImagePositionY ?? 50
            )
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(host.name)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.cardTitle)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    if host.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                            .padding(.top, 3)
                    }
                }

                Text(host.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.cardBody)
                    .lineLimit(3)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    Label("\(host.upcomingCount) upcoming", systemImage: "rectangle.stack.fill")
                    if host.pollCount > 0 {
                        Label("\(host.pollCount) poll\(host.pollCount == 1 ? "" : "s")", systemImage: "chart.bar.doc.horizontal")
                    }
                    if let nextEvent = host.nextEvent {
                        Label(nextEvent.dateText, systemImage: "calendar")
                    }
                }
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.32))
                .padding(.top, 4)
        }
        .padding(14)
        .pccCardStyle()
    }
}
