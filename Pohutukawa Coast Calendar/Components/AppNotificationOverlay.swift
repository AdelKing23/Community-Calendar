import SwiftUI

enum NotificationMuteCategory: String, CaseIterable, Identifiable {
    case membership
    case subscription
    case listings
    case reminders
    case supportQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .membership: return "Membership"
        case .subscription: return "Subscription"
        case .listings: return "My listings"
        case .reminders: return "Reminders"
        case .supportQueue: return "Review queue"
        }
    }
}

enum AppNotificationDestination: Hashable, Identifiable {
    case createAccount
    case membership
    case myListings
    case savedEvents
    case reviewQueue
    case event(LocalEvent)

    var id: String {
        switch self {
        case .createAccount: return "create-account"
        case .membership: return "membership"
        case .myListings: return "my-listings"
        case .savedEvents: return "saved-events"
        case .reviewQueue: return "review-queue"
        case .event(let event): return "event-\(event.id.uuidString)"
        }
    }
}

private struct AppNotificationItem: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let message: String
    let tint: Color
    let destination: AppNotificationDestination
    let priority: Int
    var category: NotificationMuteCategory = .listings
}

struct AppNotificationOverlay: View {
    @Binding var selectedTab: MainTab

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var pushNotificationStore: PushNotificationStore
    @EnvironmentObject private var purchaseService: StoreKitPurchaseService
    @State private var isShowingCenter = false
    @State private var selectedDestination: AppNotificationDestination?
    @State private var items: [AppNotificationItem] = []

    private var badgeCount: Int {
        let muted = NotificationMuteStore.mutedCategories
        return items.filter { !muted.contains($0.category) }.count
    }

    @State private var isLoading = false

    private let service: UserListingFetching & EventChangeRequesting & PublishedEventFetching & UserNotificationFetching = SupabaseEventService()
    private let supportService: OwnerEventReviewing = SupabaseEventService()

    var body: some View {
        Button {
            isShowingCenter = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: badgeCount == 0 ? "bell" : "bell.badge.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(badgeCount == 0 ? PCCTheme.ink.opacity(0.68) : .white)
                    .frame(width: 48, height: 48)
                    .background(badgeCount == 0 ? .white.opacity(0.92) : PCCTheme.leafGreen, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.96), lineWidth: 1))
                    .shadow(color: PCCTheme.deepGreen.opacity(0.16), radius: 14, x: 0, y: 8)

