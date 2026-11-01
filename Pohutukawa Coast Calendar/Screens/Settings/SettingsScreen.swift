import SwiftUI
import PhotosUI
import UIKit
import UserNotifications

struct SettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var accountProfileStore: AccountProfileStore
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var pushNotificationStore: PushNotificationStore
    @EnvironmentObject private var purchaseService: StoreKitPurchaseService
    @AppStorage(PCCWallpaperStyle.storageKey) private var selectedWallpaper = PCCWallpaperStyle.ornament.rawValue
    @AppStorage(PCCCardTintStyle.storageKey) private var selectedCardTint = PCCCardTintStyle.clean.rawValue
    let onNavigateCreate: () -> Void
    @State private var canOpenReviewQueue = false
    @State private var selectedDocument: SettingsDocument?
    @State private var showWallpaperPicker = false
    @State private var showCardTintPicker = false
    @State private var showContactSupport = false
    @State private var showBusinessPlans = false
    @State private var showMyMemberPage = false
    @State private var showMyCalendar = false
    @State private var showOrgCalendar = false
    @State private var orgCalendarProfileID: UUID?
    @State private var orgCalendarName = "Organisation"
    @State private var showSavedReminders = false
    @State private var showListingAnalytics = false
    @State private var showMyListings = false
    @State private var showAccountDetails = false
    @State private var showAccountAccess = false
    @State private var showNotificationSettings = false
    @State private var overviewListings: [LocalEvent] = []
    @State private var overviewBusinessState = BusinessAccountState.empty
    @State private var isLoadingOverview = false

    private let supportService: OwnerEventReviewing = SupabaseEventService()
    private let overviewService = SupabaseEventService()

    init(onNavigateCreate: @escaping () -> Void = {}) {
        self.onNavigateCreate = onNavigateCreate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("YOUR SPACE", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("Settings")
                                .font(.system(size: 40, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Account, membership, saved activity and reminders.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        accountSection



                        SettingsActionSection(title: "My Calendar") {
                            Button {
                                showMyCalendar = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "my-calendar",
                                        icon: "calendar",
                                        title: "My Calendar",
                                        subtitle: "Dates from organisations you belong to.",
                                        detail: "Open",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsActionSection(title: "Organisations") {
                            Button {
                                showBusinessPlans = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "listed-member-application",
                                        icon: "checkmark.seal",
                                        title: userSessionStore.isSignedIn ? "Manage my organisation" : "Register your Organisation",
                                        subtitle: "Organisations list on Coast Calendar. Register, get Support approval, then subscribe to release listings to the public board.",
                                        detail: userSessionStore.isSignedIn ? memberPageDetail : "Apply",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)

                            if userSessionStore.isSignedIn {
                                Divider()
                                    .overlay(PCCTheme.ink.opacity(0.08))
                                    .padding(.leading, 48)

                                Button {
                                    showMyListings = true
                                } label: {
                                    SettingsRow(
                                        content: SettingsRowContent(
                                            id: "previous-listings",
                                            icon: "rectangle.stack",
                                            title: "My listings",
                                            subtitle: "Review, edit, remove, and follow Support feedback.",
                                            detail: "Open",
                                            style: .disclosure,
                                            isEnabled: true
                                        )
                                    )
                                }
                                .buttonStyle(.plain)

                                if overviewBusinessState.profile?.memberStatus == .approved {
                                    Divider()
                                        .overlay(PCCTheme.ink.opacity(0.08))
                                        .padding(.leading, 48)

                                    Button {
                                        orgCalendarProfileID = overviewBusinessState.profile?.id
                                        orgCalendarName = overviewBusinessState.profile?.businessName ?? "Organisation"
                                        showOrgCalendar = true
                                    } label: {
                                        SettingsRow(
                                            content: SettingsRowContent(
                                                id: "org-calendar-settings",
                                                icon: "calendar.badge.plus",
                                                title: "Org Calendar",
                                                subtitle: "Add and manage dates for your organisation.",
                                                detail: "Open",
                                                style: .disclosure,
                                                isEnabled: true
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } footer: {
                            Text("Register your Organisation with a free account. Support approves it; subscription is only needed to release listings publicly.")
                        }

                        SettingsActionSection(title: "My Activity") {
                            Button {
                                showSavedReminders = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "saved-reminders",
                                        icon: "bookmark.fill",
                                        title: "My engagements",
                                        subtitle: "See all the things you've interacted with.",
                                        detail: "Open",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(PCCTheme.ink.opacity(0.08))
                                .padding(.leading, 48)

                            Button {
                                showNotificationSettings = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "notification-settings",
                                        icon: "bell.and.waves.left.and.right",
                                        title: "Reminder settings",
                                        subtitle: "Choose how Going reminders behave on this device.",
                                        detail: reminderStore.automaticGoingRemindersEnabled ? reminderStore.reminderLeadTime.title : "Off",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsActionSection(title: "Appearance") {
                            Button {
                                showWallpaperPicker = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "wallpaper",
                                        icon: "photo",
                                        title: "App wallpaper",
                                        subtitle: PCCWallpaperStyle.style(for: selectedWallpaper).title,
                                        detail: "Change",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                showCardTintPicker = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "card-colour",
                                        icon: "square.on.square",
                                        title: "Card colour",
                                        subtitle: PCCCardTintStyle.style(for: selectedCardTint).title,
                                        detail: "Change",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        } footer: {
                            Text("Choose the background and card surface that feels easiest to read.")
                        }

                        SettingsActionSection(title: "Contact Support") {
                            Button {
                                showContactSupport = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "contact",
                                        icon: "envelope",
                                        title: "Contact \(CommunityArea.appBrandName)",
                                        subtitle: "Send a private support request from this app.",
                                        detail: "Open",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if canOpenReviewQueue {
                            NavigationLink {
                                SupportAdminScreen()
                            } label: {
                                ReviewQueueRow()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding + 10)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.standardBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationBarHidden(true)
            .pccDismissesKeyboardOnTap()
            .task(id: userSessionStore.session?.userID) {
                await checkReviewQueueAccess()
                await loadSettingsOverview()
            }
            .refreshable {
                await loadSettingsOverview()
            }
            .sheet(item: $selectedDocument) { document in
                SettingsDocumentScreen(document: document)
            }
            .sheet(isPresented: $showWallpaperPicker) {
                WallpaperPickerScreen()
            }
            .sheet(isPresented: $showCardTintPicker) {
                CardTintPickerScreen()
            }
            .sheet(isPresented: $showContactSupport) {
                ContactSupportScreen()
                    .environmentObject(userSessionStore)
            }
            .sheet(isPresented: $showBusinessPlans) {
                BusinessPlansScreen(onNavigateCreate: onNavigateCreate)
                    .environmentObject(userSessionStore)
                    .environmentObject(pushNotificationStore)
                    .environmentObject(purchaseService)
            }
            .sheet(isPresented: $showMyMemberPage) {
                if let profile = overviewBusinessState.profile, let userID = userSessionStore.session?.userID {
                    NavigationStack {
                        OrganiserEventsScreen(
                            organiserID: userID,
                            organiserName: profile.businessName,
                            profile: nil,
                            profileID: profile.id
                        )
                    }
                    .environmentObject(userSessionStore)
                    .environmentObject(engagementStore)
                } else {
                    MemberPageUnavailableSheet()
                }
            }
            .sheet(isPresented: $showOrgCalendar) {
                if let profile = overviewBusinessState.profile {
                    OrgCalendarSheet(
                        organiserName: profile.businessName,
                        events: [],
                        canWrite: true,
                        profileID: profile.id
                    )
                    .environmentObject(userSessionStore)
                }
            }
        .sheet(isPresented: $showMyCalendar) {
            MyCalendarSheet()
                .environmentObject(userSessionStore)
        }
        .sheet(isPresented: $showSavedReminders) {
                SavedRemindersScreen()
            }
            .sheet(isPresented: $showListingAnalytics) {
                ListingAnalyticsSettingsScreen()
                    .environmentObject(userSessionStore)
            }
            .sheet(isPresented: $showMyListings) {
                MyListingsSettingsScreen(onNavigateCreate: onNavigateCreate)
                    .environmentObject(userSessionStore)
            }
            .sheet(isPresented: $showAccountDetails) {
                AccountDetailsScreen()
                    .environmentObject(userSessionStore)
                    .environmentObject(accountProfileStore)
            }
            .sheet(isPresented: $showAccountAccess) {
                AccountAccessSheet()
                    .environmentObject(userSessionStore)
            }
            .sheet(isPresented: $showNotificationSettings) {
                NotificationSettingsScreen()
                    .environmentObject(reminderStore)
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if userSessionStore.isSignedIn {
            SettingsActionSection(title: "Account") {
                Button {
                    showAccountDetails = true
                } label: {
                    SettingsRow(
                        content: SettingsRowContent(
                            id: "account-details",
                            icon: "person.crop.circle.fill",
                            title: accountProfileStore.profile.hasPublicIdentity ? accountProfileStore.profile.publicDisplayName : "Account details",
                            subtitle: accountProfileSubtitle,
                            detail: "Edit",
                            style: .disclosure,
                            isEnabled: true
                        )
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(PCCTheme.ink.opacity(0.08))
                    .padding(.leading, 48)

                Button {
                    Task {
                        await pushNotificationStore.removeCurrentTokenBeforeSignOut()
                        userSessionStore.signOut()
                    }
                } label: {
                    SettingsRow(
                        content: SettingsRowContent(
                            id: "sign-out",
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign out",
                            subtitle: userSessionStore.email,
                            detail: nil,
                            style: .plain,
                            isEnabled: true
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            SettingsActionSection(title: "Account") {
                Button {
                    showAccountAccess = true
                } label: {
                    SettingsRow(
                        content: SettingsRowContent(
                            id: "join-community",
                            icon: "person.crop.circle.badge.plus",
                            title: "Create account or sign in",
                            subtitle: "Create a free account to save listings, set reminders, and Belong to organisations.",
                            detail: "Open",
                            style: .disclosure,
                            isEnabled: true
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountProfileSubtitle: String {
        if accountProfileStore.profile.contactVisibility == .anonymous {
            return "Public contact details off for new listings"
        }

        if accountProfileStore.profile.hasPublicIdentity {
            return accountProfileStore.profile.publicByline
        }

        return userSessionStore.email ?? "Signed-in account"
    }

    private var memberPageDetail: String {
        guard let profile = overviewBusinessState.profile else { return "Set up" }
        if overviewBusinessState.activeSubscription != nil { return "Preview" }
        return profile.memberStatus.displayTitle
    }

    @MainActor
    private func checkReviewQueueAccess() async {
        guard let currentSession = userSessionStore.session else {
            canOpenReviewQueue = false
            return
        }

        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? currentSession
        do {
            canOpenReviewQueue = try await supportService.currentUserHasSupportAccess(accessToken: activeSession.accessToken)
        } catch {
            canOpenReviewQueue = false
        }
    }

    @MainActor
    private func loadSettingsOverview() async {
        guard let session = userSessionStore.session else {
            overviewListings = []
            overviewBusinessState = .empty
            isLoadingOverview = false
            return
        }

        let requestedUserID = session.userID
        isLoadingOverview = true
        defer { isLoadingOverview = false }

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            guard activeSession.userID == requestedUserID,
                  userSessionStore.session?.userID == requestedUserID else {
                overviewListings = []
                overviewBusinessState = .empty
                return
            }
            async let listings = overviewService.fetchUserListings(userID: activeSession.userID, accessToken: activeSession.accessToken)
            async let business = overviewService.fetchBusinessAccount(userID: activeSession.userID, accessToken: activeSession.accessToken)
            let loadedListings = try await listings
            let loadedBusiness = try await business
            guard userSessionStore.session?.userID == requestedUserID else {
                overviewListings = []
                overviewBusinessState = .empty
                return
            }
            overviewListings = loadedListings
            overviewBusinessState = loadedBusiness
        } catch {
            overviewListings = []
            overviewBusinessState = .empty
        }
    }
}

struct SettingsCommandCenterCard: View {
    let isSignedIn: Bool
    let isLoading: Bool
    let listings: [LocalEvent]
    let businessState: BusinessAccountState
    let savedCount: Int
    let reminderCount: Int
    let onSignIn: () -> Void
    let onCreate: () -> Void
    let onListings: () -> Void
    let onBusiness: () -> Void
    let onMemberPage: () -> Void
    let onSaved: () -> Void

    private var reviewCount: Int {
        listings.filter { $0.listingStatus == .pendingReview }.count
    }

    private var rejectedCount: Int {
        listings.filter { $0.listingStatus == .rejected }.count
    }

    private var publishedCount: Int {
        listings.filter { $0.listingStatus == .published }.count
    }

    private var primaryTitle: String {
        if !isSignedIn { return "Sign in to keep everything together" }
        if rejectedCount > 0 { return "\(rejectedCount) listing\(rejectedCount == 1 ? "" : "s") need attention" }
        if reviewCount > 0 { return "\(reviewCount) listing\(reviewCount == 1 ? "" : "s") waiting for review" }
        return "Everything important is in one place"
    }

    private var primaryMessage: String {
        if !isSignedIn {
            return "Sign in once, then listings, review updates, subscriptions and saves stay attached to you."
        }
        if rejectedCount > 0 {
            return "Support has feedback. Tap My Listings, open the card, and follow the next step."
        }
        if reviewCount > 0 {
            return "Your listing is with Support. The bell will bring you back when action is needed."
        }
        return "Apply for member publishing, check review status, manage subscriptions and keep personal saves in one place."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(PCCTheme.leafGreen, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Action Hub")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(PCCTheme.pohutukawaOrange)

                    Text(primaryTitle)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(primaryMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.64))
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)
            }

            if isLoading {
                Label("Refreshing your account...", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if isSignedIn {
                    SettingsHubButton(
                        title: "My Listings",
                        detail: reviewStatusText,
                        icon: "rectangle.stack.fill",
                        tint: rejectedCount > 0 ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen,
                        action: onListings
                    )
                    SettingsHubButton(
                        title: "Member Page",
                        detail: businessStatusText,
                        icon: "checkmark.seal.fill",
                        tint: PCCTheme.leafGreen,
                        action: businessState.profile == nil ? onBusiness : onMemberPage
                    )
                    SettingsHubButton(
                        title: "Saved",
                        detail: "\(savedCount) saved, \(reminderCount) alarm\(reminderCount == 1 ? "" : "s")",
                        icon: "bell.badge.fill",
                        tint: PCCTheme.pohutukawaOrange,
                        action: onSaved
                    )
                } else {
                    SettingsHubButton(title: "Sign in", detail: "Track things", icon: "person.crop.circle.badge.plus", tint: PCCTheme.leafGreen, action: onSignIn)
                    SettingsHubButton(title: "Create", detail: "Add listing", icon: "plus.circle.fill", tint: PCCTheme.pohutukawaOrange, action: onCreate)
                }
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var reviewStatusText: String {
        if rejectedCount > 0 { return "\(rejectedCount) needs edit" }
        if reviewCount > 0 { return "\(reviewCount) in review" }
        if publishedCount > 0 { return "\(publishedCount) live" }
        return "Status"
    }

    private var businessStatusText: String {
        if let active = businessState.activeSubscription, let plan = active.plan {
            return plan.title
        }
        if let profile = businessState.profile {
            return profile.memberStatus.displayTitle
        }
        return "Apply"
    }
}

struct SettingsHubButton: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(detail)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(13)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsActionSection<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pccSettingsSectionTitleStyle()

            VStack(spacing: 0) {
                content()
            }
            .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )

            footer()
                .pccSettingsFooterStyle()
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }
}

extension SettingsActionSection where Footer == EmptyView {
    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
        self.footer = { EmptyView() }
    }
}

struct SettingsListSection: View {
    let title: String
    let rows: [SettingsRowContent]
    var footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pccSettingsSectionTitleStyle()

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SettingsRow(content: row)

                    if row.id != rows.last?.id {
                        Divider()
                            .overlay(PCCTheme.ink.opacity(0.08))
                            .padding(.leading, 48)
                    }
                }
            }
            .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .pccSettingsFooterStyle()
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsRowContent: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let detail: String?
    let style: SettingsRowStyle
    let isEnabled: Bool
}

enum SettingsRowStyle: Equatable {
    case plain
    case disclosure
    case status
    case toggle(isOn: Bool)
}

struct SettingsRow: View {
    let content: SettingsRowContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: content.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(content.isEnabled ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.34))
                .frame(width: 34, height: 34)
                .background(PCCTheme.cream.opacity(0.70), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.ink)

                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .opacity(content.isEnabled ? 1 : 0.72)
    }

    @ViewBuilder
    private var accessory: some View {
        switch content.style {
        case .plain:
            EmptyView()
        case .disclosure:
            HStack(spacing: 7) {
                if let detail = content.detail {
                    Text(detail)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.34))
            }
        case .status:
            if let detail = content.detail {
                Text(detail)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PCCTheme.cream.opacity(0.86), in: Capsule())
            }
        case .toggle(let isOn):
            Toggle("", isOn: .constant(isOn))
                .labelsHidden()
                .disabled(true)
        }
    }
}

struct SettingsSignOutRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaRed)
                .frame(width: 30, height: 30)
                .background(PCCTheme.pohutukawaRed.opacity(0.08), in: Circle())

            Text("Sign out")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaRed)

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}

struct MemberPageUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)

                    Text("No member page yet")
                        .font(.system(size: 32, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Submit a member profile first. Once it exists, this opens the public page locals will see, including your profile, contact actions, listings and polls.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .lineSpacing(4)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
            .navigationTitle("Member Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

struct AccountAccessSheet: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var authMode: CreateListingScreen.AuthMode = .signIn
    @State private var email = ""
    @State private var accountFullName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("ACCOUNT", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text(authMode == .signIn ? "Sign in" : "Create account")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("A normal account is free. Create one to save events, reminders and Belonging.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        ListingAccountGate(
                            mode: $authMode,
                            fullName: $accountFullName,
                            email: $email,
                            password: $password,
                            confirmPassword: $confirmPassword,
                            isAuthenticating: isAuthenticating,
                            errorMessage: errorMessage,
                            onForgotPassword: {
                                Task { await sendPasswordResetEmail() }
                            }
                        ) {
                            Task { await authenticate() }
                        }

                        if userSessionStore.isSignedIn, !userSessionStore.isEmailVerified {
                            EmailVerificationRequiredCard(
                                email: userSessionStore.email,
                                title: "Verify email to unlock member tools",
                                message: "Confirm your email before applying for publishing access, subscriptions or member profile changes. This helps protect your account and Support follow-up.",
                                resendAction: resendVerificationEmail,
                                refreshAction: refreshVerificationStatus
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .pccDismissesKeyboardOnTap()
            .pccKeyboardDoneToolbar {
                UIApplication.pccDismissKeyboard()
            }
            .toolbar {
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

    @MainActor
    private func resendVerificationEmail() async {
        do {
            try await userSessionStore.resendVerificationEmail()
            errorMessage = "Open the link in your email, then tap Check again."
        } catch {
            errorMessage = error.pccUserFacingMessage
        }
    }

    @MainActor
    private func refreshVerificationStatus() async {
        do {
            try await userSessionStore.refreshNow()
            errorMessage = userSessionStore.isEmailVerified
                ? "Email verified. You can continue."
                : "Still waiting for email confirmation."
        } catch {
            errorMessage = "Could not refresh account status. Please sign in again."
        }
    }

    @MainActor
    private func authenticate() async {
        guard !isAuthenticating else { return }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.localizedCaseInsensitiveContains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard !password.isEmpty else {
            errorMessage = authMode == .signIn
                ? "Enter your password to sign in."
                : "Create a password with at least 6 characters."
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        if authMode == .signUp {
            let trimmedName = accountFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedName.count >= 2 else {
                errorMessage = "Enter the name we should greet you with."
                return
            }
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match yet."
                return
            }
        }

        isAuthenticating = true
        errorMessage = nil

        do {
            switch authMode {
            case .signUp:
                try await userSessionStore.signUp(email: trimmedEmail, password: password, fullName: accountFullName)
            case .signIn:
                try await userSessionStore.signIn(email: trimmedEmail, password: password)
            }

            password = ""
            confirmPassword = ""
            isAuthenticating = false
            dismiss()
        } catch UserAuthError.signUpNeedsConfirmation {
            isAuthenticating = false
            errorMessage = "Check your email to confirm your account, then sign in."
            authMode = .signIn
            password = ""
            confirmPassword = ""
        } catch {
            isAuthenticating = false
            errorMessage = authMode == .signUp
                ? "Account could not be created. Try signing in if you already made one."
                : "Sign in failed. Check your email and password, then try again."
        }
    }

    @MainActor
    private func sendPasswordResetEmail() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.localizedCaseInsensitiveContains("@") else {
            errorMessage = "Enter your email first, then tap Forgot password."
            return
        }

        errorMessage = nil
        do {
            try await userSessionStore.sendPasswordResetEmail(email: trimmedEmail)
            errorMessage = "Password reset email sent. Check your inbox, then come back and sign in."
        } catch {
            errorMessage = "Password reset email could not be sent. Check the address and try again."
        }
    }
}

struct AccountDetailsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var accountProfileStore: AccountProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile = AccountProfile.empty
    @State private var accountFullName = ""
    @State private var savedMessage: String?
    @State private var showAccountDeletionRequest = false

    private let supportService: SupportRequestSubmitting = SupabaseEventService()

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("ACCOUNT", systemImage: "person.crop.circle")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("Public organiser details")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Add just enough detail so locals know who is behind a listing — perfect for schools, churches, sports clubs, venues and community groups.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if userSessionStore.isSignedIn {
                            AccountVerificationStatusCard(
                                email: userSessionStore.email,
                                isVerified: userSessionStore.isEmailVerified,
                                resendAction: resendVerificationEmail,
                                refreshAction: refreshVerificationStatus
                            )
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            PCCFormField(title: "User name", text: $accountFullName, prompt: "Isaac")
                            Text("Used to greet you in the app. Not shown on public listings.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                            PCCFormField(title: "Public contact name", text: $profile.displayName, prompt: "Sharon")
                            PCCFormField(title: "Role or title", text: $profile.publicRole, prompt: "Principal, coach, organiser")
                            PCCFormField(title: "Organisation", text: $profile.organisationName, prompt: "Maraetai School, local club")
                            PCCFormField(title: "Contact email", text: $profile.preferredContactEmail, prompt: userSessionStore.email ?? "hello@example.co.nz")
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            PCCFormField(title: "Phone", text: $profile.phone, prompt: "Optional")
                                .keyboardType(.phonePad)
                            PCCFormField(title: "Website or social link", text: $profile.website, prompt: "Optional")
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(18)
                        .pccCardStyle()

                        AccountContactVisibilityPicker(profile: $profile)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("How this appears")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            OrganiserIdentityPreview(profile: profile, fallbackEmail: userSessionStore.email)
                        }
                        .padding(18)
                        .pccCardStyle()

                        if let savedMessage {
                            Label(savedMessage, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(PCCTheme.leafGreen)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            accountProfileStore.save(profile)
                            Task { await saveAccountFullName() }
                            savedMessage = "Account details saved."
                        } label: {
                            Label("Save account details", systemImage: "checkmark.circle.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                        Text("Payment card details are not stored here. Apple handles subscriptions; Coast Calendar only records receipts and publishing access status.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.56))
                            .lineSpacing(2)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account control")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            Text("You can ask Coast Calendar to delete your account record and personal account details. Apple subscriptions are managed by Apple and may need to be cancelled separately.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                .lineSpacing(2)

                            Button {
                                showAccountDeletionRequest = true
                            } label: {
                                Label("Request account deletion", systemImage: "person.crop.circle.badge.xmark")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.pohutukawaRed, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }
                        .padding(18)
                        .pccCardStyle()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .pccDismissesKeyboardOnTap()
            .pccKeyboardDoneToolbar {
                UIApplication.pccDismissKeyboard()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .onAppear {
                profile = accountProfileStore.profile
                accountFullName = userSessionStore.session?.fullName ?? ""
                if profile.preferredContactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.preferredContactEmail = userSessionStore.email ?? ""
                }
            }
            .sheet(isPresented: $showAccountDeletionRequest) {
                AccountDeletionRequestScreen(
                    email: userSessionStore.email,
                    submitAction: submitAccountDeletionRequest
                )
            }
        }
    }

    @MainActor
    private func saveAccountFullName() async {
        let trimmed = accountFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        do {
            try await userSessionStore.updateFullName(trimmed)
        } catch {
            savedMessage = "User name could not be saved."
        }
    }

    @MainActor
    private func resendVerificationEmail() async {
        do {
            try await userSessionStore.resendVerificationEmail()
            savedMessage = "Verification email sent."
        } catch {
            savedMessage = error.pccUserFacingMessage
        }
    }

    @MainActor
    private func refreshVerificationStatus() async {
        do {
            try await userSessionStore.refreshNow()
            savedMessage = userSessionStore.isEmailVerified
                ? "Email verified."
                : "Still waiting for email confirmation."
        } catch {
            savedMessage = "Could not refresh account status."
        }
    }

    @MainActor
    private func submitAccountDeletionRequest(message: String) async throws {
        guard let accessToken = userSessionStore.session?.accessToken else {
            throw SupabaseServiceError.authFailed
        }

        let email = userSessionStore.email ?? "No email available"
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestMessage = [
            "Account deletion requested from iOS Account settings.",
            "Signed-in email: \(email)",
            "User note: \(trimmedMessage.isEmpty ? "No extra note supplied." : trimmedMessage)",
            "Please delete the account record and personal account data that Coast Calendar is not legally required to retain. Apple subscriptions are managed by Apple."
        ].joined(separator: "\n\n")

        _ = try await supportService.submitSupportRequest(
            topic: "Account deletion",
            message: requestMessage,
            listingReference: nil,
            accessToken: accessToken
        )

        savedMessage = "Account deletion request sent to Support."
    }
}

struct AccountDeletionRequestScreen: View {
    let email: String?
    let submitAction: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("ACCOUNT CONTROL", systemImage: "person.crop.circle.badge.xmark")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaRed)

                            Text("Request account deletion")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("This starts deletion of your Coast Calendar account and personal account details. Support will confirm the request and complete deletion of data we are not legally required to keep.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        SettingsInfoMessage(
                            icon: "creditcard.trianglebadge.exclamationmark",
                            title: "Apple subscriptions",
                            message: "Deleting your Coast Calendar account does not automatically cancel Apple billing. Manage subscriptions through your Apple ID before or after sending this request."
                        )

                        if let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                            Link(destination: subscriptionsURL) {
                                Label("Manage Apple subscriptions", systemImage: "arrow.up.forward.app.fill")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PCCTheme.leafGreen)
                            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                                    .stroke(PCCTheme.leafGreen.opacity(0.18), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Request details")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Signed-in account: \(email ?? "Unknown email")")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Optional note")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(PCCTheme.ink)

                                TextEditor(text: $note)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(PCCTheme.ink)
                                    .frame(minHeight: 120)
                                    .padding(10)
                                    .scrollContentBackground(.hidden)
                                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                                            .stroke(PCCTheme.ink.opacity(0.08), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(18)
                        .pccCardStyle()

                        if let message {
                            SettingsInfoMessage(
                                icon: didSubmit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                title: didSubmit ? "Request sent" : "Could not send request",
                                message: message
                            )
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Label(isSubmitting ? "Sending request" : "Send deletion request", systemImage: "paperplane.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(didSubmit ? PCCTheme.leafGreen : PCCTheme.pohutukawaRed, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        .disabled(isSubmitting || didSubmit)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .pccDismissesKeyboardOnTap()
            .pccKeyboardDoneToolbar {
                UIApplication.pccDismissKeyboard()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(didSubmit ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await submitAction(note)
            didSubmit = true
            message = "Support has received your account deletion request. You can sign out now; Support will confirm once the account deletion is complete."
        } catch {
            message = error.pccUserFacingMessage
        }
    }
}

struct AccountVerificationStatusCard: View {
    let email: String?
    let isVerified: Bool
    let resendAction: () async -> Void
    let refreshAction: () async -> Void

    var body: some View {
        if isVerified {
            SettingsInfoMessage(
                icon: "checkmark.shield.fill",
                title: "Email verified",
                message: "\(email ?? "This account") can apply for member publishing, save preferences and manage account details."
            )
        } else {
            EmailVerificationRequiredCard(
                email: email,
                title: "Email not verified",
                message: "Verify this email before member publishing applications or subscriptions. Apple handles card payments; this app uses the verified email for account safety and Support follow-up.",
                resendAction: resendAction,
                refreshAction: refreshAction
            )
        }
    }
}

struct OrganiserIdentityPreview: View {
    let profile: AccountProfile
    let fallbackEmail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(PCCTheme.leafGreen, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))

                if let email = contactEmail, profile.contactVisibility != .anonymous {
                    Label(email, systemImage: "envelope")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch profile.contactVisibility {
        case .anonymous:
            return "Anonymous listing contact"
        case .nameAndEmail, .publicProfile:
            return profile.hasPublicIdentity ? profile.publicDisplayName : "Local organiser"
        }
    }

    private var subtitle: String {
        switch profile.contactVisibility {
        case .anonymous:
            return "New listings will not prefill public contact name or email."
        case .nameAndEmail:
            return "New listings can show a simple public name and email."
        case .publicProfile:
            return profile.hasPublicIdentity ? profile.publicByline : "Add organiser details for the public listing profile."
        }
    }

    private var contactEmail: String? {
        let email = profile.preferredContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty { return email }
        return fallbackEmail
    }
}

struct AccountContactVisibilityPicker: View {
    @Binding var profile: AccountProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Public contact")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Choose what the app pre-fills on new listings. Support can still review everything before it goes public.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineSpacing(2)
            }

            VStack(spacing: 9) {
                ForEach(AccountProfile.ContactVisibility.allCases) { visibility in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            profile.contactVisibility = visibility
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: profile.contactVisibility == visibility ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(profile.contactVisibility == visibility ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.38))
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(visibility.title)
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(PCCTheme.ink)

                                Text(visibility.detail)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            profile.contactVisibility == visibility ? PCCTheme.leafGreen.opacity(0.10) : PCCTheme.cream.opacity(0.58),
                            in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct NotificationSettingsScreen: View {
    @EnvironmentObject private var reminderStore: EventReminderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("REMINDERS", systemImage: "bell.badge")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("Notification settings")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("When you tap Going, the app can remind you before the event starts. Simple, local, and controlled on this device.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        VStack(spacing: 0) {
                            Toggle(isOn: $reminderStore.automaticGoingRemindersEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Going reminders")
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(PCCTheme.ink)

                                    Text("Automatically schedule a reminder when you mark an event as Going.")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                }
                            }
                            .tint(PCCTheme.leafGreen)
                            .padding(16)

                            Divider()
                                .overlay(PCCTheme.ink.opacity(0.08))
                                .padding(.leading, 16)

                            Picker("Reminder time", selection: $reminderStore.reminderLeadTime) {
                                ForEach(EventReminderLeadTime.allCases) { leadTime in
                                    Text(leadTime.title).tag(leadTime)
                                }
                            }
                            .pickerStyle(.inline)
                            .disabled(!reminderStore.automaticGoingRemindersEnabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                                .stroke(.white.opacity(0.82), lineWidth: 1)
                        )

                        NotificationPermissionCard(status: reminderStore.authorizationStatus) {
                            Task {
                                _ = await reminderStore.requestNotificationAccess()
                            }
                        }

                        Text("\(reminderStore.activeReminderCount) reminder\(reminderStore.activeReminderCount == 1 ? "" : "s") currently scheduled on this device.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task {
                await reminderStore.refreshAuthorizationStatus()
            }
        }
    }
}

struct NotificationPermissionCard: View {
    let status: UNAuthorizationStatus
    let requestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                .lineSpacing(3)

            if status == .notDetermined {
                Button(action: requestAccess) {
                    Label("Allow notifications", systemImage: "bell.badge")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var title: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are ready"
        case .denied:
            return "Notifications are off"
        case .notDetermined:
            return "Allow reminders"
        @unknown default:
            return "Notification status unknown"
        }
    }

    private var message: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Going reminders can appear before events start."
        case .denied:
            return "Turn notifications on in iPhone Settings if you want Going reminders."
        case .notDetermined:
            return "The app will ask iOS for permission before scheduling your first reminder."
        @unknown default:
            return "Open iPhone Settings if reminders do not appear."
        }
    }

    private var icon: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "bell.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell.badge"
        @unknown default:
            return "bell"
        }
    }
}

struct SettingsDocumentsSection: View {
    @Binding var selectedDocument: SettingsDocument?

    var body: some View {
        SettingsActionSection(title: "Documents") {
            VStack(spacing: 0) {
                ForEach(SettingsDocument.allCases) { document in
                    Button {
                        selectedDocument = document
                    } label: {
                        SettingsRow(
                            content: SettingsRowContent(
                                id: document.id,
                                icon: document.icon,
                                title: document.title,
                                subtitle: document.subtitle,
                                detail: "Read",
                                style: .disclosure,
                                isEnabled: true
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    if document.id != SettingsDocument.allCases.last?.id {
                        Divider()
                            .overlay(PCCTheme.ink.opacity(0.08))
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }
}

enum SettingsDocument: String, CaseIterable, Identifiable {
    case terms
    case privacy
    case postingRules
    case paymentRefunds
    case communityStandards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "Terms of Use"
        case .privacy: return "Privacy Policy"
        case .postingRules: return "Community posting rules"
        case .paymentRefunds: return "Payment / refund notes"
        case .communityStandards: return "Community standards"
        }
    }

    var subtitle: String {
        switch self {
        case .terms:
            return "Rules for using the Coast Calendar app and website."
        case .privacy:
            return "How Coast Calendar handles personal information."
        case .postingRules:
            return "What belongs on Coast Calendar."
        case .paymentRefunds:
            return "Subscription and refund notes."
        case .communityStandards:
            return "Keep local listings useful, lawful and respectful."
        }
    }

    var icon: String {
        switch self {
        case .terms: return "doc.text"
        case .privacy: return "lock.shield"
        case .postingRules: return "checklist"
        case .paymentRefunds: return "creditcard.and.123"
        case .communityStandards: return "heart.text.square"
        }
    }

    var paragraphs: [String] {
        switch self {
        case .terms:
            return [
                "Last updated 1 November 2026.",
                "Coast Calendar is a community calendar and organisation directory for the Pōhutukawa Coast and surrounding areas of New Zealand, made by Atlas Digital. By using the Coast Calendar iOS app or the website at coastcalendar.nz (“the Service”), you agree to these Terms of Use.",
                "These Terms are a first-pass draft prepared for the current stage of the Service. They are not legal advice. A qualified New Zealand lawyer should review them before they are treated as final.",
                "1. The Service",
                "The Service lets people browse local what’s-on listings, follow organisations, and (for approved organisations with an active subscription) publish listings, polls and notices. Content is submitted by the community. We do not create or verify the accuracy of listings.",
                "2. Accounts",
                "You may need an account to publish content or manage an organisation. You are responsible for keeping your login details secure and for activity under your account. You must provide accurate information when you register.",
                "3. Listings, polls, notices and organisation content",
                "Organisations and users are responsible for the accuracy, legality and appropriateness of the content they post. Keep listings and organisation details accurate and up to date.",
                "You must not post:",
                "• spam, scams, or misleading content",
                "• content that is harmful, unsafe, illegal, or inappropriate",
                "• content that infringes someone else’s rights",
                "4. Acceptable Use",
                "You agree not to misuse the Service, including by attempting to disrupt it, access it without permission, or use it in a way that harms other users or the community.",
                "5. User-generated content and licence",
                "You keep ownership of the content you post. By posting content on the Service you grant Atlas Digital a non-exclusive, royalty-free licence to host, display, and distribute that content as part of the Service (including on the app and website) for as long as it remains on the Service. You can remove your own content; we may also remove content as described below.",
                "6. Moderation and removal",
                "Support may review, change the status of, or remove listings, polls, notices, photos or accounts that break these Terms or that we reasonably consider harmful to the community or the Service. We do not promise to review all content.",
                "7. Subscriptions and payments",
                "Paid organisation plans are monthly subscriptions that renew automatically until cancelled. You can cancel anytime:",
                "• on iOS, through your Apple ID subscription settings",
                "• on the web, through Stripe (Manage subscription in Settings)",
                "Cancelling stops future renewals. Your plan stays active until the end of the current paid period.",
                "On iOS, payment is charged to your Apple ID and Apple’s standard terms apply. On the web, payments are processed by Stripe. We do not see or store your full card details.",
                "8. Intellectual property",
                "The Coast Calendar name, branding, app, and website are owned by Atlas Digital. You may not copy or reuse them without permission, except for normal personal use of the Service.",
                "9. Disclaimer and limitation of liability",
                "The Service is provided “as is.” Event details come from the community, so always check with the organiser before you go. We work to keep the Service running, but we do not guarantee that it will be uninterrupted, error-free, or that any particular listing is accurate.",
                "To the extent permitted by New Zealand law, Atlas Digital is not liable for any loss or damage arising from your use of the Service or from reliance on community-submitted content. Nothing in these Terms limits rights that cannot be limited under the Consumer Guarantees Act 1993 or other New Zealand law.",
                "10. Account deletion and termination",
                "You can request deletion of your account from Settings in the app or by emailing support@coastcalendar.nz. We will delete your account and personal information except where we need to keep it by law.",
                "We may suspend or close accounts that break these Terms.",
                "11. Changes to these Terms",
                "We may update these Terms from time to time. The “Last updated” date at the top will change. Continued use of the Service after an update means you accept the new Terms.",
                "12. Governing law",
                "These Terms are governed by the laws of New Zealand. Any disputes will be subject to the courts of New Zealand.",
                "13. Contact",
                "Questions about these Terms? Email support@coastcalendar.nz.",
                "Coast Calendar by Atlas Digital"
            ]
        case .privacy:
            return [
                "Last updated 1 November 2026.",
                "Coast Calendar is made by Atlas Digital in New Zealand. This policy covers the Coast Calendar iOS app and the website at coastcalendar.nz (“the Service”).",
                "This is a first-pass draft prepared for the current stage of the Service. It is not legal advice. A qualified New Zealand lawyer should review it before it is treated as final, especially against the Privacy Act 2020.",
                "1. Who we are",
                "Atlas Digital operates Coast Calendar. Contact: support@coastcalendar.nz.",
                "2. What information we collect and store",
                "To make the Service work we store:",
                "• your account email address and display name",
                "• organisation details you provide",
                "• photos you upload",
                "• listings, polls and notices you create",
                "• items you save to My Calendar",
                "• your subscription or purchase status",
                "• basic in-app usage such as listing views and saves (used for app features and simple analytics)",
                "Location is used only while you are using the app or site to pick an area. It is not stored and you are not tracked.",
                "3. Public content",
                "Listings and polls are public when published. Organisation pages, and the photos and details added to them, are also public once published.",
                "4. What we do not do",
                "We do not show ads. We do not sell your data. We do not track you across other apps or websites.",
                "5. Payments",
                "Payments are handled by Apple on iOS and by Stripe on the web. We do not see or store your full card details.",
                "6. Service providers",
                "Your data is stored with our hosting and database providers (Supabase and Cloudflare), who process it only to run the Service. We require them to handle data securely.",
                "7. How long we keep information",
                "We keep account and content information while your account is active or as needed to provide the Service. When you request account deletion we delete your personal information except where we are required to keep it by law (for example, certain financial or legal records).",
                "8. Your rights",
                "Under the New Zealand Privacy Act 2020 you can ask to access or correct personal information we hold about you, and you can make a complaint to the Privacy Commissioner. Email support@coastcalendar.nz to make a request.",
                "9. Deleting your account",
                "You can request account deletion from Settings in the app, or by emailing support@coastcalendar.nz. We will delete your account and personal information except where we need to keep it by law.",
                "10. Children’s privacy",
                "The Service is not directed at children under 13. We do not knowingly collect personal information from children under 13.",
                "11. Changes to this policy",
                "We may update this policy from time to time. The “Last updated” date at the top will change. Continued use of the Service after an update means you accept the new policy.",
                "12. Contact",
                "Questions about privacy? Email support@coastcalendar.nz.",
                "Coast Calendar by Atlas Digital"
            ]
        case .postingRules:
            return [
                "Listings should be local, useful, accurate, and written for the community area selected in the app.",
                "Do not submit misleading, illegal, hateful, unsafe, adult, scam, spam, or abusive content.",
                "Publishing access is limited to approved member accounts with an active subscription. Do not use public community features to submit listings on behalf of an unapproved account.",
                "Images must be relevant to the listing and suitable for a general community audience."
            ]
        case .paymentRefunds:
            return [
                "Approved member accounts must keep an active subscription to publish or run polls.",
                "Payments are handled securely by Apple or the payment provider shown in the app. Coast Calendar does not store card details.",
                "Subscription access does not guarantee attendance, sales, bookings or enquiries.",
                "Refund requests for completed Apple purchases are handled through Apple unless required otherwise by law."
            ]
        case .communityStandards:
            return [
                "Coast Calendar should feel useful, calm and trustworthy for local people.",
                "Be respectful. Do not use listings to harass, shame, mislead, impersonate, spam, or pressure other people.",
                "Keep details current. If your event changes, send an edit request so Support can review it before public details change.",
                "Support may restrict accounts, decline listings, or archive content that puts the community or platform at risk."
            ]
        }
    }
}

struct SettingsDocumentScreen: View {
    let document: SettingsDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(document.title)
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(Self.isSectionHeading(paragraph) ? .headline.weight(.bold) : .body.weight(.medium))
                                    .foregroundStyle(PCCTheme.ink.opacity(Self.isSectionHeading(paragraph) ? 0.9 : 0.72))
                                    .lineSpacing(4)
                            }
                        }
                        .padding(18)
                        .pccCardStyle()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

    private static func isSectionHeading(_ paragraph: String) -> Bool {
        paragraph.range(of: #"^\d+\. "#, options: .regularExpression) != nil
    }
}

struct WallpaperPickerScreen: View {
    @AppStorage(PCCWallpaperStyle.storageKey) private var selectedWallpaper = PCCWallpaperStyle.ornament.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var previewStyle: PCCWallpaperStyle

    init() {
        let stored = UserDefaults.standard.string(forKey: PCCWallpaperStyle.storageKey) ?? PCCWallpaperStyle.ornament.rawValue
        _previewStyle = State(initialValue: PCCWallpaperStyle.style(for: stored))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCWallpaperPreviewBackground(style: previewStyle)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wallpaper")
                                .font(.system(size: 38, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Preview a background before saving it. The original illustrated wallpaper stays available as the default.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }

                        WallpaperPreviewCard(style: previewStyle)

                        VStack(spacing: 10) {
                            ForEach(PCCWallpaperStyle.allCases) { style in
                                Button {
                                    previewStyle = style
                                } label: {
                                    HStack(spacing: 12) {
                                        PCCWallpaperThumb(style: style)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(style.title)
                                                .font(.headline.weight(.black))
                                                .foregroundStyle(PCCTheme.ink)

                                            Text(style == .ornament ? "Swift-drawn pōhutukawa background" : "Photo wallpaper")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(PCCTheme.ink.opacity(0.56))
                                        }

                                        Spacer()

                                        if previewStyle == style {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3.weight(.black))
                                                .foregroundStyle(PCCTheme.leafGreen)
                                        }
                                    }
                                    .padding(12)
                                    .background(.white.opacity(previewStyle == style ? 0.88 : 0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            selectedWallpaper = previewStyle.rawValue
                            dismiss()
                        } label: {
                            Text("Save Wallpaper")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
        }
    }
}

struct PCCWallpaperPreviewBackground: View {
    let style: PCCWallpaperStyle

    var body: some View {
        ZStack {
            if let assetName = style.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.white.opacity(0.34), PCCTheme.cream.opacity(0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                PCCTheme.cream.ignoresSafeArea()
                LinearGradient(
                    colors: [.white.opacity(0.95), PCCTheme.cream.opacity(0.95), Color(red: 0.95, green: 0.91, blue: 0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                PCCWallpaperOrnament()
                    .opacity(0.88)
                    .ignoresSafeArea()
            }
        }
    }
}

struct WallpaperPreviewCard: View {
    let style: PCCWallpaperStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(CommunityArea.appBrandName)
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)

                Spacer()

                Text("Preview")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            }

            Text("Showing: \(CommunityArea.defaultAreaName)")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)

            VStack(alignment: .leading, spacing: 8) {
                Text("Local market day")
                    .font(.title2.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Saturday, 10:00 AM · Beachlands")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
            }
            .padding(14)
            .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct PCCWallpaperThumb: View {
    let style: PCCWallpaperStyle

    var body: some View {
        ZStack {
            if let assetName = style.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                PCCTheme.cream
                PCCWallpaperOrnament()
                    .opacity(0.88)
                    .scaleEffect(0.36)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.88), lineWidth: 1)
        )
    }
}

struct CardTintPickerScreen: View {
    @AppStorage(PCCCardTintStyle.storageKey) private var selectedCardTint = PCCCardTintStyle.clean.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var previewStyle: PCCCardTintStyle

    init() {
        let stored = UserDefaults.standard.string(forKey: PCCCardTintStyle.storageKey) ?? PCCCardTintStyle.clean.rawValue
        _previewStyle = State(initialValue: PCCCardTintStyle.style(for: stored))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Card Colour")
                                .font(.system(size: 38, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Pick a readable card surface for your wallpaper.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                        }

                        CardTintPreviewCard(style: previewStyle)

                        VStack(spacing: 10) {
                            ForEach(PCCCardTintStyle.allCases) { style in
                                Button {
                                    previewStyle = style
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(style.previewColor)
                                            .frame(width: 42, height: 42)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white.opacity(0.92), lineWidth: 2)
                                            )

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(style.title)
                                                .font(.headline.weight(.black))
                                                .foregroundStyle(PCCTheme.ink)

                                            Text(style == .clean ? "Highest contrast default" : "Soft tint, text stays dark")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(PCCTheme.ink.opacity(0.56))
                                        }

                                        Spacer()

                                        if previewStyle == style {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3.weight(.black))
                                                .foregroundStyle(PCCTheme.leafGreen)
                                        }
                                    }
                                    .padding(12)
                                    .background(style.fill, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                                            .stroke(.white.opacity(0.82), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            selectedCardTint = previewStyle.rawValue
                            dismiss()
                        } label: {
                            Text("Save Card Colour")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Card Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
        }
    }
}

struct CardTintPreviewCard: View {
    let style: PCCCardTintStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                Spacer()

                Text(style.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            }

            Text("Beach clean-up morning")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            Text("Saturday, 9:00 AM · Maraetai")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))

            HStack(spacing: 8) {
                Label("Community", systemImage: "person.3.fill")
                Label("Save", systemImage: "bookmark")
            }
            .font(.caption.weight(.black))
            .foregroundStyle(PCCTheme.leafGreen)
        }
        .padding(20)
        .background(style.fill, in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                .stroke(.white.opacity(0.92), lineWidth: 1)
        )
        .shadow(color: PCCTheme.deepGreen.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

struct ContactSupportScreen: View {
    enum Topic: String, CaseIterable, Identifiable {
        case listing = "Listing help"
        case account = "Account"
        case payment = "Payment"
        case safety = "Safety or content"
        case other = "Other"

        var id: String { rawValue }
    }

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var topic: Topic = .listing
    @State private var listingReference = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var supportRequestID: UUID?
    @State private var mySupportRequests: [SupportRequestRecord] = []
    @State private var isLoadingRequests = false
    @State private var errorMessage: String?
    @State private var showAccountAccess = false
    private let service: SupportRequestSubmitting = SupabaseEventService()

    private var canSend: Bool {
        userSessionStore.isSignedIn
            && !isSending
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contact Support")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text("Send a private request to Support. Your message is attached to your app account so we can follow up without showing a personal email in the app.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.66))
                            .lineSpacing(3)

                        VStack(alignment: .leading, spacing: 14) {
                            if !userSessionStore.isSignedIn {
                                Button {
                                    showAccountAccess = true
                                } label: {
                                    Label("Sign in so Support can reply through your app account.", systemImage: "person.crop.circle.badge.exclamationmark")
                                        .font(.subheadline.weight(.black))
                                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .buttonStyle(.plain)
                            }

                            Picker("Topic", selection: $topic) {
                                ForEach(Topic.allCases) { topic in
                                    Text(topic.rawValue).tag(topic)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(PCCTheme.leafGreen)

                            PCCSupportField(title: "Listing reference", text: $listingReference, prompt: "Optional")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Message")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                                TextEditor(text: $message)
                                    .font(.body.weight(.medium))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 130)
                                    .padding(10)
                                    .background(PCCTheme.cream.opacity(0.70), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            }

                            if let supportRequestID {
                                Label("Support request sent. Reference \(supportRequestID.uuidString.prefix(8).uppercased()).", systemImage: "checkmark.seal.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PCCTheme.leafGreen)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PCCTheme.pohutukawaRed)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button {
                                submitSupportRequest()
                            } label: {
                                Label(isSending ? "Sending" : "Send Support Request", systemImage: isSending ? "hourglass" : "paperplane.fill")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            .disabled(!canSend)
                            .opacity(canSend ? 1 : 0.52)
                        }
                        .padding(18)
                        .pccCardStyle()

                        if userSessionStore.isSignedIn {
                            SupportPanel(title: "Your Requests", icon: "bubble.left.and.text.bubble.right.fill", defaultExpanded: true) {
                                if isLoadingRequests {
                                    ProgressView()
                                        .tint(PCCTheme.leafGreen)
                                } else if mySupportRequests.isEmpty {
                                    Text("No support requests yet. Messages you send will appear here with Support replies.")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                                } else {
                                    VStack(spacing: 12) {
                                        ForEach(mySupportRequests.prefix(8)) { request in
                                            UserSupportRequestCard(request: request)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.standardBottomInset)
                .pccScrollableKeyboardDismiss()
                .pccDismissesKeyboardOnTap()
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAccountAccess) {
                AccountAccessSheet()
                    .environmentObject(userSessionStore)
            }
            .task(id: userSessionStore.session?.userID) {
                await loadMySupportRequests()
            }
            .refreshable {
                await loadMySupportRequests()
            }
            .toolbar {
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

    private func submitSupportRequest() {
        guard canSend else { return }

        Task {
            await MainActor.run {
                isSending = true
                errorMessage = nil
                supportRequestID = nil
            }

            do {
                await userSessionStore.refreshIfNeeded()
                guard let session = userSessionStore.session else {
                    throw UserAuthError.signInFailed
                }

                let trimmedReference = listingReference.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestID = try await service.submitSupportRequest(
                    topic: topic.rawValue,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    listingReference: trimmedReference.isEmpty ? nil : trimmedReference,
                    accessToken: session.accessToken
                )

                await MainActor.run {
                    supportRequestID = requestID
                    message = ""
                    listingReference = ""
                    isSending = false
                }
                await loadMySupportRequests()
            } catch {
                await MainActor.run {
                    errorMessage = error.pccUserFacingMessage
                    isSending = false
                }
            }
        }
    }

    @MainActor
    private func loadMySupportRequests() async {
        guard let session = userSessionStore.session else {
            mySupportRequests = []
            isLoadingRequests = false
            return
        }

        let requestedUserID = session.userID
        isLoadingRequests = mySupportRequests.isEmpty
        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            guard activeSession.userID == requestedUserID,
                  userSessionStore.session?.userID == requestedUserID else {
                mySupportRequests = []
                return
            }
            let loaded = try await service.fetchMySupportRequests(
                userID: activeSession.userID,
                accessToken: activeSession.accessToken
            )
            guard userSessionStore.session?.userID == requestedUserID else {
                mySupportRequests = []
                return
            }
            mySupportRequests = loaded
            isLoadingRequests = false
        } catch {
            guard userSessionStore.session?.userID == requestedUserID else { return }
            isLoadingRequests = false
        }
    }
}

struct UserSupportRequestCard: View {
    let request: SupportRequestRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.topic)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Reference \(request.id.uuidString.prefix(8).uppercased())")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.52))
                }

                Spacer()

                Text(request.status.settingsLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(request.status.settingsTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(request.status.settingsTint.opacity(0.10), in: Capsule())
            }

            if let listingReference = request.listingReference, !listingReference.isEmpty {
                Text("Listing \(listingReference)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            Text(request.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            if let supportNote = request.supportNote, !supportNote.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Support replied", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)

                    Text(supportNote)
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            Text(request.updatedAt.formatted(.dateTime.day().month().hour().minute()))
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.44))
        }
        .padding(12)
        .background(PCCTheme.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

private extension SupportRequestStatus {
    var settingsLabel: String {
        switch self {
        case .open: return "Open"
        case .inReview: return "In Review"
        case .closed: return "Closed"
        }
    }

    var settingsTint: Color {
        switch self {
        case .open: return PCCTheme.pohutukawaOrange
        case .inReview: return PCCTheme.leafGreen
        case .closed: return PCCTheme.ink.opacity(0.62)
        }
    }
}

struct BusinessPlansScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var pushNotificationStore: PushNotificationStore
    @EnvironmentObject private var purchaseService: StoreKitPurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BusinessProfileDraft()
    @State private var publicDraft = PublicMemberProfileDraft()
    @State private var serverConfirmedPublicDraft = PublicMemberProfileDraft()
    @State private var publicProfile: PublicBusinessProfileRecord?
    @State private var accountState = BusinessAccountState.empty
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isPurchasing = false
    @State private var isCreatingAccountAndApplying = false
    @State private var message: String?
    @State private var showPublicMemberPage = false
    @State private var showHomePageEditor = false
    @State private var showSubscriptionPaymentSheet = false
    @State private var showValidation = false
    @State private var heroPickerItem: PhotosPickerItem?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var heroPreviewImage: UIImage?
    @State private var avatarPreviewImage: UIImage?
    @State private var pendingHeroImageData: Data?
    @State private var pendingAvatarImageData: Data?
    @State private var isLoadingHeroImage = false
    @State private var isLoadingAvatarImage = false
    @State private var applicationEmail = ""
    @State private var applicationFullName = ""
    @State private var applicationPassword = ""
    @State private var applicationConfirmPassword = ""
    @State private var invalidMembershipFields: Set<String> = []
    @State private var accountValidationMessage: String?
    @State private var showMembershipSubmittedAlert = false
    @State private var membershipSubmittedMessage = ""
    @State private var automaticSubscriptionActivationKey: String?
    @State private var isAutomaticallyActivatingSubscription = false
    @State private var pendingPlanPayment: BusinessSubscriptionPlan?
    @State private var showPlanChangeConfirmation = false
    @State private var pendingPlanSelection: BusinessSubscriptionPlan?
    @State private var showPlanSelectionConfirmation = false
    let onNavigateCreate: () -> Void
    private let service: BusinessAccountManaging & MemberPublicProfileManaging = SupabaseEventService()
    private let subscriptionProcessor = SupabaseAppleBusinessSubscriptionService()

    init(onNavigateCreate: @escaping () -> Void = {}) {
        self.onNavigateCreate = onNavigateCreate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    membershipScreenContent
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationTitle("Member")
            .navigationBarTitleDisplayMode(.inline)
            .pccDismissesKeyboardOnTap()
            .pccKeyboardDoneToolbar {
                UIApplication.pccDismissKeyboard()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .sheet(isPresented: $showPublicMemberPage) {
                if let profile = publicProfile, let userID = userSessionStore.session?.userID {
                    NavigationStack {
                        OrganiserEventsScreen(
                            organiserID: userID,
                            organiserName: profile.displayName,
                            profile: profile,
                            profileID: profile.id
                        )
                    }
                    .environmentObject(userSessionStore)
                } else {
                    MemberPageUnavailableSheet()
                }
            }
            .sheet(isPresented: $showHomePageEditor) {
                NavigationStack {
                    MemberHomePageEditorSheet(
                        draft: $publicDraft,
                        heroPickerItem: $heroPickerItem,
                        avatarPickerItem: $avatarPickerItem,
                        heroPreviewImage: heroPreviewImage,
                        avatarPreviewImage: avatarPreviewImage,
                        isLoadingHeroImage: isLoadingHeroImage,
                        isLoadingAvatarImage: isLoadingAvatarImage,
                        showValidation: showValidation,
                        invalidMembershipFields: invalidMembershipFields,
                        isSaving: isSaving,
                        primaryButtonTitle: homePageActionTitle,
                        heroImageRequest: memberImageRequest(path: publicDraft.heroImagePath),
                        avatarImageRequest: memberImageRequest(path: publicDraft.avatarImagePath),
                        hasUnsavedChanges: homePageHasUnsavedChanges,
                        onDone: {
                            Task { await finishHomePageSetup() }
                        },
                        onDiscard: {
                            discardHomePageDraftChanges()
                        },
                        onRemoveHeroImage: {
                            removeMemberImage(.hero)
                        },
                        onRemoveAvatarImage: {
                            removeMemberImage(.avatar)
                        }
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSubscriptionPaymentSheet) {
                NavigationStack {
                    SubscriptionPaymentSheet(
                        summaryText: subscriptionSummaryText,
                        selectedPlan: accountState.profile?.selectedPlan ?? draft.selectedPlan,
                        activeSubscription: accountState.activeSubscription,
                        content: {
                            monthlyPlansContent
                        }
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Membership submitted", isPresented: $showMembershipSubmittedAlert) {
                Button("Done") {
                    dismiss()
                }
            }
            .alert("Change subscription plan?", isPresented: $showPlanChangeConfirmation, presenting: pendingPlanPayment) { plan in
                Button("Cancel", role: .cancel) {
                    pendingPlanPayment = nil
                }
                Button("Continue") {
                    Task { await performPlanPayment(plan) }
                }
            } message: { plan in
                Text("Paying for \(plan.title) makes it the active plan immediately. Existing published listings keep their previous plan coverage until that paid-through period ends; new listings and future limits use the new plan.")
            }
            .alert("Save this plan?", isPresented: $showPlanSelectionConfirmation, presenting: pendingPlanSelection) { plan in
                Button("No", role: .cancel) {
                    pendingPlanSelection = nil
                }
                Button("Yes") {
                    Task { await saveSelectedPlan(plan) }
                }
            } message: { plan in
                Text("Save \(plan.title) as the plan for this membership. You can then tap Pay to confirm it with Apple.")
            }
            .task {
                await loadBusinessAccount()
                await purchaseService.loadProducts()
                await activatePurchasedSubscriptionIfReady()
            }
            .task(id: userSessionStore.session?.userID) {
                automaticSubscriptionActivationKey = nil
                await loadBusinessAccount()
                await activatePurchasedSubscriptionIfReady()
            }
            .onChange(of: userSessionStore.session?.userID) { _, _ in
                clearAccountOwnedPresentationState()
            }
            .onChange(of: purchaseService.state) { _, newState in
                guard case .awaitingBackendRetry(let productID) = newState else { return }
                Task { await retryBackendActivationIfReady(productID: productID) }
            }
            .onChange(of: purchaseService.purchasedProductIDs) { _, _ in
                Task { await activatePurchasedSubscriptionIfReady() }
            }
            .onChange(of: heroPickerItem) { _, item in
                Task { await loadMemberImage(from: item, kind: .hero) }
            }
            .onChange(of: avatarPickerItem) { _, item in
                Task { await loadMemberImage(from: item, kind: .avatar) }
            }
        }
    }

    private var membershipScreenContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard
            if shouldShowMemberProcessCard {
                memberProcessCard
            }

            membershipStageContent

            if shouldShowStoreKitStatusCard {
                StoreKitStatusCard(state: purchaseService.state) {
                    Task { await purchaseService.loadProducts() }
                }
            }

            if let message {
                SettingsInfoMessage(icon: "info.circle", title: "Member page status", message: message)
            }
        }
    }

    @ViewBuilder
    private var membershipStageContent: some View {
        if !userSessionStore.isSignedIn {
            unsignedMembershipAccountCard
            if canRevealUnsignedMembershipSteps {
                monthlyPlansCard
                unsignedMembershipDetailsCard
            } else {
                SettingsInfoMessage(
                    icon: "lock.open.fill",
                    title: "Start with your account",
                    message: "Enter a real email, a password of at least 6 characters, and a matching confirmation. Then choose your member plan and fill in the application."
                )
            }
        } else {
            memberDashboardCard
            if !userSessionStore.isEmailVerified {
                EmailVerificationRequiredCard(
                    email: userSessionStore.email,
                    title: "Email confirmation",
                    message: "You can submit the membership application now. Email confirmation may still be needed later for account recovery, payment receipts or publishing tools.",
                    resendAction: resendVerificationEmail,
                    refreshAction: refreshVerificationStatus
                )
            }
            if shouldShowFullPlanPicker {
                monthlyPlansCard
            }
            if accountState.profile?.memberStatus != .approved {
                profileCard
            }
            statusCard
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(headerTitle)
                .font(.system(size: 34, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            Text(headerSubtitle)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                .lineSpacing(3)
        }
        .padding(20)
        .pccCardStyle()
    }

    private var headerTitle: String {
        if accountState.profile == nil { return "Register your Organisation" }
        return "Organisation Dashboard"
    }

    private var headerSubtitle: String {
        if accountState.profile == nil {
            return "Register your Organisation. Support approves it, then you subscribe to list."
        }
        if !accountState.hasActiveOrganisationSubscription {
            return "Support approves your organisation first. You choose a monthly plan after that."
        }
        return "Manage your public page, subscription, listings and polls."
    }

    private var shouldShowMemberProcessCard: Bool {
        guard let profile = accountState.profile else { return true }
        return profile.memberStatus != .approved
    }

    private var shouldShowFullPlanPicker: Bool {
        accountState.profile?.memberStatus == .approved
    }

    private var homepageIsReady: Bool {
        !publicDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publicDraft.areaScopeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var homePageActionTitle: String {
        guard accountState.profile != nil else { return "Set up your home page" }
        return homepageIsReady ? "Manage your home page" : "Set up your home page"
    }

    private var memberProcessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            VStack(alignment: .leading, spacing: 9) {
                MembershipStepRow(number: "1", title: "Sign in normally", message: "Use a regular app account first. Browsing, saving and reminders stay separate from membership.")
                MembershipStepRow(number: "2", title: "Register your Organisation", message: "Tell us who you represent and who is authorised to manage the membership. Public homepage details are set up separately.")
                MembershipStepRow(number: "3", title: "Wait for admin approval", message: "Your application shows as pending until Support approves it.")
                MembershipStepRow(number: "4", title: "Use your dashboard", message: "After approval, finish your page, activate the subscription, publish listings and post Notices for followers.")
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var unsignedMembershipAccountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Create account to apply")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Create the account that will manage this membership. These details help Coast Calendar assess and support the application.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.64))
                    .lineSpacing(2)
            }

            BusinessTextField(
                title: "User name",
                text: $applicationFullName,
                required: true,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("accountFullName") ? "Enter the name we should greet you with." : nil
            )
            .textInputAutocapitalization(.words)

            BusinessTextField(
                title: "Email",
                text: $applicationEmail,
                required: true,
                keyboardType: .emailAddress,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("accountEmail") ? accountValidationMessage ?? "Enter a real email address." : nil
            )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            membershipSecureField(title: "Password", prompt: "At least 6 characters", text: $applicationPassword)
            membershipSecureField(title: "Confirm password", prompt: "Confirm password", text: $applicationConfirmPassword)

            if !applicationConfirmPassword.isEmpty, applicationPassword != applicationConfirmPassword {
                Label("Passwords do not match yet.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            } else if canRevealUnsignedMembershipSteps {
                Label("Account details ready. Choose a member plan next.", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var memberDashboardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(memberDashboardTitle)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                    Text(memberDashboardSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }

                Spacer()

                Text(memberDashboardStage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(memberDashboardTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(memberDashboardTint.opacity(0.10), in: Capsule())
            }

            VStack(spacing: 10) {
                MemberDashboardActionRow(
                    icon: "person.text.rectangle.fill",
                    title: homePageActionTitle,
                    value: homepageIsReady ? "Public page ready" : "Add a public name and location",
                    tint: PCCTheme.leafGreen,
                    action: { showHomePageEditor = true }
                )

                if accountState.canSubmitAsOrganisation {
                    MemberDashboardActionRow(
                        icon: "plus.circle.fill",
                        title: "Create",
                        value: "Listings and polls live in the Create tab",
                        tint: PCCTheme.ink.opacity(0.72),
                        action: {
                            dismiss()
                            onNavigateCreate()
                        }
                    )
                }
            }

            Text(memberDashboardMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .lineSpacing(2)
        }
        .padding(18)
        .pccCardStyle()
    }

    private var subscriptionPlanSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscription plan")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                    Text(subscriptionSummaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }

                Spacer()

                if let active = accountState.activeSubscription, let plan = active.plan {
                    Text(plan.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                }
            }

            if let active = accountState.activeSubscription {
                SubscriptionFactRow(title: "Status", value: active.status.capitalized)
                SubscriptionFactRow(title: active.status == "cancelled" ? "Active until" : "Renews or paid through", value: active.currentPeriodEnd?.formatted(date: .abbreviated, time: .omitted) ?? "Not available")
                SubscriptionFactRow(title: "Auto-renew", value: active.status == "cancelled" ? "Off" : "Managed by Apple")
            } else {
                SettingsInfoMessage(
                    icon: "creditcard.fill",
                    title: "No active subscription",
                    message: "After approval, choose a monthly plan below. Apple manages subscription changes and cancellation."
                )
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var unsignedMembershipDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Application details")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Tell us who you represent and who is authorised to manage this member account. Your public homepage is set up separately after approval.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineSpacing(2)
            }

            Text("Selected plan: \(draft.selectedPlan.title)")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())

            Text("Optional photos")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink)
            Text("Add a banner and profile image now if you have them. They seed the public homepage after Support approves. You can skip this.")
                .font(.caption.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))

            MemberImageEditorPanel(
                title: "Banner image",
                emptyTitle: "Add banner image (optional)",
                imageRequest: memberImageRequest(path: publicDraft.heroImagePath),
                previewImage: heroPreviewImage,
                pickerItem: $heroPickerItem,
                isLoading: isLoadingHeroImage,
                positionX: $publicDraft.heroImagePositionX,
                positionY: $publicDraft.heroImagePositionY,
                aspectRatio: 1.55,
                isCircular: false,
                showValidation: false,
                onRemove: { removeMemberImage(.hero) }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 180)

            HStack {
                MemberImageEditorPanel(
                    title: "Profile image",
                    emptyTitle: "Add profile image (optional)",
                    imageRequest: memberImageRequest(path: publicDraft.avatarImagePath),
                    previewImage: avatarPreviewImage,
                    pickerItem: $avatarPickerItem,
                    isLoading: isLoadingAvatarImage,
                    positionX: $publicDraft.avatarImagePositionX,
                    positionY: $publicDraft.avatarImagePositionY,
                    aspectRatio: 1,
                    isCircular: true,
                    showValidation: false,
                    onRemove: { removeMemberImage(.avatar) }
                )
                .frame(width: 120, height: 120)
                Spacer()
            }

            BusinessTextField(
                title: "Organisation name",
                text: $draft.name,
                required: true,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("memberName") ? "Add the school, club, business, group or person represented." : nil
            )
            BusinessOrganisationTypePicker(
                selection: $draft.organisationType,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("organisationType") ? "Choose the type that best fits this membership." : nil
            )
            BusinessTextField(
                title: "Application contact email",
                text: $draft.email,
                required: true,
                keyboardType: .emailAddress,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("contactEmail") ? "Enter a valid email address, like name@example.co.nz." : nil
            )
            BusinessTextField(title: "Public contact person", text: $draft.contactName, required: true, showValidation: showValidation)
            BusinessTextField(title: "Application phone", text: $draft.phone, required: false, keyboardType: .phonePad, showValidation: showValidation)
            BusinessTextField(title: "Business, school or group address", text: $draft.address, required: false, showValidation: showValidation)
            BusinessWebsiteField(
                urlText: websiteInputBinding,
                showValidation: invalidMembershipFields.contains("website"),
                validationMessage: invalidMembershipFields.contains("website") ? "Add the website after https://www., like test.co.nz, or leave only the prefix." : nil
            )
            BusinessMultilineField(title: "Application note", text: $draft.about, prompt: "Tell Support enough to assess the application, including your connection to the organisation or member.")

            Button {
                Task { await createAccountAndSubmitMembership() }
            } label: {
                Label(isCreatingAccountAndApplying ? "Submitting" : "Submit to create account and apply for membership", systemImage: isCreatingAccountAndApplying ? "hourglass" : "checkmark.seal.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(PCCTheme.leafGreen)
            .disabled(isCreatingAccountAndApplying)
        }
        .padding(18)
        .pccCardStyle()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
            Text("Member page editor")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)
                Spacer()
                if let profile = accountState.profile {
                    Text(profile.memberStatus.displayTitle)
                        .font(.caption.weight(.black))
                        .foregroundStyle(profile.memberStatus == .approved ? PCCTheme.leafGreen : PCCTheme.pohutukawaOrange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((profile.memberStatus == .approved ? PCCTheme.leafGreen : PCCTheme.pohutukawaOrange).opacity(0.10), in: Capsule())
                }
            }

            Text("This becomes the live page locals see when they tap your host profile. Use the web member page editor for profile photo, hero photo and positioning so the page matches what locals will see.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .lineSpacing(2)

            BusinessTextField(
                title: "Organisation name",
                text: $draft.name,
                required: true,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("memberName") ? "Add the school, club, business or group name." : nil
            )
            BusinessOrganisationTypePicker(
                selection: $draft.organisationType,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("organisationType") ? "Choose the type that best fits this membership." : nil
            )
            BusinessTextField(
                title: "Contact email",
                text: $draft.email,
                required: true,
                keyboardType: .emailAddress,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("contactEmail") ? "Enter a valid email address, like name@example.co.nz." : nil
            )
            BusinessTextField(title: "Public contact person", text: $draft.contactName, required: true, showValidation: showValidation)
            BusinessTextField(title: "Phone", text: $draft.phone, required: false, keyboardType: .phonePad, showValidation: showValidation)
            BusinessTextField(title: "Address", text: $draft.address, required: false, showValidation: showValidation)
            BusinessWebsiteField(
                urlText: websiteInputBinding,
                showValidation: invalidMembershipFields.contains("website"),
                validationMessage: invalidMembershipFields.contains("website") ? "Add the website after https://www., like test.co.nz, or leave only the prefix." : nil
            )
            BusinessMultilineField(title: "Bio", text: $draft.about, prompt: "What should locals know about this member?")

            Picker("Monthly plan", selection: $draft.selectedPlan) {
                ForEach(BusinessSubscriptionPlan.allCases) { plan in
                    Text("\(plan.title) \(plan.priceText)").tag(plan)
                }
            }
            .pickerStyle(.menu)
            .tint(PCCTheme.leafGreen)
            .padding(12)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            Button {
                Task { await saveProfile() }
            } label: {
                Label(isSaving ? "Saving" : accountState.profile == nil ? "Submit membership application" : "Save membership page", systemImage: "checkmark.seal.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(PCCTheme.leafGreen)
            .disabled(isSaving)

            if accountState.profile != nil {
                Button {
                    showPublicMemberPage = true
                } label: {
                    Label("Preview public member page", systemImage: "person.crop.rectangle.stack")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(PCCTheme.pohutukawaOrange)
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var noticesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "newspaper.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notices And Weekly Letters")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                    Text("A lighter, safer tool than a blank document editor: choose a template, add words and photos, then publish to people who Belong to or follow your page.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .lineSpacing(2)
                }
            }

            VStack(spacing: 9) {
                NoticeTemplateRow(
                    icon: "doc.text.image.fill",
                    title: "Weekly Letter",
                    message: "Best for schools, centres and clubs sending a regular update."
                )
                NoticeTemplateRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Photo Update",
                    message: "Hero image, short story, caption and optional action."
                )
                NoticeTemplateRow(
                    icon: "pin.square.fill",
                    title: "Notice Board",
                    message: "Short community notices with date, location and contact."
                )
            }

            SettingsInfoMessage(
                icon: "checkmark.seal.fill",
                title: "Use the web dashboard for Notices",
                message: "Create weekly letters and member updates from the web dashboard with fixed templates and image slots so they stay clean for people who Belong to your page."
            )
        }
        .padding(18)
        .pccCardStyle()
    }

    private var monthlyPlansCard: some View {
        monthlyPlansContent
            .padding(18)
            .pccCardStyle()
    }

    private var monthlyPlansContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monthly member plans")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(accountState.activeSubscription == nil
                 ? "Support approves your organisation first. You choose a monthly plan after that."
                 : "Changing plan replaces your current subscription and may start a new Apple charge. Confirm on the Apple sheet before you continue.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .lineSpacing(2)

            ForEach(BusinessSubscriptionPlan.allCases) { plan in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.title)
                                .font(.title3.weight(.black))
                                .foregroundStyle(PCCTheme.ink)
                            Text(plan.audience)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        }
                        Spacer()
                        Text(purchaseService.businessProductSummary(for: plan)?.displayPrice ?? plan.priceText)
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.pohutukawaOrange)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(plan.inclusions, id: \.self) { inclusion in
                            Label(inclusion, systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        }
                    }

                    HStack(spacing: 8) {
                        Text(plan.tagText)
                            .font(.caption.weight(.black))
                            .foregroundStyle(draft.selectedPlan == plan ? .white : PCCTheme.leafGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(draft.selectedPlan == plan ? PCCTheme.leafGreen : PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                        Text("\(plan.activeListingLimit) active listing\(plan.activeListingLimit == 1 ? "" : "s") or poll\(plan.activeListingLimit == 1 ? "" : "s")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.55))
                    }

                    planActionButtons(for: plan)
                }
                .padding(14)
                .background(draft.selectedPlan == plan ? PCCTheme.leafGreen.opacity(0.08) : .white.opacity(0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        .stroke(draft.selectedPlan == plan ? PCCTheme.leafGreen.opacity(0.45) : .clear, lineWidth: 1.5)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current status")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            if let active = accountState.activeSubscription, let plan = active.plan {
                SettingsInfoMessage(icon: "checkmark.seal.fill", title: "\(plan.title) active", message: "Subscription status is \(active.status). Limit: \(active.activeListingLimit) active listing\(active.activeListingLimit == 1 ? "" : "s") or poll\(active.activeListingLimit == 1 ? "" : "s").")
            } else if let attention = accountState.subscriptionNeedingBackendAttention, attention.plan != nil {
                SettingsInfoMessage(icon: "exclamationmark.triangle.fill", title: "Publishing is not unlocked yet", message: "Apple has taken the payment, but publishing is not unlocked yet. Open Membership and try again, or contact Support.")
            } else if let profile = accountState.profile, profile.memberStatus == .pendingReview {
                SettingsInfoMessage(icon: "clock.badge.checkmark", title: "Application submitted", message: "Your membership application is pending review by Pōhutukawa Coast Calendar Support. We'll let you know when it has been reviewed.")
            } else if let profile = accountState.profile, profile.memberStatus == .approved {
                SettingsInfoMessage(icon: "checkmark.seal.fill", title: "Approved - finish your page", message: profile.supportNote ?? "Add or check your profile image, hero image, bio and contact details, then complete the selected monthly subscription to activate publishing access.")
            } else if let profile = accountState.profile, profile.memberStatus == .rejected {
                SettingsInfoMessage(icon: "exclamationmark.triangle.fill", title: "Needs changes", message: profile.rejectionReason ?? profile.supportNote ?? "Support requested changes before this member profile can be approved.")
            } else if let profile = accountState.profile, profile.memberStatus == .suspended {
                SettingsInfoMessage(icon: "pause.circle.fill", title: "Publishing suspended", message: profile.suspensionReason ?? profile.supportNote ?? "Support has paused publishing access for this member profile.")
            } else if let localPlan = BusinessSubscriptionPlan.allCases.first(where: { purchaseService.purchasedProductIDs.contains($0.productID) }) {
                SettingsInfoMessage(icon: "checkmark.circle.fill", title: "\(localPlan.title) purchased", message: "Apple reports this subscription active on this device. The app will verify it with the server and refresh publishing access.")
            } else {
                SettingsInfoMessage(icon: "checkmark.seal", title: "No member application", message: "Submit a member profile and selected plan for Support approval.")
            }

            if !accountState.sponsorRequests.isEmpty {
                ForEach(accountState.sponsorRequests.prefix(3)) { request in
                    HStack {
                        Text(FoundingSponsorPackage(rawValue: request.packageID)?.title ?? request.packageID)
                            .font(.caption.weight(.bold))
                        Spacer()
                        Text(request.status.capitalized)
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.pohutukawaOrange)
                    }
                }
            }
        }
        .padding(18)
        .pccCardStyle()
    }

    private var trimmedApplicationEmail: String {
        applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRevealUnsignedMembershipSteps: Bool {
        membershipValidationTrace(includeAccountEmail: true).accountEmailAccepted == true
        && applicationPassword.count >= 6
        && applicationPassword == applicationConfirmPassword
    }

    private var shouldShowStoreKitStatusCard: Bool {
        switch purchaseService.state {
        case .failed, .productsUnavailable:
            return true
        default:
            return false
        }
    }

    private var websiteInputBinding: Binding<String> {
        Binding(
            get: {
                draft.website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "https://www."
                    : draft.website
            },
            set: { draft.website = $0 }
        )
    }

    private func membershipSecureField(title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))

            SecureField(prompt, text: text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(PCCTheme.ink)
                .tint(PCCTheme.leafGreen)
                .padding(13)
                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
    }

    @MainActor
    private func loadBusinessAccount() async {
        guard userSessionStore.session != nil else {
            clearAccountOwnedPresentationState()
            isLoading = false
            return
        }

        let requestContext = userSessionStore.captureAccountContext()
        isLoading = true
        defer { isLoading = false }

        await userSessionStore.refreshIfNeeded()
        guard let activeSession = userSessionStore.session,
              activeSession.userID == requestContext.userID else {
            clearAccountOwnedPresentationState()
            return
        }
        let activeContext = userSessionStore.captureAccountContext()

        do {
            let loaded = try await service.fetchBusinessAccount(userID: activeSession.userID, accessToken: activeSession.accessToken)
            guard userSessionStore.isCurrent(activeContext) else {
                return
            }
            accountState = loaded
#if DEBUG
            print("[Membership] loaded profileStatus=\(loaded.profile?.status ?? "none") selectedPlan=\(loaded.profile?.selectedPlanID ?? "none") subscriptions=\(loaded.subscriptions.map { "\($0.planID):\($0.status):start=\($0.currentPeriodStart?.description ?? "nil"):end=\($0.currentPeriodEnd?.description ?? "nil")" }.joined(separator: " | ")) active=\(loaded.activeSubscription?.planID ?? "none") attention=\(loaded.subscriptionNeedingBackendAttention?.planID ?? "none")")
#endif
            if let profile = loaded.profile {
                draft = BusinessProfileDraft(
                    name: profile.businessName,
                    organisationType: profile.organisationType,
                    contactName: profile.contactName ?? "",
                    email: profile.contactEmail,
                    phone: profile.phone ?? "",
                    address: profile.address ?? "",
                    website: profile.website ?? "",
                    about: profile.about ?? "",
                    areaScopeID: profile.areaScopeID,
                    selectedPlan: profile.selectedPlan,
                    heroImageURL: profile.heroImageURL ?? "",
                    avatarImageURL: profile.avatarImageURL ?? "",
                    heroImagePositionX: profile.heroImagePositionX,
                    heroImagePositionY: profile.heroImagePositionY,
                    avatarImagePositionX: profile.avatarImagePositionX,
                    avatarImagePositionY: profile.avatarImagePositionY,
                    notes: ""
                )
                await loadPublicMemberProfileDraft(
                    profileID: profile.id,
                    accessToken: activeSession.accessToken,
                    context: activeContext
                )
            } else if draft.email.isEmpty {
                draft.email = activeSession.email ?? ""
                publicProfile = nil
                publicDraft = PublicMemberProfileDraft()
                serverConfirmedPublicDraft = PublicMemberProfileDraft()
                clearPendingMemberImages()
            }
        } catch {
            guard userSessionStore.isCurrent(activeContext) else { return }
            message = "Business account details could not be loaded: \(error.pccUserFacingMessage)"
        }
    }

    @MainActor
    private func clearAccountOwnedPresentationState() {
        accountState = .empty
        draft = BusinessProfileDraft()
        publicDraft = PublicMemberProfileDraft()
        serverConfirmedPublicDraft = PublicMemberProfileDraft()
        publicProfile = nil
        clearPendingMemberImages()
        showHomePageEditor = false
        showPublicMemberPage = false
        showSubscriptionPaymentSheet = false
        pendingPlanPayment = nil
        pendingPlanSelection = nil
        isSaving = false
        isPurchasing = false
        message = nil
    }

    @MainActor
    private func createAccountAndSubmitMembership() async {
        guard !isCreatingAccountAndApplying else { return }

        showValidation = true
        invalidMembershipFields = []
        accountValidationMessage = nil

        let accountTrace = membershipValidationTrace(includeAccountEmail: true)
        logMembershipValidationTrace(accountTrace, context: "createAccountAndSubmitMembership.account")

        guard accountTrace.accountEmailAccepted == true else {
            invalidMembershipFields.insert("accountEmail")
            accountValidationMessage = "Enter a valid email address, like name@example.co.nz."
            message = accountValidationMessage
            return
        }

        let trimmedAccountName = applicationFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAccountName.count >= 2 else {
            invalidMembershipFields.insert("accountFullName")
            message = "Enter the name we should greet you with."
            return
        }

        guard applicationPassword.count >= 6 else {
            message = "Create a password with at least 6 characters."
            return
        }

        guard applicationPassword == applicationConfirmPassword else {
            message = "Passwords do not match yet."
            return
        }

        if draft.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.email = trimmedApplicationEmail
        }

        guard validateMembershipDetails() else {
            return
        }
        normalizeMembershipContactEmail()
        normalizeWebsiteDraft()

        isCreatingAccountAndApplying = true
        defer { isCreatingAccountAndApplying = false }

        do {
            try await userSessionStore.signUp(email: trimmedApplicationEmail, password: applicationPassword, fullName: applicationFullName)
        } catch UserAuthError.signUpNeedsConfirmation {
            applicationPassword = ""
            applicationConfirmPassword = ""
            invalidMembershipFields.insert("accountEmail")
            accountValidationMessage = "Check this email inbox to confirm your account, then sign in and submit the membership application."
            message = accountValidationMessage
            return
        } catch {
            handleAccountCreationError(error)
            return
        }

        applicationPassword = ""
        applicationConfirmPassword = ""

        await userSessionStore.refreshIfNeeded()

        guard let session = userSessionStore.session else {
            message = "Account created. Sign in, then submit the membership application."
            return
        }
        let requestContext = userSessionStore.captureAccountContext()

        do {
            let profile = try await service.upsertBusinessProfile(draft, ownerUserID: session.userID, accessToken: session.accessToken)
            guard userSessionStore.isCurrent(requestContext) else { return }
            accountState.profile = profile
            seedPublicDraftFromApplicationIfNeeded()
            if pendingHeroImageData != nil || pendingAvatarImageData != nil {
                await finishHomePageSetup()
            }
            await refreshMembershipApplicationAfterSave(profile: profile, session: session)
            let notificationsReady = await pushNotificationStore.prepareForMembershipDecisionNotifications(
                session: session,
                context: requestContext
            )
            guard userSessionStore.isCurrent(requestContext) else { return }
            finishMembershipSubmission(
                notificationsReady: notificationsReady,
                messagePrefix: "Account created and membership submitted.",
                emailVerificationNeeded: !session.isEmailVerified
            )
        } catch {
            handleMembershipSaveError(error)
        }
    }

    @MainActor
    private func saveProfile() async {
        if !userSessionStore.isEmailVerified,
           let profile = accountState.profile,
           profile.memberStatus == .approved {
            message = "Verify your email before editing an approved member page."
            return
        }
        showValidation = true
        guard validateMembershipDetails() else {
            return
        }
        normalizeMembershipContactEmail()
        normalizeWebsiteDraft()
        guard let session = userSessionStore.session else { return }
        isSaving = true
        defer { isSaving = false }
        let requestContext = userSessionStore.captureAccountContext()

        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? session
        guard userSessionStore.isCurrent(requestContext),
              Optional(activeSession.userID) == requestContext.userID else { return }

        do {
            let profile = try await service.upsertBusinessProfile(draft, ownerUserID: activeSession.userID, accessToken: activeSession.accessToken)
            guard userSessionStore.isCurrent(requestContext) else { return }
            let wasFirstSubmission = accountState.profile == nil
            accountState.profile = profile
            await refreshMembershipApplicationAfterSave(profile: profile, session: activeSession)
            let notificationsReady = await pushNotificationStore.prepareForMembershipDecisionNotifications(
                session: activeSession,
                context: requestContext
            )
            guard userSessionStore.isCurrent(requestContext) else { return }
            if wasFirstSubmission {
                finishMembershipSubmission(
                    notificationsReady: notificationsReady,
                    messagePrefix: "Membership submitted.",
                    emailVerificationNeeded: !activeSession.isEmailVerified
                )
            } else {
                message = "Member page saved."
            }
        } catch {
            handleMembershipSaveError(error)
        }
    }

    @MainActor
    private func finishMembershipSubmission(notificationsReady: Bool, messagePrefix: String, emailVerificationNeeded: Bool) {
        applicationEmail = ""
        applicationPassword = ""
        applicationConfirmPassword = ""
        invalidMembershipFields = []
        accountValidationMessage = nil
        showValidation = false

        let notificationLine = notificationsReady
            ? "You will get a notification when Support makes a decision."
            : "You will get an in-app notification when Support makes a decision. Turn on iPhone notifications if you also want an alert."
        let verificationLine = emailVerificationNeeded
            ? " You can confirm your email later if the app asks before payment or publishing."
            : ""
        let successMessage = "\(messagePrefix) \(notificationLine)\(verificationLine)"
        message = successMessage
        membershipSubmittedMessage = successMessage
        showMembershipSubmittedAlert = true
    }

    @MainActor
    private func refreshMembershipApplicationAfterSave(profile: BusinessProfileRecord, session: UserSession) async {
        do {
            let loaded = try await service.fetchBusinessAccount(userID: session.userID, accessToken: session.accessToken)
            guard loaded.profile != nil else {
                accountState.profile = profile
#if DEBUG
                print("[Membership] saved profile id=\(profile.id) but follow-up owner RPC returned no profile")
#endif
                return
            }
            accountState = loaded
        } catch {
            accountState.profile = profile
#if DEBUG
            print("[Membership] saved profile id=\(profile.id) but follow-up account refresh failed: \(error)")
#endif
        }
    }

    @MainActor
    private func loadPublicMemberProfileDraft(profileID: UUID, accessToken: String, context: UserAccountContext) async {
        do {
            let loadedPublicProfile = try await service.fetchOwnPublicProfileDraft(
                profileID: profileID,
                accessToken: accessToken
            )
            guard userSessionStore.isCurrent(context) else { return }
            publicProfile = loadedPublicProfile
            let loadedDraft = loadedPublicProfile.map(PublicMemberProfileDraft.init(profile:)) ?? PublicMemberProfileDraft()
            publicDraft = loadedDraft
            serverConfirmedPublicDraft = loadedDraft
            clearPendingMemberImages()
        } catch {
            guard userSessionStore.isCurrent(context) else { return }
            publicProfile = nil
            publicDraft = PublicMemberProfileDraft()
            serverConfirmedPublicDraft = PublicMemberProfileDraft()
            clearPendingMemberImages()
#if DEBUG
            print("[Membership] public profile draft refresh failed for profileID=\(profileID): \(error)")
#endif
            if accountState.profile != nil {
                message = "Member page details could not be refreshed. Your membership application status is still shown here."
            }
        }
    }

    @MainActor
    private func handleMembershipSaveError(_ error: Error) {
        let friendlyMessage = error.pccUserFacingMessage
        let lowercased = friendlyMessage.lowercased()
        let trace = membershipValidationTrace(includeAccountEmail: !userSessionStore.isSignedIn)
        logMembershipValidationTrace(trace, context: "handleMembershipSaveError")
        invalidMembershipFields = []
        accountValidationMessage = nil

        if trace.formIsValid,
           (lowercased.contains("permission")
            || lowercased.contains("access")
            || lowercased.contains("verify your email")
            || lowercased.contains("membership approval")
            || lowercased.contains("subscription state")
            || lowercased.contains("row-level security")) {
            message = "The application details look valid, but the application could not be saved. Support should check the membership application rule."
            return
        }

        if lowercased.contains("already has an account")
            || lowercased.contains("confirm your account")
            || lowercased.contains("session has expired")
            || (lowercased.contains("sign in") && !trace.formIsValid) {
            handleAccountCreationError(error)
            return
        }

        if lowercased.contains("organisation")
            || lowercased.contains("required field is missing")
            || lowercased.contains("required")
            || lowercased.contains("missing") {
            invalidMembershipFields = trace.blockingFields
            if invalidMembershipFields.contains("organisationType") {
                message = "Choose the organisation type before submitting."
                return
            }
        }

        if (lowercased.contains("email") || lowercased.contains("contact")),
           !trace.contactEmailAccepted {
            invalidMembershipFields.insert("contactEmail")
        }

        if lowercased.contains("website") || lowercased.contains("url") {
            invalidMembershipFields.insert("website")
        }

        if invalidMembershipFields.isEmpty,
           lowercased.contains("one field has a value the app cannot accept") || lowercased.contains("something in the form needs fixing") {
            invalidMembershipFields = trace.blockingFields
            message = trace.formIsValid
                ? "The application details look valid, but the application could not be saved. Support should check the membership application rule."
                : "The form needs one more required field before it can be saved."
            return
        }

        message = membershipUserFacingMessage(for: error, fallback: friendlyMessage)
    }

    private func membershipUserFacingMessage(for error: Error, fallback: String) -> String {
        let lowercased = fallback.lowercased()
        if lowercased.contains("out of step") || lowercased.contains("database") {
#if DEBUG
            print("[Membership] technical membership error hidden from applicant: \(error)")
#endif
            return "The membership service could not finish that request. Please try again now. If it keeps happening, Support can check your membership setup."
        }
        return fallback
    }

    @MainActor
    private func handleAccountCreationError(_ error: Error) {
        let friendlyMessage = error.pccUserFacingMessage
        invalidMembershipFields = ["accountEmail"]
        accountValidationMessage = friendlyMessage
        message = friendlyMessage
    }

    @MainActor
    private func validateMembershipDetails() -> Bool {
        let trace = membershipValidationTrace(includeAccountEmail: false)
        logMembershipValidationTrace(trace, context: "validateMembershipDetails")
        invalidMembershipFields = trace.blockingFields

        if invalidMembershipFields.contains("memberName") {
            message = "Add the member name before submitting."
            return false
        }

        if invalidMembershipFields.contains("organisationType") {
            message = "Choose the organisation type before submitting."
            return false
        }

        if invalidMembershipFields.contains("contactEmail") {
            message = "Enter a valid contact email for Support before submitting."
            return false
        }

        if invalidMembershipFields.contains("website") {
            message = "Fix the website field or leave it blank before submitting."
            return false
        }

        message = nil
        return true
    }

    private func membershipValidationTrace(includeAccountEmail: Bool) -> MembershipApplicationValidationTrace {
        MembershipApplicationValidationTrace.evaluate(
            accountEmail: includeAccountEmail ? applicationEmail : nil,
            draft: draft,
            websiteAccepted: isUsableWebsite(draft.website.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private func logMembershipValidationTrace(_ trace: MembershipApplicationValidationTrace, context: String) {
#if DEBUG
        print("[MembershipValidation] context=\(context) rawAccountEmail=\(trace.rawAccountEmail ?? "nil") trimmedAccountEmail=\(trace.trimmedAccountEmail ?? "nil") accountEmailAccepted=\(trace.accountEmailAccepted.map(String.init(describing:)) ?? "nil") rawContactEmail=\(trace.rawContactEmail) trimmedContactEmail=\(trace.trimmedContactEmail) contactEmailAccepted=\(trace.contactEmailAccepted) organisationType=\(trace.payloadOrganisationType ?? "nil") formIsValid=\(trace.formIsValid) blockingFields=\(trace.blockingFields.sorted().joined(separator: ","))")
#endif
    }

    private func isUsableWebsite(_ website: String) -> Bool {
        let suffix = websiteSuffix(from: website)
        guard !suffix.isEmpty else { return true }
        guard !suffix.contains(" "),
              let host = suffix.split(separator: "/", maxSplits: 1).first,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix(".") else {
            return false
        }

        return true
    }

    private func normalizeWebsiteDraft() {
        draft.website = normalizedWebsiteURL(from: draft.website)
    }

    private func normalizeMembershipContactEmail() {
        draft.email = MembershipContactEmailValidator.normalized(draft.email)
    }

    private func normalizedWebsiteURL(from website: String) -> String {
        let suffix = websiteSuffix(from: website)
        guard !suffix.isEmpty else { return "" }
        return "https://www.\(suffix)"
    }

    private func websiteSuffix(from website: String) -> String {
        var value = website.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }

        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }

        while value.hasPrefix("/") {
            value.removeFirst()
        }

        return value
    }

    @MainActor
    private func purchaseSubscription(_ plan: BusinessSubscriptionPlan) async {
        guard userSessionStore.isEmailVerified else {
            message = "Verify your email before starting a subscription."
            return
        }
        guard draft.hasMinimumRequiredFields else {
            showValidation = true
            message = "Finish the required member page details before paying."
            return
        }
        if accountState.profile == nil {
            await saveProfile()
        }
        guard accountState.profile != nil else { return }
        guard accountState.canCompleteSubscription else {
            message = "Support must approve this member profile before you can complete the subscription."
            return
        }
        guard let session = userSessionStore.session else {
            message = "Your session expired. Please sign in again."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }
        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? session

        do {
            guard let profile = accountState.profile else { return }
            let intent = AppleBusinessSubscriptionIntent(
                businessProfileID: profile.id,
                plan: plan,
                userID: activeSession.userID
            )
            let result: AppleBusinessSubscriptionBackendResult?
            if purchaseService.purchasedProductIDs.contains(plan.productID) {
                result = try await purchaseService.activateExistingBusinessSubscription(
                    plan,
                    intent: intent,
                    accessToken: activeSession.accessToken,
                    processor: subscriptionProcessor
                )
            } else {
                result = try await purchaseService.purchaseBusinessSubscription(
                    plan,
                    intent: intent,
                    accessToken: activeSession.accessToken,
                    processor: subscriptionProcessor
                )
            }
            if let result {
                message = subscriptionActivationMessage(for: result, plan: plan)
                await loadBusinessAccount()
                finishSubscriptionFlowIfActive(result)
            } else if purchaseService.state == .cancelled {
                message = "\(membershipApprovedPaymentPrefix(for: plan)) The subscription was cancelled and nothing was charged. Try payment again to activate publishing."
            } else if purchaseService.state == .pending {
                message = "\(membershipApprovedPaymentPrefix(for: plan)) Apple marked this subscription as pending. Publishing activates after the payment is confirmed."
            }
        } catch {
            message = "\(membershipApprovedPaymentPrefix(for: plan)) Payment was unsuccessful. Try again to activate publishing. \(error.pccUserFacingMessage)"
        }
    }

    @MainActor
    private func retryBackendActivationIfReady(productID: String) async {
        guard !isPurchasing,
              let plan = BusinessSubscriptionPlan.plan(forProductID: productID),
              userSessionStore.isEmailVerified,
              accountState.canCompleteSubscription,
              let profile = accountState.profile,
              let session = userSessionStore.session else {
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? session
        let intent = AppleBusinessSubscriptionIntent(
            businessProfileID: profile.id,
            plan: plan,
            userID: activeSession.userID
        )

        do {
            let result = try await purchaseService.activateExistingBusinessSubscription(
                plan,
                intent: intent,
                accessToken: activeSession.accessToken,
                processor: subscriptionProcessor
            )
            message = result.map { subscriptionActivationMessage(for: $0, plan: plan) } ?? "\(plan.title) is active."
            await loadBusinessAccount()
            if let result {
                finishSubscriptionFlowIfActive(result)
            }
        } catch {
            message = "Subscription activation needs a retry: \(error.pccUserFacingMessage)"
        }
    }

    @MainActor
    private func activatePurchasedSubscriptionIfReady() async {
        guard !isPurchasing,
              !isAutomaticallyActivatingSubscription,
              accountState.activeSubscription == nil,
              userSessionStore.isEmailVerified,
              accountState.canCompleteSubscription,
              let profile = accountState.profile,
              let session = userSessionStore.session else {
            return
        }

        let plan = profile.selectedPlan
        guard purchaseService.purchasedProductIDs.contains(plan.productID) else { return }

        let activationKey = "\(session.userID.uuidString)-\(profile.id.uuidString)-\(plan.productID)"
        guard automaticSubscriptionActivationKey != activationKey else { return }
        automaticSubscriptionActivationKey = activationKey

        isAutomaticallyActivatingSubscription = true
        defer { isAutomaticallyActivatingSubscription = false }

        message = "Apple purchase found. Activating your membership now."
        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? session
        guard activeSession.userID == session.userID else { return }

        let intent = AppleBusinessSubscriptionIntent(
            businessProfileID: profile.id,
            plan: plan,
            userID: activeSession.userID
        )

        do {
            let result = try await purchaseService.activateExistingBusinessSubscription(
                plan,
                intent: intent,
                accessToken: activeSession.accessToken,
                processor: subscriptionProcessor
            )
            message = result.map { subscriptionActivationMessage(for: $0, plan: plan) } ?? "\(plan.title) is active."
            await loadBusinessAccount()
            if let result {
                finishSubscriptionFlowIfActive(result)
            }
        } catch {
            message = "Apple purchase was found, but membership activation needs a retry: \(error.pccUserFacingMessage)"
        }
    }

    private func canBuy(_ plan: BusinessSubscriptionPlan) -> Bool {
        accountState.profile != nil
        && accountState.canCompleteSubscription
        && accountState.profile?.selectedPlan == plan
        && (purchaseService.businessProductSummary(for: plan) != nil || purchaseService.purchasedProductIDs.contains(plan.productID))
        && userSessionStore.isEmailVerified
        && !isPurchasing
    }


    private func subscriptionActivationMessage(
        for result: AppleBusinessSubscriptionBackendResult,
        plan: BusinessSubscriptionPlan
    ) -> String {
        switch result.status {
        case .activated, .alreadyProcessed:
            return result.message ?? "\(plan.title) is active."
        case .rejected:
            let raw = (result.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.localizedCaseInsensitiveContains("already linked") {
                return "This Apple subscription is already linked to another organisation on Coast Calendar. Publishing unlocks for the organisation that holds the plan. If you are testing, use a different Sandbox Apple ID, or ask Support to review the link."
            }
            if raw.localizedCaseInsensitiveContains("approved for this subscription plan") {
                return "Your organisation is approved, but its selected plan does not match this Apple product. Choose the matching plan before paying."
            }
            if raw.isEmpty {
                return "\(membershipApprovedPaymentPrefix(for: plan)) Subscription could not be activated."
            }
            return "\(membershipApprovedPaymentPrefix(for: plan)) \(raw)"
        }
    }

    private func membershipApprovedPaymentPrefix(for plan: BusinessSubscriptionPlan) -> String {
        guard accountState.profile?.memberStatus == .approved else {
            return "\(plan.title) payment could not be completed."
        }
        return "Your membership is approved, but \(plan.title) is not active yet."
    }

    @MainActor
    private func finishSubscriptionFlowIfActive(_ result: AppleBusinessSubscriptionBackendResult) {
        guard result.grantsCurrentAccess,
              accountState.activeSubscription != nil else { return }

        showSubscriptionPaymentSheet = false
        dismiss()
    }

    private func handlePlanTap(_ plan: BusinessSubscriptionPlan) {
        draft.selectedPlan = plan

        guard userSessionStore.isSignedIn else {
            message = "\(plan.title) selected. Fill in the member details below, then submit to create the account and apply."
            return
        }

        guard userSessionStore.isEmailVerified else {
            message = "\(plan.title) selected. Verify your email before submitting the membership application."
            return
        }

        guard accountState.profile != nil else {
            message = "\(plan.title) selected. Fill in the member details below, then submit for Support approval."
            return
        }

        guard accountState.profile?.selectedPlan == plan else {
            message = "\(plan.title) selected. Save your member page to update the requested plan."
            return
        }

        guard accountState.canCompleteSubscription else {
            message = "\(plan.title) selected. Payment unlocks after Support approves the membership."
            return
        }

        Task { await purchaseSubscription(plan) }
    }

    @MainActor
    private func payForSelectedPlan(_ plan: BusinessSubscriptionPlan) async {
        draft.selectedPlan = plan

        guard accountState.canCompleteSubscription, accountState.profile != nil else {
            handlePlanTap(plan)
            return
        }

        if let activePlan = accountState.activeSubscription?.plan,
           activePlan != plan {
            pendingPlanPayment = plan
            showPlanChangeConfirmation = true
            return
        }

        await performPlanPayment(plan)
    }

    @MainActor
    private func performPlanPayment(_ plan: BusinessSubscriptionPlan) async {
        pendingPlanPayment = nil
        draft.selectedPlan = plan
        // Do not block Apple Pay on a profile save. Charge first; server verify updates the plan.
        await purchaseSubscription(plan)
    }

    @MainActor
    private func promptSaveSelectedPlan(_ plan: BusinessSubscriptionPlan) {
        guard accountState.profile != nil else {
            draft.selectedPlan = plan
            message = "\(plan.title) selected. Fill in the member details below, then submit for Support approval."
            return
        }

        pendingPlanSelection = plan
        showPlanSelectionConfirmation = true
    }

    @MainActor
    private func saveSelectedPlan(_ plan: BusinessSubscriptionPlan) async {
        pendingPlanSelection = nil
        draft.selectedPlan = plan
        message = "Saving \(plan.title) as your membership plan."
        await saveProfile()

        if accountState.profile?.selectedPlan == plan {
            message = "\(plan.title) saved. Tap Pay to confirm with Apple."
        } else {
            message = "Apple has taken the payment, but publishing is not unlocked yet. Open Membership and try again, or contact Support."
        }
    }

    @ViewBuilder
    private func planActionButtons(for plan: BusinessSubscriptionPlan) -> some View {
        if accountState.canCompleteSubscription, accountState.profile != nil {
            if accountState.activeSubscription?.plan == plan {
                Label("Current plan", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            } else {
                Button {
                    Task { await payForSelectedPlan(plan) }
                } label: {
                    Label(paymentButtonTitle(for: plan), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(PCCTheme.leafGreen)
                .disabled(isPurchasing || isSaving || !canPayForSelectedPlan(plan))
            }
        } else {
            Button {
                handlePlanTap(plan)
            } label: {
                Label(subscriptionButtonTitle(for: plan), systemImage: subscriptionButtonIcon(for: plan))
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(draft.selectedPlan == plan ? PCCTheme.leafGreen : PCCTheme.pohutukawaOrange)
            .disabled(isPurchasing || (accountState.canCompleteSubscription && !canBuy(plan) && accountState.profile?.selectedPlan == plan))
        }
    }

    private func canPayForSelectedPlan(_ plan: BusinessSubscriptionPlan) -> Bool {
        userSessionStore.isEmailVerified
        && accountState.canCompleteSubscription
        && (purchaseService.businessProductSummary(for: plan) != nil || purchaseService.purchasedProductIDs.contains(plan.productID))
    }

    private func paymentButtonTitle(for plan: BusinessSubscriptionPlan) -> String {
        if purchaseService.purchasedProductIDs.contains(plan.productID) {
            return accountState.activeSubscription?.productID == plan.productID ? "Active" : "Activate subscription"
        }
        let price = purchaseService.businessProductSummary(for: plan)?.displayPrice ?? plan.priceText
        return "Pay \(price)"
    }

    private func subscriptionButtonTitle(for plan: BusinessSubscriptionPlan) -> String {
        if purchaseService.purchasedProductIDs.contains(plan.productID) {
            return accountState.activeSubscription?.productID == plan.productID ? "Active" : "Activate subscription"
        }
        if !userSessionStore.isSignedIn {
            return draft.selectedPlan == plan ? "Selected - create account" : "Choose this plan"
        }
        if !userSessionStore.isEmailVerified {
            return draft.selectedPlan == plan ? "Selected - verify email" : "Choose this plan"
        }
        if accountState.profile == nil {
            return draft.selectedPlan == plan ? "Selected - fill details" : "Choose this plan"
        }
        if accountState.profile?.selectedPlan != plan {
            return draft.selectedPlan == plan ? "Save to change plan" : "Choose this plan"
        }
        if !accountState.canCompleteSubscription {
            return "Selected - waiting for approval"
        }
        guard let product = purchaseService.businessProductSummary(for: plan) else {
            return "App Store product unavailable"
        }
        return "Subscribe \(product.displayPrice)"
    }

    private func subscriptionButtonIcon(for plan: BusinessSubscriptionPlan) -> String {
        if accountState.canCompleteSubscription, accountState.profile?.selectedPlan == plan {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return draft.selectedPlan == plan ? "checkmark.circle.fill" : "circle"
    }

    private var subscriptionSummaryText: String {
        if let active = accountState.activeSubscription, let plan = active.plan {
            if active.status == "cancelled", let end = active.currentPeriodEnd {
                return "Cancelled. Access remains active until \(end.formatted(date: .abbreviated, time: .omitted))."
            }
            if let end = active.currentPeriodEnd {
                return "\(plan.title) active until \(end.formatted(date: .abbreviated, time: .omitted))."
            }
            return "\(plan.title) \(active.status)."
        }

        if let attention = accountState.subscriptionNeedingBackendAttention, attention.plan != nil {
            return "Apple has taken the payment, but publishing is not unlocked yet. Open Membership and try again, or contact Support."
        }

        if accountState.profile?.memberStatus == .approved {
            return "Approved with no active subscription."
        }

        return "Choose a plan for Support to review with your application."
    }

    private var memberDashboardTitle: String {
        if accountState.profile?.memberStatus == .approved {
            return "Organisation dashboard"
        }
        return "Complete your membership"
    }

    private var memberDashboardSubtitle: String {
        if accountState.canReleaseToBoard {
            return "Your Organisation can list on the public board."
        }
        if accountState.canSubmitAsOrganisation {
            return "Your Organisation can create listings and polls."
        }
        return "Finish these steps to unlock Organisation listing tools."
    }

    private var memberDashboardMessage: String {
        guard let profile = accountState.profile else {
            return "Register your Organisation to list on Coast Calendar."
        }

        switch profile.memberStatus {
        case .pendingReview:
            return "Application submitted. Pending review by Pōhutukawa Coast Calendar Support."
        case .approved:
            if accountState.subscriptionNeedingBackendAttention != nil {
                return "Apple has taken the payment, but publishing is not unlocked yet. Open Membership and try again, or contact Support."
            }
            if accountState.activeSubscription == nil {
                return homepageIsReady
                ? "Public page is ready. Choose a plan below to unlock Create."
                : "Membership is approved. Add a public name and location, then choose a plan to unlock Create."
            }
            return homepageIsReady ? "Your member tools are ready." : "Set up your home page so locals can see who you are."
        case .rejected:
            return profile.rejectionReason ?? profile.supportNote ?? "Support needs changes before this membership can be approved."
        case .suspended:
            return profile.suspensionReason ?? profile.supportNote ?? "Support has paused this membership."
        case .archived:
            return "This membership record is archived."
        }
    }


    private func seedPublicDraftFromApplicationIfNeeded() {
        if publicDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.displayName = draft.name
        }
        if publicDraft.areaScopeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.areaScopeID = draft.areaScopeID
        }
        if publicDraft.publicContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.publicContactName = draft.contactName
        }
        if publicDraft.publicContactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.publicContactEmail = draft.email
        }
        if publicDraft.publicPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.publicPhone = draft.phone
        }
        if publicDraft.publicAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.publicAddress = draft.address
        }
        if publicDraft.publicWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.publicWebsite = draft.website
        }
        if publicDraft.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicDraft.bio = draft.about
        }
    }

    @MainActor
    private func finishHomePageSetup() async {
        guard let session = userSessionStore.session,
              let profile = accountState.profile else {
            message = "Sign in again before saving your member page."
            return
        }
        let profileID = profile.id
        let userID = profile.ownerUserID
        let requestContext = userSessionStore.captureAccountContext()

        showValidation = true
        guard validateHomepageDetails() else { return }

        isSaving = true
        defer { isSaving = false }
        let previousHeroPath = serverConfirmedPublicDraft.heroImagePath
        let previousAvatarPath = serverConfirmedPublicDraft.avatarImagePath
        var uploadedImagePaths: [String] = []
        var savedProfileBeforeConfirmation: PublicBusinessProfileRecord?
        do {
            var draftToSave = publicDraft
            if let pendingHeroImageData {
                let path = try await service.uploadMemberProfileImage(
                    data: pendingHeroImageData,
                    mimeType: "image/jpeg",
                    kind: "hero",
                    userID: userID,
                    accessToken: session.accessToken
                )
                uploadedImagePaths.append(path)
                draftToSave.heroImagePath = path
            }
            if let pendingAvatarImageData {
                let path = try await service.uploadMemberProfileImage(
                    data: pendingAvatarImageData,
                    mimeType: "image/jpeg",
                    kind: "avatar",
                    userID: userID,
                    accessToken: session.accessToken
                )
                uploadedImagePaths.append(path)
                draftToSave.avatarImagePath = path
            }

            let saved = try await service.saveOwnPublicProfileDraft(
                profileID: profileID,
                draft: draftToSave,
                accessToken: session.accessToken
            )
            savedProfileBeforeConfirmation = saved
            guard userSessionStore.isCurrent(requestContext) else { return }
            let confirmed = try await service.confirmOwnPublicContact(
                profileID: profileID,
                revision: saved.publicContactRevision,
                accessToken: session.accessToken
            )
            guard userSessionStore.isCurrent(requestContext) else { return }
            applySavedPublicProfile(confirmed)
            await retireReplacedMemberImages(
                previousHeroPath: previousHeroPath,
                previousAvatarPath: previousAvatarPath,
                savedDraft: PublicMemberProfileDraft(profile: confirmed),
                accessToken: session.accessToken
            )
            message = confirmed.publishedAt == nil
                ? "Your public home page details are saved and confirmed. Publication remains server-controlled."
                : "Your public home page details are saved."
            showHomePageEditor = false
        } catch {
            guard userSessionStore.isCurrent(requestContext) else { return }
            if let savedProfileBeforeConfirmation {
                applySavedPublicProfile(savedProfileBeforeConfirmation)
                message = "Your home page was saved, but contact confirmation needs another try before publication can be requested."
            } else {
                await cleanupUploadedMemberImages(uploadedImagePaths, accessToken: session.accessToken)
                message = "Your public home page could not be saved. Your edits are still here so you can try again."
            }
        }
    }

    @MainActor
    private func applySavedPublicProfile(_ profile: PublicBusinessProfileRecord) {
        publicProfile = profile
        let savedDraft = PublicMemberProfileDraft(profile: profile)
        publicDraft = savedDraft
        serverConfirmedPublicDraft = savedDraft
        clearPendingMemberImages()
    }

    @MainActor
    private func discardHomePageDraftChanges() {
        publicDraft = serverConfirmedPublicDraft
        clearPendingMemberImages()
        message = nil
    }

    @MainActor
    private func removeMemberImage(_ kind: MemberProfileImageKind) {
        switch kind {
        case .hero:
            publicDraft.heroImagePath = nil
            heroPreviewImage = nil
            pendingHeroImageData = nil
            heroPickerItem = nil
        case .avatar:
            publicDraft.avatarImagePath = nil
            avatarPreviewImage = nil
            pendingAvatarImageData = nil
            avatarPickerItem = nil
        }
    }

    @MainActor
    private func clearPendingMemberImages() {
        heroPickerItem = nil
        avatarPickerItem = nil
        heroPreviewImage = nil
        avatarPreviewImage = nil
        pendingHeroImageData = nil
        pendingAvatarImageData = nil
    }

    @MainActor
    private func cleanupUploadedMemberImages(_ paths: [String], accessToken: String) async {
        for path in paths {
            do {
                try await service.deleteMemberProfileImage(path: path, accessToken: accessToken)
            } catch {
#if DEBUG
                print("[Membership] uploaded member image cleanup failed for path=\(path): \(error)")
#endif
            }
        }
    }

    @MainActor
    private func retireReplacedMemberImages(
        previousHeroPath: String?,
        previousAvatarPath: String?,
        savedDraft: PublicMemberProfileDraft,
        accessToken: String
    ) async {
        let retiredPaths = Set([previousHeroPath, previousAvatarPath].compactMap { path -> String? in
            guard let path,
                  path != savedDraft.heroImagePath,
                  path != savedDraft.avatarImagePath else {
                return nil
            }
            return path
        })

        for path in retiredPaths {
            do {
                try await service.deleteMemberProfileImage(path: path, accessToken: accessToken)
            } catch {
#if DEBUG
                print("[Membership] retired member image cleanup failed for path=\(path): \(error)")
#endif
            }
        }
    }

    private var homePageHasUnsavedChanges: Bool {
        publicDraft != serverConfirmedPublicDraft
        || pendingHeroImageData != nil
        || pendingAvatarImageData != nil
    }

    private func memberImageRequest(path: String?) -> URLRequest? {
        service.memberProfileImageRequest(path: path, accessToken: userSessionStore.session?.accessToken)
    }

    @MainActor
    private func validateHomepageDetails() -> Bool {
        invalidMembershipFields = []

        let displayName = publicDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactEmail = publicDraft.publicContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let areaScopeID = publicDraft.areaScopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty { invalidMembershipFields.insert("memberName") }
        if !contactEmail.isEmpty,
           !MembershipContactEmailValidator.isUsable(contactEmail) {
            invalidMembershipFields.insert("contactEmail")
        }
        if areaScopeID.isEmpty { invalidMembershipFields.insert("areaScope") }
        if invalidMembershipFields.isEmpty { return true }
        message = "Add a public name and location, then check any optional contact details before tapping Done."
        return false
    }

    @MainActor
    private func loadMemberImage(from item: PhotosPickerItem?, kind: MemberProfileImageKind) async {
        guard let item else { return }
        switch kind {
        case .hero: isLoadingHeroImage = true
        case .avatar: isLoadingAvatarImage = true
        }
        defer {
            switch kind {
            case .hero:
                heroPickerItem = nil
                isLoadingHeroImage = false
            case .avatar:
                avatarPickerItem = nil
                isLoadingAvatarImage = false
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let photo = compressedMemberPhoto(from: data),
                  let image = UIImage(data: photo.data) else {
                message = "That image could not be prepared. Please choose another photo."
                return
            }

            switch kind {
            case .hero:
                pendingHeroImageData = photo.data
                heroPreviewImage = image
            case .avatar:
                pendingAvatarImageData = photo.data
                avatarPreviewImage = image
            }
        } catch {
            message = "That image could not be loaded. Please choose another photo."
        }
    }

    private func compressedMemberPhoto(from data: Data) -> ListingPhotoUpload? {
        guard let image = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 1800
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let compressed = resized.jpegData(compressionQuality: 0.82) else { return nil }
        return ListingPhotoUpload(id: UUID(), data: compressed, width: Int(targetSize.width.rounded()), height: Int(targetSize.height.rounded()), mimeType: "image/jpeg")
    }

    private var memberDashboardStage: String {
        guard let profile = accountState.profile else { return "Apply" }
            if let active = accountState.activeSubscription, active.plan != nil {
            return "Live"
        }
        if accountState.subscriptionNeedingBackendAttention != nil {
            return "Check payment"
        }
        switch profile.memberStatus {
        case .pendingReview:
            return "Pending"
        case .approved:
            return "Approved"
        case .rejected:
            return "Needs changes"
        case .suspended:
            return "Suspended"
        case .archived:
            return "Archived"
        }
    }

    private var memberDashboardTint: Color {
        guard let profile = accountState.profile else { return PCCTheme.pohutukawaOrange }
        if accountState.activeSubscription?.plan != nil { return PCCTheme.leafGreen }
        if accountState.subscriptionNeedingBackendAttention != nil { return PCCTheme.pohutukawaOrange }
        switch profile.memberStatus {
        case .approved:
            return PCCTheme.leafGreen
        case .pendingReview:
            return PCCTheme.pohutukawaOrange
        case .rejected, .suspended, .archived:
            return PCCTheme.ink.opacity(0.68)
        }
    }

    @MainActor
    private func resendVerificationEmail() async {
        do {
            try await userSessionStore.resendVerificationEmail()
            message = "Open the link in your email, then tap Check again."
        } catch {
            message = error.pccUserFacingMessage
        }
    }

    @MainActor
    private func refreshVerificationStatus() async {
        do {
            try await userSessionStore.refreshNow()
            message = userSessionStore.isEmailVerified
                ? "Email verified. Member page tools are available."
                : "Still waiting for email confirmation."
        } catch {
            message = "Could not refresh account status. Please sign in again."
        }
    }
}

enum MemberProfileImageKind {
    case hero
    case avatar
}

struct MemberHomePageEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: PublicMemberProfileDraft
    @Binding var heroPickerItem: PhotosPickerItem?
    @Binding var avatarPickerItem: PhotosPickerItem?
    let heroPreviewImage: UIImage?
    let avatarPreviewImage: UIImage?
    let isLoadingHeroImage: Bool
    let isLoadingAvatarImage: Bool
    let showValidation: Bool
    let invalidMembershipFields: Set<String>
    let isSaving: Bool
    let primaryButtonTitle: String
    let heroImageRequest: URLRequest?
    let avatarImageRequest: URLRequest?
    let hasUnsavedChanges: Bool
    let onDone: () -> Void
    let onDiscard: () -> Void
    let onRemoveHeroImage: () -> Void
    let onRemoveAvatarImage: () -> Void
    @State private var showDiscardConfirmation = false

    private let locationCatalog = LocationCatalog.local

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewHeader

                    Button(action: onDone) {
                        Label(isSaving ? "Saving" : "Save changes", systemImage: isSaving ? "hourglass" : "checkmark.seal.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PCCTheme.leafGreen)
                    .disabled(isSaving || isLoadingHeroImage || isLoadingAvatarImage)
                }
                .padding(.horizontal, 16)
                .padding(.top, 74)
                .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
            }
            .pccScrollableKeyboardDismiss()
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .navigationTitle(primaryButtonTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    if hasUnsavedChanges {
                        showDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
            }
        }
        .confirmationDialog(
            "Discard unsaved home page changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) {
                onDiscard()
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        }
        .pccDismissesKeyboardOnTap()
        .pccKeyboardDoneToolbar {
            UIApplication.pccDismissKeyboard()
        }
    }

    private var previewHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                MemberImageEditorPanel(
                    title: "Banner image",
                    emptyTitle: "Add banner image",
                    imageRequest: heroImageRequest,
                    previewImage: heroPreviewImage,
                    pickerItem: $heroPickerItem,
                    isLoading: isLoadingHeroImage,
                    positionX: $draft.heroImagePositionX,
                    positionY: $draft.heroImagePositionY,
                    aspectRatio: 1.55,
                    isCircular: false,
                    showValidation: showValidation && invalidMembershipFields.contains("heroImage"),
                    onRemove: onRemoveHeroImage
                )
                .frame(maxWidth: .infinity)
                .frame(height: 248)

                HStack(alignment: .bottom) {
                    MemberImageEditorPanel(
                        title: "Profile image",
                        emptyTitle: "Add profile image",
                        imageRequest: avatarImageRequest,
                        previewImage: avatarPreviewImage,
                        pickerItem: $avatarPickerItem,
                        isLoading: isLoadingAvatarImage,
                        positionX: $draft.avatarImagePositionX,
                        positionY: $draft.avatarImagePositionY,
                        aspectRatio: 1,
                        isCircular: true,
                        showValidation: showValidation && invalidMembershipFields.contains("avatarImage"),
                        onRemove: onRemoveAvatarImage
                    )
                    .frame(width: 152, height: 152)
                    .offset(y: 76)

                    Spacer()
                }
                .padding(.leading, 24)
            }
            .zIndex(1)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Color.clear
                        .frame(width: 166, height: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Member or organisation name" : draft.displayName)
                            .font(.title2.weight(.black))
                            .foregroundStyle(PCCTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(selectedLocationName)
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.pohutukawaOrange)
                    }
                    .padding(.bottom, 8)

                    Spacer(minLength: 0)
                }
                .padding(.top, 18)

            Text(draft.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your bio will appear here." : draft.bio)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

                Label("These are the public homepage details locals will see. They can be different from the private application details Coast Calendar uses for assessment and support.", systemImage: "eye.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .lineSpacing(2)
                    .padding(12)
                    .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                editableDetailsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 70)
            .padding(.bottom, 18)
            .background(.white.opacity(0.84))
        }
        .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(PCCTheme.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var editableDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BusinessTextField(
                title: "Member or organisation name",
                text: $draft.displayName,
                required: true,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("memberName") ? "Add the name locals should see." : nil
            )

            BusinessTextField(
                title: "Public contact name",
                text: $draft.publicContactName,
                required: false,
                showValidation: showValidation
            )

            BusinessTextField(
                title: "Phone",
                text: $draft.publicPhone,
                required: false,
                keyboardType: .phonePad,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("phone") ? "Add a phone number for this page." : nil
            )

            BusinessTextField(
                title: "Email",
                text: $draft.publicContactEmail,
                required: false,
                keyboardType: .emailAddress,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("contactEmail") ? "Add a public contact email." : nil
            )

            BusinessTextField(
                title: "Address",
                text: $draft.publicAddress,
                required: false,
                showValidation: showValidation,
                validationMessage: invalidMembershipFields.contains("address") ? "Add the member address or service address." : nil
            )

            BusinessTextField(
                title: "Location description",
                text: $draft.publicLocationText,
                required: false,
                showValidation: showValidation
            )

            BusinessTextField(
                title: "Website",
                text: $draft.publicWebsite,
                required: false,
                keyboardType: .URL,
                showValidation: showValidation
            )

            Picker("Location", selection: $draft.areaScopeID) {
                ForEach(memberHomeLocationScopes) { scope in
                    Text(scope.displayTitle).tag(scope.id)
                }
            }
            .pickerStyle(.menu)
            .tint(PCCTheme.leafGreen)
            .padding(12)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            if showValidation && invalidMembershipFields.contains("areaScope") {
                Label("Choose the area shown on this page.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }

            BusinessMultilineField(
                title: "Bio",
                text: $draft.bio,
                prompt: "Describe your organisation, club, school, marae, community group, service or business."
            )
            if showValidation && invalidMembershipFields.contains("about") {
                Label("Add a bio for the public page.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }
        }
        .padding(.top, 6)
    }

    private var selectedLocationName: String {
        locationCatalog.scope(id: draft.areaScopeID)?.displayTitle ?? "New Zealand"
    }

    private var memberHomeLocationScopes: [LocationScope] {
        let scopes = locationCatalog.listingInputScopes
        guard !scopes.contains(where: { $0.id == draft.areaScopeID }),
              let current = locationCatalog.scope(id: draft.areaScopeID) else {
            return scopes
        }
        return [current] + scopes
    }
}

struct MemberImageEditorPanel: View {
    let title: String
    let emptyTitle: String
    let imageRequest: URLRequest?
    let previewImage: UIImage?
    @Binding var pickerItem: PhotosPickerItem?
    let isLoading: Bool
    @Binding var positionX: Double
    @Binding var positionY: Double
    let aspectRatio: CGFloat
    let isCircular: Bool
    let showValidation: Bool
    let onRemove: () -> Void
    @GestureState private var dragOffset: CGSize = .zero
    @State private var remoteImage: UIImage?
    @State private var isLoadingRemoteImage = false

    var body: some View {
        ZStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                framedImage
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text(hasImage ? "Choose a replacement image." : "Choose an image."))

            if hasImage && !isLoading {
                Label(dragPrompt, systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font((isCircular ? Font.caption2 : Font.caption).weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(isCircular ? 1 : 2)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, isCircular ? 9 : 13)
                    .padding(.vertical, isCircular ? 6 : 8)
                    .background(.black.opacity(0.50), in: Capsule())
            }

            VStack {
                Spacer()

                HStack(spacing: 10) {
                    Spacer()

                    if hasImage {
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Image(systemName: "trash")
                                .font(.headline.weight(.black))
                                .frame(width: controlSize, height: controlSize)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PCCTheme.pohutukawaRed)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .accessibilityLabel(Text("Remove \(title.lowercased())"))

                        Button {
                            positionX = 50
                            positionY = 50
                        } label: {
                            Image(systemName: "scope")
                                .font(.headline.weight(.black))
                                .frame(width: controlSize, height: controlSize)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .accessibilityLabel(Text("Centre \(title.lowercased())"))
                    }
                }
                .padding(isCircular ? 6 : 12)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: imageRequest?.url) {
            await loadRemoteImage()
        }
    }

    @ViewBuilder
    private var framedImage: some View {
        let content = ZStack {
            imageContent

            if isLoading || isLoadingRemoteImage {
                ProgressView()
                    .tint(PCCTheme.leafGreen)
            } else if previewImage == nil && imageRequest == nil {
                emptyImagePrompt
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .contentShape(Rectangle())

        if isCircular {
            content
                .background(PCCTheme.cream.opacity(0.72), in: Circle())
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(showValidation ? PCCTheme.pohutukawaRed.opacity(0.78) : PCCTheme.leafGreen.opacity(0.24), style: StrokeStyle(lineWidth: 2, dash: showValidation ? [] : [8, 7]))
                }
        } else {
            content
                .background(PCCTheme.cream.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        .stroke(showValidation ? PCCTheme.pohutukawaRed.opacity(0.78) : PCCTheme.leafGreen.opacity(0.24), style: StrokeStyle(lineWidth: 2, dash: showValidation ? [] : [8, 7]))
                }
        }
    }

    private var emptyImagePrompt: some View {
        VStack(spacing: isCircular ? 5 : 10) {
            Image(systemName: "photo.badge.plus")
                .font((isCircular ? Font.title2 : Font.largeTitle).weight(.black))

            Text(isCircular ? "Upload profile image" : "Upload banner image here")
                .font((isCircular ? Font.caption2 : Font.headline).weight(.black))
                .multilineTextAlignment(.center)
                .lineLimit(isCircular ? 2 : 1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, isCircular ? 18 : 24)
        }
        .foregroundStyle(PCCTheme.leafGreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PCCTheme.leafGreen.opacity(isCircular ? 0.06 : 0.08))
    }

    @ViewBuilder
    private var imageContent: some View {
        if let previewImage {
            pannableImage(Image(uiImage: previewImage))
        } else if let remoteImage {
            pannableImage(Image(uiImage: remoteImage))
        } else if imageRequest != nil {
            Image(systemName: "photo")
                .font(.title.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.35))
        }
    }

    private var hasImage: Bool {
        previewImage != nil || imageRequest != nil
    }

    private var dragPrompt: String {
        isCircular ? "Drag to move" : "Drag to move cover photo"
    }

    private var controlSize: CGFloat {
        isCircular ? 44 : 50
    }

    private func cropDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                guard hasImage else { return }
                applyCropDrag(value.translation, in: size)
            }
    }

    private func pannableImage(_ image: Image) -> some View {
        GeometryReader { proxy in
            let offset = displayedCropOffset(in: proxy.size)
            image
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(isCircular ? 1.18 : 1.24)
                .offset(x: offset.width, y: offset.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(cropDragGesture(in: proxy.size))
        }
    }

    private func cropOffset(in size: CGSize) -> CGSize {
        MemberProfileImageCrop.offset(in: size, isCircular: isCircular, positionX: positionX, positionY: positionY)
    }

    private func displayedCropOffset(in size: CGSize) -> CGSize {
        clampedOffset(
            CGSize(
                width: cropOffset(in: size).width + dragOffset.width,
                height: cropOffset(in: size).height + dragOffset.height
            ),
            in: size
        )
    }

    private func applyCropDrag(_ translation: CGSize, in size: CGSize) {
        let nextOffset = clampedOffset(
            CGSize(
                width: cropOffset(in: size).width + translation.width,
                height: cropOffset(in: size).height + translation.height
            ),
            in: size
        )
        let bounds = cropBounds(in: size)
        positionX = 50 - Double(nextOffset.width / bounds.width) * 50
        positionY = 50 - Double(nextOffset.height / bounds.height) * 50
    }

    private func clampedOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let bounds = cropBounds(in: size)
        return CGSize(
            width: min(bounds.width, max(-bounds.width, offset.width)),
            height: min(bounds.height, max(-bounds.height, offset.height))
        )
    }

    private func cropBounds(in size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width * (isCircular ? 0.09 : 0.12)),
            height: max(1, size.height * (isCircular ? 0.09 : 0.12))
        )
    }

    @MainActor
    private func loadRemoteImage() async {
        guard previewImage == nil, let imageRequest else {
            remoteImage = nil
            return
        }
        isLoadingRemoteImage = true
        defer { isLoadingRemoteImage = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: imageRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                remoteImage = nil
                return
            }
            remoteImage = image
        } catch {
            remoteImage = nil
        }
    }
}

struct MemberDashboardActionRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.black))
                    .foregroundStyle(tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.38))
            }
            .padding(12)
            .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SubscriptionPaymentSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let summaryText: String
    let selectedPlan: BusinessSubscriptionPlan
    let activeSubscription: BusinessSubscriptionRecord?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: activeSubscription == nil ? "creditcard.fill" : "checkmark.seal.fill")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(activeSubscription == nil ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)

                        Text(activeSubscription == nil ? "Subscription payment" : "Subscription active")
                            .font(.system(size: 32, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text(summaryText)
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.66))
                            .lineSpacing(3)

                        if let active = activeSubscription {
                            Text("Current plan: \(active.plan?.title ?? active.planID)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.leafGreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                        } else {
                            Text("No active plan yet")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.pohutukawaOrange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Capsule())
                        }
                    }
                    .padding(20)
                    .pccCardStyle()

                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
            }
        }
    }
}

struct SubscriptionFactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))
            Spacer()
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink)
        }
        .padding(11)
        .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct BusinessPlanDisplayCard<Action: View>: View {
    let title: String
    let priceText: String
    let subtitle: String
    let inclusions: [String]
    let footer: String
    @ViewBuilder let action: () -> Action

    init(
        title: String,
        priceText: String,
        subtitle: String,
        inclusions: [String],
        footer: String,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title
        self.priceText = priceText
        self.subtitle = subtitle
        self.inclusions = inclusions
        self.footer = footer
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }
                Spacer()
                Text(priceText)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            ForEach(inclusions, id: \.self) { inclusion in
                Label(inclusion, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
            }

            Text(footer)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.56))

            action()
        }
        .padding(18)
        .pccCardStyle()
    }
}

extension BusinessPlanDisplayCard where Action == EmptyView {
    init(
        title: String,
        priceText: String,
        subtitle: String,
        inclusions: [String],
        footer: String
    ) {
        self.title = title
        self.priceText = priceText
        self.subtitle = subtitle
        self.inclusions = inclusions
        self.footer = footer
        self.action = { EmptyView() }
    }
}

struct MembershipStepRow: View {
    let number: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(PCCTheme.leafGreen, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineSpacing(2)
            }
        }
    }
}

struct MemberDashboardTile: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                Text(value)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(12)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct NoticeTemplateRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 24, height: 24)
                .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct BusinessTextField: View {
    let title: String
    @Binding var text: String
    let required: Bool
    var keyboardType: UIKeyboardType = .default
    let showValidation: Bool
    var validationMessage: String? = nil

    private var isMissing: Bool {
        required && showValidation && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isInvalid: Bool {
        isMissing || validationMessage != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(isInvalid ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.62))
                if required {
                    Text("Required")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(isInvalid ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.38))
                }
            }

            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(keyboardType == .emailAddress || keyboardType == .URL ? .never : .words)
                .autocorrectionDisabled(keyboardType == .emailAddress || keyboardType == .URL)
                .font(.body.weight(.semibold))
                .padding(12)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        .stroke(isInvalid ? PCCTheme.pohutukawaOrange : .white.opacity(0.8), lineWidth: isInvalid ? 2 : 1)
                )

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
        }
    }
}

