import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @AppStorage(PCCWallpaperStyle.storageKey) private var selectedWallpaper = PCCWallpaperStyle.ornament.rawValue
    let onNavigateCreate: () -> Void
    @State private var canOpenReviewQueue = false
    @State private var selectedDocument: SettingsDocument?
    @State private var showWallpaperPicker = false
    @State private var showContactSupport = false
    @State private var showPayments = false
    @State private var showSavedReminders = false
    @State private var showListingAnalytics = false
    @State private var showMyListings = false

    private let supportService: OwnerEventReviewing = SupabaseEventService()

    init(onNavigateCreate: @escaping () -> Void = {}) {
        self.onNavigateCreate = onNavigateCreate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        accountSection

                        if userSessionStore.isSignedIn {
                            Button {
                                userSessionStore.signOut()
                            } label: {
                                SettingsSignOutRow()
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsActionSection(title: "My Listings") {
                            Button {
                                showMyListings = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "previous-listings",
                                        icon: "rectangle.stack",
                                        title: "Your listings",
                                        subtitle: "Review, edit, remove, and follow Support feedback for your listings.",
                                        detail: userSessionStore.isSignedIn ? "Open" : "Sign in",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsActionSection(title: "Analytics") {
                            Button {
                                showListingAnalytics = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "listing-analytics",
                                        icon: "chart.bar.xaxis",
                                        title: "Listing insights",
                                        subtitle: "See simple per-listing activity. Boost + Insights shows a deeper graph.",
                                        detail: userSessionStore.isSignedIn ? "Open" : "Sign in",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        } footer: {
                            Text("Analytics are privacy-friendly and aggregated. Soft-launch numbers are placeholders until server tracking is connected.")
                        }

                        SettingsActionSection(title: "Saved & Reminders") {
                            Button {
                                showSavedReminders = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "saved-reminders",
                                        icon: "bookmark",
                                        title: "Saved events",
                                        subtitle: "Saved, going and interested events will appear here.",
                                        detail: "Soon",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsActionSection(title: "Payments") {
                            Button {
                                showPayments = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "payments",
                                        icon: "creditcard",
                                        title: "Payments and receipts",
                                        subtitle: "Listing payments and receipts will appear here once paid options are live.",
                                        detail: "Soon",
                                        style: .disclosure,
                                        isEnabled: true
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        } footer: {
                            Text("Community Calendar will not store card details. Payments will be handled securely by Stripe.")
                        }

                        SettingsActionSection(title: "Wallpaper") {
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
                        }

                        SettingsDocumentsSection(selectedDocument: $selectedDocument)

                        SettingsListSection(
                            title: "Area",
                            rows: [
                                SettingsRowContent(
                                    id: "current-area",
                                    icon: "mappin.and.ellipse",
                                    title: "Current area",
                                    subtitle: CommunityArea.defaultAreaName,
                                    detail: nil,
                                    style: .plain,
                                    isEnabled: true
                                )
                            ],
                            footer: "More communities coming soon."
                        )

                        SettingsActionSection(title: "Contact Support") {
                            Button {
                                showContactSupport = true
                            } label: {
                                SettingsRow(
                                    content: SettingsRowContent(
                                        id: "contact",
                                        icon: "envelope",
                                        title: "Contact \(CommunityArea.appBrandName)",
                                        subtitle: "Send a short support request from this app once support sending is connected.",
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
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationBarHidden(true)
            .task(id: userSessionStore.session?.userID) {
                await checkReviewQueueAccess()
            }
            .sheet(item: $selectedDocument) { document in
                SettingsDocumentScreen(document: document)
            }
            .sheet(isPresented: $showWallpaperPicker) {
                WallpaperPickerScreen()
            }
            .sheet(isPresented: $showContactSupport) {
                ContactSupportPlaceholderScreen()
            }
            .sheet(isPresented: $showPayments) {
                PaymentsPlaceholderScreen()
            }
            .sheet(isPresented: $showSavedReminders) {
                SavedRemindersPlaceholderScreen()
            }
            .sheet(isPresented: $showListingAnalytics) {
                ListingAnalyticsSettingsScreen()
                    .environmentObject(userSessionStore)
            }
            .sheet(isPresented: $showMyListings) {
                MyListingsSettingsScreen()
                    .environmentObject(userSessionStore)
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if userSessionStore.isSignedIn {
            SettingsListSection(
                title: "Account",
                rows: [
                    SettingsRowContent(
                        id: "account-details",
                        icon: "person.crop.circle.fill",
                        title: "Account details",
                        subtitle: userSessionStore.email ?? "Signed-in account",
                        detail: "Active",
                        style: .status,
                        isEnabled: true
                    )
                ]
            )
        } else {
            SettingsActionSection(title: "Account") {
                Button {
                    onNavigateCreate()
                } label: {
                    SettingsRow(
                        content: SettingsRowContent(
                            id: "join-community",
                            icon: "person.crop.circle.badge.plus",
                            title: "Create account / Sign in",
                            subtitle: "Create a free account when you are ready to submit and manage listings.",
                            detail: "Create tab",
                            style: .disclosure,
                            isEnabled: true
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func checkReviewQueueAccess() async {
        guard let currentSession = userSessionStore.session else {
            canOpenReviewQueue = false
            return
        }

        await userSessionStore.refreshIfNeeded()
        let activeSession = userSessionStore.session ?? currentSession
        canOpenReviewQueue = SupportAccessPolicy.isSupportAccount(email: activeSession.email)
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
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content()
            }
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )

            footer()
                .font(.footnote.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.56))
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
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                .textCase(.uppercase)

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
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
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

            Text("Sign Out")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaRed)

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
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
        case .terms: return "Terms and conditions"
        case .privacy: return "Privacy policy"
        case .postingRules: return "Community posting rules"
        case .paymentRefunds: return "Payment / refund notes"
        case .communityStandards: return "Community standards"
        }
    }

    var subtitle: String {
        switch self {
        case .terms:
            return "How listings are reviewed and published."
        case .privacy:
            return "How account and listing information is used."
        case .postingRules:
            return "What belongs on Community Calendar."
        case .paymentRefunds:
            return "Paid promotion notes for later launch stages."
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
                "Community Calendar provides a local listing platform for events, activities and community notices.",
                "Listings are reviewed before publishing. Community Calendar may approve, reject, edit, archive, remove or decline to publish a listing at its discretion.",
                "You are responsible for making sure your listing is accurate, lawful, safe, and that you have permission to publish any words, images or contact details you provide.",
                "Publishing a listing does not mean Community Calendar endorses the event, organiser, product or service."
            ]
        case .privacy:
            return [
                "Community Calendar uses account and listing information to operate accounts, receive submissions, review listings, provide support, keep the platform safe, and support payments when paid options are added.",
                "Contact details submitted with a listing may be used for review and support. Optional public event contact details, when supplied, may appear on the published listing.",
                "Community Calendar does not sell personal information.",
                "When payments are added, card details will be handled by the payment provider. Community Calendar will not store card details in the app."
            ]
        case .postingRules:
            return [
                "Listings should be local, useful, accurate, and written for the community area selected in the app.",
                "Do not submit misleading, illegal, hateful, unsafe, adult, scam, spam, or abusive content.",
                "Commercial listings must use the correct paid or promotional option when those options are live. Free community listing paths must not be used to avoid listing fees.",
                "Images must be relevant to the listing and suitable for a general community audience."
            ]
        case .paymentRefunds:
            return [
                "Paid listing and promotion tools are coming soon.",
                "Payments will be handled securely by Stripe or another payment provider. Community Calendar will not store card details.",
                "Paid promotion improves placement or visibility where offered, but it does not guarantee attendance, sales, bookings or enquiries.",
                "Refunds or credits may be offered at Community Calendar’s discretion unless required by law."
            ]
        case .communityStandards:
            return [
                "Community Calendar should feel useful, calm and trustworthy for local people.",
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

struct ContactSupportPlaceholderScreen: View {
    enum Topic: String, CaseIterable, Identifiable {
        case listing = "Listing help"
        case account = "Account"
        case payment = "Payment"
        case safety = "Safety or content"
        case other = "Other"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var topic: Topic = .listing
    @State private var listingReference = ""
    @State private var message = ""
    @State private var showComingSoon = false

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contact Support")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        VStack(alignment: .leading, spacing: 14) {
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

                            if showComingSoon {
                                Label("Support request sending is coming soon. For soft launch testing, send feedback directly to the app owner.", systemImage: "paperplane")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PCCTheme.leafGreen)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button {
                                showComingSoon = true
                            } label: {
                                Text("Send Support Request")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }
                        .padding(18)
                        .pccCardStyle()
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

struct PaymentsPlaceholderScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("Payments")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Paid listing options are being prepared for launch. No card details are stored by Community Calendar.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ListingTier.allCases) { tier in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(tier.priceText)
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(tier.isPaidTier ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
                                        .frame(width: 54, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tier.title)
                                            .font(.headline.weight(.black))
                                            .foregroundStyle(PCCTheme.ink)

                                        Text(tier.shortDescription)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(13)
                                .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            }
                        }
                        .padding(18)
                        .pccCardStyle()

                        SettingsInfoMessage(
                            icon: "lock.shield",
                            title: "Payment handling",
                            message: "In-app boosts will use Apple’s purchase system where required. Stripe may be used later for external tickets, invoices or sponsor payments. Receipts will appear here when paid options are live."
                        )

                        SettingsInfoMessage(
                            icon: "shippingbox",
                            title: "Purchase setup",
                            message: "StoreKit product IDs are prepared for Commercial, Boost, and Boost + Insights. Purchase buttons stay off until App Store products and payment tracking are connected."
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Payments")
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

struct ListingAnalyticsSettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var listings: [LocalEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
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

                            Text("Track what each listing is doing. Free listings get a simple view; Boost + Insights gets the deeper graph.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if !userSessionStore.isSignedIn {
                            SettingsInfoMessage(
                                icon: "person.crop.circle.badge.plus",
                                title: "Sign in to see your listings",
                                message: "Analytics are attached to listings you submit from your account."
                            )
                        } else if isLoading {
                            SettingsInfoMessage(
                                icon: "arrow.clockwise",
                                title: "Loading insights",
                                message: "Fetching your submitted listings."
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
            .refreshable {
                await loadListings()
            }
        }
    }

    @MainActor
    private func loadListings() async {
        guard let session = userSessionStore.session else { return }

        isLoading = listings.isEmpty
        errorMessage = nil

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            listings = try await service.fetchUserListings(userID: activeSession.userID, accessToken: activeSession.accessToken)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Your listing insights could not be loaded. Please try again soon."
        }
    }
}

struct MyListingsSettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var listings: [LocalEvent] = []
    @State private var changeRequests: [EventChangeRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var selectedUserListing: LocalEvent?
    @State private var selectedEditListing: LocalEvent?
    @State private var selectedRemovalListing: LocalEvent?
    private let service: UserListingFetching & EventChangeRequesting = SupabaseEventService()

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

                            Text("Your submitted, pending, published, rejected and archived listings stay here with Support feedback attached.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if !userSessionStore.isSignedIn {
                            SettingsInfoMessage(
                                icon: "person.crop.circle.badge.plus",
                                title: "Sign in to manage listings",
                                message: "Create or sign into an account from the Create tab before submitting listings."
                            )
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
            .refreshable {
                await loadListings()
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
        guard let session = userSessionStore.session else { return }

        isLoading = listings.isEmpty
        errorMessage = nil

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            listings = try await service.fetchUserListings(userID: activeSession.userID, accessToken: activeSession.accessToken)
            changeRequests = try await service.fetchMyChangeRequests(userID: activeSession.userID, accessToken: activeSession.accessToken)
            isLoading = false
        } catch {
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
            actionMessage = "Edit request could not be sent. Please try again."
        }
    }

    @MainActor
    private func submitRemovalRequest(for listing: LocalEvent, note: String?) async {
        guard let session = userSessionStore.session else { return }

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? session
            try await service.createRemovalRequest(
                event: listing,
                requesterID: activeSession.userID,
                requesterNote: note,
                accessToken: activeSession.accessToken
            )
            actionMessage = "Removal request sent for \(listing.title)."
            selectedRemovalListing = nil
            await loadListings()
        } catch {
            actionMessage = "Removal request could not be sent. Please try again."
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

                        Text("\(event.inferredListingTier.title) · \(event.listingStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    }

                    Spacer()

                    Text(event.inferredListingTier.includesInsights ? "Graph" : "Basic")
                        .font(.caption.weight(.black))
                        .foregroundStyle(event.inferredListingTier.includesInsights ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background((event.inferredListingTier.includesInsights ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen).opacity(0.10), in: Capsule())

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

struct SavedRemindersPlaceholderScreen: View {
    @EnvironmentObject private var engagementStore: EventEngagementStore
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
                            Text("Saved & Reminders")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Events you save, mark interested, or mark going appear here on this device.")
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

                        Text("Reminder notifications and cross-device syncing are not connected yet.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.52))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Saved")
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
    let event: LocalEvent

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

                    Text("\(event.venue), \(event.town.rawValue)")
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
                    engagementStore.toggleGoing(event)
                } label: {
                    Label(engagementStore.isGoing(event) ? "Not Going" : "Going", systemImage: "checkmark.circle")
                }
            }
            .font(.caption.weight(.black))
            .buttonStyle(.plain)
            .foregroundStyle(PCCTheme.ink.opacity(0.66))
        }
        .padding(14)
        .pccCardStyle()
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