                if badgeCount > 0 {
                    Text("\(min(badgeCount, 9))")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(PCCTheme.pohutukawaOrange, in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(items.isEmpty ? "Notifications" : "\(items.count) notifications")
        .task(id: userSessionStore.session?.userID) {
            await refreshItems()
        }
        .onChange(of: reminderStore.activeReminderCount) { _, _ in
            Task { await refreshItems() }
        }
        .onChange(of: engagementStore.savedEventIDs) { _, _ in
            Task { await refreshItems() }
        }
        .onChange(of: engagementStore.goingEventIDs) { _, _ in
            Task { await refreshItems() }
        }
        .onChange(of: engagementStore.interestedEventIDs) { _, _ in
            Task { await refreshItems() }
        }
        .onChange(of: purchaseService.state) { _, _ in
            Task { await refreshItems() }
        }
        .sheet(isPresented: $isShowingCenter) {
            AppNotificationCenterSheet(
                items: items,
                isLoading: isLoading,
                onRefresh: { Task { await refreshItems() } },
                onSelect: handleSelection
            )
        }
        .sheet(item: $selectedDestination) { destination in
            destinationView(for: destination)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AppNotificationDestination) -> some View {
        switch destination {
        case .createAccount:
            EmptyView()
        case .membership:
            BusinessPlansScreen()
                .environmentObject(userSessionStore)
                .environmentObject(pushNotificationStore)
                .environmentObject(purchaseService)
        case .myListings:
            MyListingsSettingsScreen {
                selectedTab = .create
            }
        case .savedEvents:
            SavedRemindersScreen()
        case .reviewQueue:
            NavigationStack {
                SupportAdminScreen()
                    .environmentObject(userSessionStore)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedDestination = nil }
                                .font(.headline.weight(.bold))
                                .foregroundStyle(PCCTheme.leafGreen)
                        }
                    }
            }
        case .event(let event):
            NavigationStack {
                EventDetailScreen(event: event)
            }
        }
    }

    private func handleSelection(_ item: AppNotificationItem) {
        NotificationDismissStore.dismiss(item.id)
        if item.id.hasPrefix("backend-"),
           let uuid = UUID(uuidString: String(item.id.dropFirst("backend-".count))) {
            Task {
                guard let token = userSessionStore.session?.accessToken else { return }
                try? await service.markUserNotificationRead(id: uuid, accessToken: token)
            }
        }

        isShowingCenter = false

        if item.destination == .createAccount {
            selectedTab = .create
        } else {
            selectedDestination = item.destination
        }
    }

    @MainActor
    private func refreshItems() async {
        let requestContext = userSessionStore.captureAccountContext()
        isLoading = true
        defer { isLoading = false }

        var nextItems: [AppNotificationItem] = []

        if !userSessionStore.isSignedIn {
            nextItems.append(
                AppNotificationItem(
                    id: "sign-in",
                    icon: "person.crop.circle.badge.plus",
                    title: "Sign in to track listings",
                    message: "Create or sign into an account so submitted listings, approvals and subscriptions stay connected.",
                    tint: PCCTheme.leafGreen,
                    destination: .createAccount,
                    priority: 70
                )
            )
        } else {
            nextItems.append(contentsOf: await backendNotificationItems())
            nextItems.append(contentsOf: await listingItems())
        }

        nextItems.append(contentsOf: await savedEventItems())
        nextItems.append(contentsOf: purchaseItems())
        nextItems.append(contentsOf: await supportQueueItems())

        guard userSessionStore.isCurrent(requestContext) else { return }

        nextItems = nextItems.filter { !NotificationDismissStore.isDismissed($0.id) }

        items = Array(nextItems.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.title < rhs.title
        }.prefix(12))
    }


    @MainActor
    private func supportQueueItems() async -> [AppNotificationItem] {
        await userSessionStore.refreshIfNeeded()
        guard let session = userSessionStore.session else { return [] }
        let hasSupport = (try? await supportService.currentUserHasSupportAccess(accessToken: session.accessToken)) ?? true
        guard hasSupport else { return [] }
        return [
            AppNotificationItem(
                id: "support-review-queue",
                icon: "checklist.checked",
                title: "Review queue",
                message: "Open Review HQ to publish or send listings back.",
                tint: PCCTheme.leafGreen,
                destination: .reviewQueue,
                priority: 120,
                category: .supportQueue
            )
        ]
    }

    @MainActor
    private func backendNotificationItems() async -> [AppNotificationItem] {
        await userSessionStore.refreshIfNeeded()
        guard let session = userSessionStore.session else { return [] }

        do {
            return try await service.fetchUserNotifications(userID: session.userID, accessToken: session.accessToken)
                .filter { $0.readAt == nil }
                .prefix(6)
                .map { notification in
                    AppNotificationItem(
                        id: "backend-\(notification.id.uuidString)",
                        icon: notification.notificationType == "membership_decision" ? "checkmark.seal.fill" : "bell.badge.fill",
                        title: notification.title,
                        message: notification.body,
                        tint: notification.notificationType == "membership_decision" ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen,
                        destination: notification.notificationType == "membership_decision" ? .membership : .savedEvents,
                        priority: notification.notificationType == "membership_decision" ? 110 : 80,
                        category: notification.notificationType == "membership_decision" ? .membership : .reminders
                    )
                }
        } catch {
            return []
        }
    }

    @MainActor
    private func listingItems() async -> [AppNotificationItem] {
        await userSessionStore.refreshIfNeeded()
        guard let session = userSessionStore.session else { return [] }
        if (try? await supportService.currentUserHasSupportAccess(accessToken: session.accessToken)) == true {
            return []
        }

        do {
            async let loadedListings = service.fetchUserListings(userID: session.userID, accessToken: session.accessToken)
            async let loadedRequests = service.fetchMyChangeRequests(userID: session.userID, accessToken: session.accessToken)
            let listings = try await loadedListings
            let requests = try await loadedRequests

            var results: [AppNotificationItem] = []

            for listing in listings {
                switch listing.listingStatus {
                case .orgCalendar:
                    break
                case .approvedAwaitingPayment:
                    results.append(
                        AppNotificationItem(
                            id: "member-access-\(listing.id)",
                            icon: "checkmark.seal.fill",
                            title: "Member access needed",
                            message: "\(listing.title) needs an approved member account with an active subscription before it can go live.",
                            tint: PCCTheme.pohutukawaOrange,
                            destination: .myListings,
                            priority: 100
                        )
                    )
                case .rejected:
                    results.append(
                        AppNotificationItem(
                            id: "rejected-\(listing.id)",
                            icon: "exclamationmark.circle.fill",
                            title: "Listing needs attention",
                            message: "\(listing.title) was not approved. Open My Listings to read why and edit or remove it.",
                            tint: PCCTheme.pohutukawaOrange,
                            destination: .event(listing),
                            priority: 95
                        )
                    )
                case .pendingReview:
                    results.append(
                        AppNotificationItem(
                            id: "review-\(listing.id)",
                            icon: "clock.badge.exclamationmark",
                            title: "Waiting for review",
                            message: "\(listing.title) is with Support. Open My Listings to review, edit or remove it while it is pending.",
                            tint: PCCTheme.leafGreen,
                            destination: .event(listing),
                            priority: 45
                        )
                    )
                case .published:
                    results.append(
                        AppNotificationItem(
                            id: "live-\(listing.id)",
                            icon: "checkmark.circle.fill",
                            title: "Listing is live",
                            message: "\(listing.title) is on the board.",
                            tint: PCCTheme.leafGreen,
                            destination: .event(listing),
                            priority: 40,
                            category: .listings
                        )
                    )
                case .archived:
                    break
                }
            }

            for request in requests where request.status == .rejected {
                if request.event?.listingStatus == .archived { continue }
                results.append(
                    AppNotificationItem(
                        id: "request-rejected-\(request.id)",
                        icon: "square.and.pencil.circle.fill",
                        title: "\(request.supportTitle) needs changes",
                        message: {
                            let parts = [request.reviewReason?.label, request.supportNote]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            return parts.isEmpty
                                ? "Support has feedback on your request. Open My Listings to review it."
                                : parts.joined(separator: " — ")
                        }(),
                        tint: PCCTheme.pohutukawaOrange,
                        destination: request.event.map { AppNotificationDestination.event($0) } ?? .myListings,
                        priority: 90
                    )
                )
            }

            return results
        } catch {
            return [
                AppNotificationItem(
                    id: "listing-load-failed",
                    icon: "wifi.exclamationmark",
                    title: "Couldn’t check listings",
                    message: "Tap to open My Listings and try refreshing.",
                    tint: PCCTheme.pohutukawaOrange,
                    destination: .myListings,
                    priority: 55
                )
            ]
        }
    }

    @MainActor
    private func savedEventItems() async -> [AppNotificationItem] {
        guard reminderStore.activeReminderCount > 0 || !engagementStore.goingEventIDs.isEmpty else {
            return []
        }

        do {
            let events = try await service.fetchPublishedEvents()
            let upcoming = events
                .filter { event in
                    event.endDate > Date()
                        && (reminderStore.hasReminder(for: event) || engagementStore.isGoing(event))
                }
                .sorted { $0.startDate < $1.startDate }

            guard let next = upcoming.first else { return [] }

            return [
                AppNotificationItem(
                    id: "next-saved-\(next.id)",
                    icon: reminderStore.hasReminder(for: next) ? "alarm.waves.left.and.right.fill" : "checkmark.circle.fill",
                    title: reminderStore.hasReminder(for: next) ? "Reminder set" : "Going soon",
                    message: "\(next.title) · \(next.dateText), \(next.timeText)",
                    tint: PCCTheme.leafGreen,
                    destination: .event(next),
                    priority: 60
                )
            ]
        } catch {
            return [
                AppNotificationItem(
                    id: "saved-load-failed",
                    icon: "bookmark.circle",
                    title: "Saved events need refresh",
                    message: "Tap to open Saved Events and refresh your reminders.",
                    tint: PCCTheme.leafGreen,
                    destination: .savedEvents,
                    priority: 35
                )
            ]
        }
    }

    private func purchaseItems() -> [AppNotificationItem] {
        switch purchaseService.state {
        case .awaitingBackendRetry:
            return [
                AppNotificationItem(
                    id: "purchase-retry",
                    icon: "exclamationmark.seal.fill",
                    title: "Subscription waiting to activate",
                    message: "Apple confirmed a purchase, but publishing access still needs a refresh. Open Membership to retry activation.",
                    tint: PCCTheme.pohutukawaOrange,
                    destination: .membership,
                    priority: 98
                )
            ]
        case .failed(let message):
            return [
                AppNotificationItem(
                    id: "purchase-failed",
                    icon: "exclamationmark.seal.fill",
                    title: "Subscription needs attention",
                    message: message,
                    tint: PCCTheme.pohutukawaOrange,
                    destination: .myListings,
                    priority: 97
                )
            ]
        case .pending:
            return [
                AppNotificationItem(
                    id: "purchase-pending",
                    icon: "clock.badge.checkmark",
                    title: "Subscription pending",
                    message: "Apple is still processing the purchase. Open My Listings for the latest publishing status.",
                    tint: PCCTheme.leafGreen,
                    destination: .myListings,
                    priority: 65
                )
            ]
        default:
            return []
        }
    }
}