struct BusinessOrganisationTypePicker: View {
    @Binding var selection: BusinessOrganisationType?
    let showValidation: Bool
    var validationMessage: String? = nil

    private var isInvalid: Bool {
        showValidation && selection == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Organisation type")
                    .font(.caption.weight(.black))
                    .foregroundStyle(isInvalid ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.62))
                Text("Required")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isInvalid ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.38))
            }

            Picker("Organisation type", selection: $selection) {
                Text("Choose organisation type").tag(nil as BusinessOrganisationType?)
                ForEach(BusinessOrganisationType.allCases) { type in
                    Text(type.title).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .tint(PCCTheme.leafGreen)
            .font(.body.weight(.semibold))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(isInvalid ? PCCTheme.pohutukawaOrange : .white.opacity(0.8), lineWidth: isInvalid ? 2 : 1)
            )

            if isInvalid, let validationMessage {
                Text(validationMessage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
        }
    }
}

struct BusinessWebsiteField: View {
    @Binding var urlText: String
    let showValidation: Bool
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Website")
                .font(.caption.weight(.black))
                .foregroundStyle(showValidation ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.62))

            TextField("https://www.example.co.nz", text: $urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.weight(.semibold))
                .foregroundStyle(PCCTheme.ink)
                .tint(PCCTheme.leafGreen)
                .padding(12)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(showValidation ? PCCTheme.pohutukawaOrange : .white.opacity(0.8), lineWidth: showValidation ? 2 : 1)
            )

            Text("Start after https://www. Leave only the prefix if you do not have a website.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.52))

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
        }
    }
}