private struct AppNotificationCenterSheet: View {
    let items: [AppNotificationItem]
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSelect: (AppNotificationItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("NOTIFICATIONS", systemImage: "bell.badge.fill")
                                .font(.caption.weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("What needs doing")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Tap any card and Coast Calendar will take you to the listing, member, reminder, or sign-in step.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if isLoading && items.isEmpty {
                            NotificationEmptyCard(icon: "arrow.clockwise", title: "Checking", message: "Looking for listing updates, member actions and reminders.")
                        } else if items.isEmpty {
                            NotificationEmptyCard(icon: "checkmark.seal.fill", title: "All caught up", message: "No listing actions, member actions or reminders need attention right now.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(items) { item in
                                    Button {
                                        onSelect(item)
                                    } label: {
                                        NotificationActionCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
        }
    }
}

private struct NotificationActionCard: View {
    let item: AppNotificationItem

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: item.icon)
                .font(.title3.weight(.black))
                .foregroundStyle(item.tint)
                .frame(width: 42, height: 42)
                .background(item.tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(item.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.36))
        }
        .padding(16)
        .pccCardStyle()
    }
}


private 
enum NotificationDismissStore {
    private static let key = "pcc.notification.dismissed.ids"
    static var dismissedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func isDismissed(_ id: String) -> Bool { dismissedIDs.contains(id) }
    static func dismiss(_ id: String) {
        var next = dismissedIDs
        next.insert(id)
        UserDefaults.standard.set(Array(next), forKey: key)
    }
}

enum NotificationMuteStore {
    private static let key = "communityCalendar.notifications.mutedCategories"

    static var mutedCategories: Set<NotificationMuteCategory> {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw.compactMap(NotificationMuteCategory.init(rawValue:)))
    }

    static func isMuted(_ category: NotificationMuteCategory) -> Bool {
        mutedCategories.contains(category)
    }

    static func setMuted(_ category: NotificationMuteCategory, _ muted: Bool) {
        var next = mutedCategories
        if muted { next.insert(category) } else { next.remove(category) }
        UserDefaults.standard.set(next.map(\.rawValue), forKey: key)
    }
}

private struct NotificationEmptyCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pccCardStyle()
    }
}