struct BusinessMultilineField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))

            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(.body.weight(.semibold))
                .padding(12)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                )
        }
    }
}

struct StoreKitStatusCard: View {
    let state: StoreKitPaymentState
    let onReload: () -> Void

    private var title: String {
        switch state {
        case .idle:
            return "Checking subscription options"
        case .loadingProducts:
            return "Loading products"
        case .ready(let productCount):
            return "\(productCount) subscription option\(productCount == 1 ? "" : "s") ready"
        case .productsUnavailable:
            return "Purchases unavailable"
        case .purchasing:
            return "Purchase in progress"
        case .purchased:
            return "Purchase confirmed by Apple"
        case .activating:
            return "Activating purchase"
        case .activated:
            return "Purchase activated"
        case .awaitingBackendRetry:
            return "Purchase waiting to retry"
        case .pending:
            return "Purchase pending"
        case .cancelled:
            return "Purchase cancelled"
        case .failed:
            return "Purchase check failed"
        }
    }

    private var message: String {
        switch state {
        case .idle, .loadingProducts:
            return "The app is refreshing the available subscription options."
        case .ready:
            return "Subscription options are available. Choose the member plan you want to continue with."
        case .productsUnavailable:
            return "Apple has not returned the subscription options yet. Refresh shortly, or try again after relaunching the app."
        case .purchasing:
            return "Keep this screen open while Apple completes the purchase."
        case .purchased(let productID):
            return "Apple verified the transaction. Recording activation for \(productID)."
        case .activating:
            return "Recording the subscription against your member account."
        case .activated(let productID):
            return "\(productID) was activated successfully."
        case .awaitingBackendRetry(let productID):
            return "\(productID) is waiting for activation. The app will retry automatically."
        case .pending:
            return "Apple marked the purchase as pending. The app should wait for a transaction update."
        case .cancelled:
            return "The purchase was cancelled before payment completed."
        case .failed(let detail):
            return detail
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .lineSpacing(2)
                }
            }

            Button(action: onReload) {
                Label("Refresh Options", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PCCTheme.leafGreen)
            .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct PaymentTierReadinessRow: View {
    let priceText: String
    let title: String
    let description: String
    let productID: String?
    let isPaid: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(priceText)
                .font(.headline.weight(.black))
                .foregroundStyle(isPaid ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(description)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineSpacing(2)

                if let productID {
                    Text(productID)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.42))
                }
            }
        }
        .padding(13)
        .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ListingAnalyticsSettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var listings: [LocalEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAccountAccess = false
    private let service: UserListingFetching = SupabaseEventService()

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Listing Insights")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Track reach, opens and engagement across listings you can manage. Boost + Insights unlocks the richest reporting view.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if !userSessionStore.isSignedIn {
                            SignInActionCard(
                                icon: "person.crop.circle.badge.plus",
                                title: "Sign in to see your listings",
                                message: "Analytics are attached to listings you submit from your account.",
                                buttonTitle: "Sign in"
                            ) {
                                showAccountAccess = true
                            }
                        } else if isLoading {
                            SettingsInfoMessage(
                                icon: "arrow.clockwise",
                                title: "Loading insights",
                                message: "Fetching listings you can manage."
                            )
                        } else if let errorMessage {
                            SettingsInfoMessage(
                                icon: "wifi.exclamationmark",
                                title: "Insights unavailable",
                                message: errorMessage
                            )
                        } else if listings.isEmpty {
                            SettingsInfoMessage(
                                icon: "rectangle.stack.badge.plus",
                                title: "No listings yet",
                                message: "Submit a listing from the Create tab and its activity will appear here."
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(listings) { listing in
                                    SettingsListingAnalyticsDisclosure(event: listing)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAccountAccess) {
                AccountAccessSheet()
                    .environmentObject(userSessionStore)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task {
                await loadListings()
            }
            .task(id: userSessionStore.session?.userID) {
                await loadListings()
            }
            .refreshable {
                await loadListings()
            }
        }
    }

    @MainActor
    private func loadListings() async {
        guard let session = userSessionStore.session else {
            listings = []
            isLoading = false
            return
        }

        let requestedUserID = session.userID
        isLoading = listings.isEmpty
        errorMessage = nil

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            guard activeSession.userID == requestedUserID,
                  userSessionStore.session?.userID == requestedUserID else {
                listings = []
                return
            }
            let loadedListings = try await service.fetchUserListings(userID: activeSession.userID, accessToken: activeSession.accessToken)
            guard userSessionStore.session?.userID == requestedUserID else {
                listings = []
                return
            }
            listings = loadedListings
            isLoading = false
        } catch {
            guard userSessionStore.session?.userID == requestedUserID else { return }
            isLoading = false
            errorMessage = "Your listing insights could not be loaded. Please try again soon."
        }
    }
}

struct MyListingsSettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    let onNavigateCreate: (() -> Void)?
    @State private var listings: [LocalEvent] = []
    @State private var changeRequests: [EventChangeRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var selectedUserListing: LocalEvent?
    @State private var selectedEditListing: LocalEvent?
    @State private var selectedRemovalListing: LocalEvent?
    @State private var showAccountAccess = false
    private let service: UserListingFetching & EventChangeRequesting = SupabaseEventService()

    init(onNavigateCreate: (() -> Void)? = nil) {
        self.onNavigateCreate = onNavigateCreate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("My Listings")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Listings you can manage stay here with Support feedback attached.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if !userSessionStore.isSignedIn {
                            SignInActionCard(
                                icon: "person.crop.circle.badge.plus",
                                title: "Sign in to manage listings",
                                message: "Sign in here to see submitted, pending, approved and archived listings.",
                                buttonTitle: "Sign in"
                            ) {
                                showAccountAccess = true
                            }
                        } else {
                            MyListingsPanel(
                                listings: listings,
                                changeRequests: changeRequests,
                                isLoading: isLoading,
                                errorMessage: errorMessage,
                                actionMessage: actionMessage,
                                onSelectListing: { listing in
                                    selectedUserListing = listing
                                },
                                onEditListing: { listing in
                                    selectedEditListing = listing
                                },
                                onRemoveListing: { listing in
                                    selectedRemovalListing = listing
                                }
                            ) {
                                Task { await loadListings() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("My Listings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task {
                await loadListings()
            }
            .task(id: userSessionStore.session?.userID) {
                await loadListings()
            }
            .refreshable {
                await loadListings()
            }
            .sheet(isPresented: $showAccountAccess) {
                AccountAccessSheet()
                    .environmentObject(userSessionStore)
            }
            .sheet(item: $selectedUserListing) { listing in
                UserListingDetailSheet(
                    listing: listing,
                    pendingRequest: pendingRequest(for: listing),
                    latestRequest: latestRequest(for: listing),
                    requests: requests(for: listing),
                    onEdit: {
                        selectedUserListing = nil
                        selectedEditListing = listing
                    },
                    onRemove: {
                        selectedUserListing = nil
                        selectedRemovalListing = listing
                    }
                )
            }
            .sheet(item: $selectedEditListing) { listing in
                ListingEditRequestSheet(listing: listing) { draft, note in
                    await submitEditRequest(for: listing, draft: draft, note: note)
                }
            }
            .sheet(item: $selectedRemovalListing) { listing in
                ListingRemovalRequestSheet(listing: listing) { note in
                    await submitRemovalRequest(for: listing, note: note)
                }
            }
        }
    }

    @MainActor
    private func loadListings() async {
        guard let session = userSessionStore.session else {
            listings = []
            changeRequests = []
            selectedUserListing = nil
            selectedEditListing = nil
            selectedRemovalListing = nil
            isLoading = false
            return
        }

        let requestedUserID = session.userID
        isLoading = listings.isEmpty
        errorMessage = nil

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            guard activeSession.userID == requestedUserID,
                  userSessionStore.session?.userID == requestedUserID else {
                listings = []
                changeRequests = []
                return
            }
            async let loadedListings = service.fetchUserListings(userID: activeSession.userID, accessToken: activeSession.accessToken)
            async let loadedChangeRequests = service.fetchMyChangeRequests(userID: activeSession.userID, accessToken: activeSession.accessToken)
            let resolvedListings = try await loadedListings
            let resolvedChangeRequests = try await loadedChangeRequests
            guard userSessionStore.session?.userID == requestedUserID else {
                listings = []
                changeRequests = []
                return
            }
            listings = resolvedListings
            changeRequests = resolvedChangeRequests
            isLoading = false
        } catch {
            guard userSessionStore.session?.userID == requestedUserID else { return }
            isLoading = false
            errorMessage = "Your listings could not be loaded. Please try again soon."
        }
    }

    private func pendingRequest(for listing: LocalEvent) -> EventChangeRequest? {
        changeRequests.first { $0.eventID == listing.id && $0.status == .pending }
    }

    private func latestRequest(for listing: LocalEvent) -> EventChangeRequest? {
        changeRequests
            .filter { $0.eventID == listing.id }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func requests(for listing: LocalEvent) -> [EventChangeRequest] {
        changeRequests
            .filter { $0.eventID == listing.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @MainActor
    private func submitEditRequest(for listing: LocalEvent, draft: ListingEditDraft, note: String?) async {
        guard let session = userSessionStore.session else { return }

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            try await service.createEditRequest(
                event: listing,
                draft: draft,
                requesterID: activeSession.userID,
                requesterNote: note,
                accessToken: activeSession.accessToken
            )
            actionMessage = "Edit request sent for \(listing.title)."
            selectedEditListing = nil
            await loadListings()
        } catch {
            print("[EditRequest] send failed: \(error)")
            actionMessage = "Edit request could not be sent. Please try again."
        }
    }

    @MainActor
    private func submitRemovalRequest(for listing: LocalEvent, note: String?) async {
        guard let session = userSessionStore.session else { return }

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            try await service.archiveOwnListing(
                eventID: listing.id,
                accessToken: activeSession.accessToken
            )
            actionMessage = "\(listing.title) is off the public board."
            selectedRemovalListing = nil
            await loadListings()
        } catch {
            print("[OwnerArchive] failed: \(error)")
            actionMessage = "Could not remove this listing. Please try again."
        }
    }
}

struct SettingsListingAnalyticsDisclosure: View {
    let event: LocalEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.ink)

                        Text(event.listingStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    }

                    Spacer()

                    Text("Insights")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.42))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ListingAnalyticsDetailCard(event: event)
            } else {
                ListingAnalyticsCompactView(event: event)
            }
        }
        .padding(16)
        .pccCardStyle()
    }
}

struct SettingsInfoMessage: View {
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

struct SignInActionCard: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                .lineSpacing(3)

            Button(action: action) {
                Label(buttonTitle, systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pccCardStyle()
    }
}

struct EmailVerificationRequiredCard: View {
    let email: String?
    let title: String
    let message: String
    let resendAction: () async -> Void
    let refreshAction: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "envelope.badge.shield.half.filled")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                .lineSpacing(3)

            if let email, !email.isEmpty {
                Text(email)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            }

            HStack(spacing: 10) {
                Button {
                    Task { await run(resendAction) }
                } label: {
                    Label("Resend email", systemImage: "paperplane.fill")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                Button {
                    Task { await run(refreshAction) }
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.leafGreen)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .disabled(isWorking)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pccCardStyle()
    }

    @MainActor
    private func run(_ action: @escaping () async -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        await action()
        isWorking = false
    }
}

struct SavedRemindersScreen: View {
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @Environment(\.dismiss) private var dismiss
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let service: PublishedEventFetching = SupabaseEventService()

    private var engagedEvents: [LocalEvent] {
        events
            .filter { !engagementStore.engagementKind(for: $0).isEmpty }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("My Activity")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Events you save, mark interested, or mark going appear here on this device. Going can also remind you before the event starts.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if isLoading {
                            SettingsInfoMessage(icon: "arrow.clockwise", title: "Loading events", message: "Checking your saved local events.")
                        } else if let errorMessage {
                            SettingsInfoMessage(icon: "wifi.exclamationmark", title: "Saved events unavailable", message: errorMessage)
                        } else if engagedEvents.isEmpty {
                            SettingsInfoMessage(icon: "bookmark", title: "Nothing saved yet", message: "Tap Save, Interested, or Going on a listing to keep it here.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(engagedEvents) { event in
                                    SavedEventSettingsCard(event: event)
                                }
                            }
                        }

                        Text("\(reminderStore.activeReminderCount) event reminder\(reminderStore.activeReminderCount == 1 ? "" : "s") set on this device.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.52))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("My Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task {
                await loadEvents()
            }
            .refreshable {
                await loadEvents()
            }
        }
    }

    @MainActor
    private func loadEvents() async {
        isLoading = events.isEmpty
        errorMessage = nil

        do {
            events = try await service.fetchPublishedEvents()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Saved events could not be loaded. Please try again soon."
        }
    }
}

struct SavedEventSettingsCard: View {
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var deviceCalendarStore: DeviceCalendarStore
    let event: LocalEvent
    @State private var showPlanSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                ListingRemoteImageView(
                    image: event.primaryImage,
                    context: "saved settings event=\(String(event.id.uuidString.prefix(8)))",
                    contentMode: .fill
                ) {
                    EventImagePlaceholderView()
                }
                .frame(width: 82, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("\(event.dateText) · \(event.timeText)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        .lineLimit(2)

                    Text("\(event.venue), \(event.displayLocationName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 7) {
                ForEach(engagementStore.engagementKind(for: event)) { kind in
                    Label(kind.rawValue, systemImage: kind.icon)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(PCCTheme.leafGreen.opacity(0.09), in: Capsule())
                }

                if reminderStore.hasReminder(for: event) {
                    Label(reminderStore.reminderTitle(for: event), systemImage: "alarm.waves.left.and.right.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(PCCTheme.pohutukawaOrange.opacity(0.11), in: Capsule())
                }

                if deviceCalendarStore.hasAddedCalendarEvent(for: event) {
                    Label("Calendar", systemImage: "calendar.badge.checkmark")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(PCCTheme.leafGreen.opacity(0.09), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Button {
                    engagementStore.toggleSaved(event)
                } label: {
                    Label(engagementStore.isSaved(event) ? "Unsave" : "Save", systemImage: "bookmark")
                }

                Button {
                    engagementStore.toggleInterested(event)
                } label: {
                    Label(engagementStore.isInterested(event) ? "Not Interested" : "Interested", systemImage: "star")
                }

                Button {
                    toggleGoing()
                } label: {
                    Label(engagementStore.isGoing(event) ? "Not Going" : "Going", systemImage: "checkmark.circle")
                }

                Button {
                    showPlanSheet = true
                } label: {
                    Label("Plan", systemImage: "alarm")
                }
            }
            .font(.caption.weight(.black))
            .buttonStyle(.plain)
            .foregroundStyle(PCCTheme.ink.opacity(0.66))
        }
        .padding(14)
        .pccCardStyle()
        .sheet(isPresented: $showPlanSheet) {
            EventPlanSheet(event: event)
                .environmentObject(reminderStore)
                .environmentObject(deviceCalendarStore)
        }
    }

    private func toggleGoing() {
        let isGoing = engagementStore.toggleGoing(event)
        reminderStore.syncReminder(for: event, isGoing: isGoing)
    }
}

struct SettingsInfoSheet: View {
    let title: String
    let icon: String
    let paragraphs: [String]
    let dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(title, systemImage: icon)
                            .font(.system(size: 32, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.72))
                                    .lineSpacing(4)
                            }
                        }
                        .padding(18)
                        .pccCardStyle()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

struct ReviewQueueRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PCCTheme.leafGreen)
                .frame(width: 30, height: 30)
                .background(PCCTheme.leafGreen.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Review Queue")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.78))

                Text("For authorised listing reviewers.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.30))
        }
        .padding(14)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}

struct OwnerSupportRow: View {
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.48))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.64), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Owner Support")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.72))

                Text("For authorised listing reviewers only.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
            }

            Spacer()

            if isSignedIn {
                Text("Signed in")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.30))
            }
        }
        .padding(14)
        .background(.white.opacity(0.50), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}
