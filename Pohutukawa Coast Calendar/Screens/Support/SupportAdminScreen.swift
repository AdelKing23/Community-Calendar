import SwiftUI

struct SupportAdminScreen: View {
    @State private var ownerSession: OwnerSession?
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var loginError: String?

    private let supportService: OwnerAuthenticating & OwnerEventReviewing = SupabaseEventService()

    var body: some View {
        ZStack {
            PCCScreenBackground()

            if let ownerSession {
                SupportDashboard(
                    ownerSession: ownerSession,
                    supportService: supportService
                ) {
                    self.ownerSession = nil
                    email = ""
                    password = ""
                    loginError = nil
                }
            } else {
                SupportLoginGate(
                    email: $email,
                    password: $password,
                    isSigningIn: isSigningIn,
                    loginError: loginError
                ) {
                    Task { await signIn() }
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func signIn() async {
        guard !isSigningIn else { return }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.localizedCaseInsensitiveContains("@"),
              !password.isEmpty else {
            loginError = "Enter the owner email and password."
            return
        }

        isSigningIn = true
        loginError = nil

        do {
            ownerSession = try await supportService.signInOwner(email: trimmedEmail, password: password)
            password = ""
            isSigningIn = false
        } catch {
            isSigningIn = false
            loginError = "Login failed. Check the owner email and password, then try again."
        }
    }
}

struct SupportLoginGate: View {
    @Binding var email: String
    @Binding var password: String
    let isSigningIn: Bool
    let loginError: String?
    let onLogin: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Launch Support Tools")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Owner-only approval tools for reviewing submitted listings. Public users do not need an account.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .lineSpacing(3)
                }
                .padding(20)
                .pccCardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    PCCSupportField(title: "Owner Email", text: $email, prompt: "owner@example.co.nz")
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))

                        SecureField("Supabase Auth password", text: $password)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(13)
                            .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }

                    if let loginError {
                        Label(loginError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PCCTheme.pohutukawaRed)
                    }

                    Button(action: onLogin) {
                        Label(isSigningIn ? "Signing In" : "Sign In", systemImage: isSigningIn ? "hourglass" : "lock.open.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(isSigningIn ? PCCTheme.ink.opacity(0.28) : PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    .disabled(isSigningIn)

                    Text("Uses Supabase Auth and owner-only RLS. No admin key is stored in the app.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.56))
                        .lineSpacing(2)
                }
                .padding(20)
                .pccCardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
        }
        .pccBottomKeyboardInset(PCCKeyboardSpacing.standardBottomInset)
        .pccScrollableKeyboardDismiss()
        .pccDismissesKeyboardOnTap()
    }
}

struct SupportDashboard: View {
    let ownerSession: OwnerSession
    let supportService: OwnerEventReviewing
    let onLogout: () -> Void

    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?
    @State private var updatingEventID: UUID?

    private var pendingEvents: [LocalEvent] {
        events
            .filter { $0.listingStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var publishedEvents: [LocalEvent] {
        events
            .filter { $0.listingStatus == .published }
            .sorted { $0.startDate < $1.startDate }
    }

    private var rejectedEvents: [LocalEvent] {
        events
            .filter { $0.listingStatus == .rejected }
            .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
    }

    private var archivedEvents: [LocalEvent] {
        events
            .filter { $0.listingStatus == .archived }
            .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SupportHeaderCard(onLogout: onLogout)

                if let actionMessage {
                    Label(actionMessage, systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                }

                if isLoading {
                    SupportPanel(title: "Loading Listings", icon: "arrow.clockwise") {
                        ProgressView()
                            .tint(PCCTheme.pohutukawaOrange)
                    }
                } else if let loadError {
                    SupportPanel(title: "Support Data", icon: "wifi.exclamationmark") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(loadError)
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.pohutukawaRed)

                            Button("Try Again") {
                                Task { await loadOwnerEvents() }
                            }
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                        }
                    }
                }

                PendingListingsReviewPanel(
                    events: pendingEvents,
                    updatingEventID: updatingEventID,
                    onSetStatus: { event, status in
                        Task { await update(event, to: status) }
                    }
                )

                SupportEventListPanel(title: "Published Events", icon: "calendar.badge.checkmark", events: publishedEvents)
                SupportEventListPanel(title: "Rejected", icon: "xmark.seal", events: rejectedEvents)
                SupportEventListPanel(title: "Archived", icon: "archivebox", events: archivedEvents)

                Text("Field editing is intentionally held for the next pass. This version proves owner login plus approve, reject and archive first.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
        }
        .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        .pccScrollableKeyboardDismiss()
        .pccDismissesKeyboardOnTap()
        .task {
            await loadOwnerEvents()
        }
        .refreshable {
            await loadOwnerEvents()
        }
    }

    @MainActor
    private func loadOwnerEvents() async {
        isLoading = events.isEmpty
        loadError = nil

        do {
            events = try await supportService.fetchOwnerEvents(accessToken: ownerSession.accessToken)
            isLoading = false
        } catch {
            isLoading = false
            loadError = "Support listings could not be loaded. If your session expired, log out and sign in again."
        }
    }

    @MainActor
    private func update(_ event: LocalEvent, to status: ListingStatus) async {
        updatingEventID = event.id
        actionMessage = nil

        do {
            try await supportService.updateEventStatus(id: event.id, status: status, accessToken: ownerSession.accessToken)
            actionMessage = "\(event.title) moved to \(status.supportLabel)."
            updatingEventID = nil
            await loadOwnerEvents()
        } catch {
            updatingEventID = nil
            loadError = "Could not update this listing. If your session expired, log out and sign in again."
        }
    }
}

struct SupportHeaderCard: View {
    let onLogout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support Dashboard")
                        .font(.system(size: 34, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Review submitted listings, then publish, reject or archive them.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                }

                Spacer()

                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaRed)
                        .padding(10)
                        .background(PCCTheme.pohutukawaRed.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Private review details are visible only after owner login.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.56))
        }
        .padding(20)
        .pccCardStyle()
    }
}

struct PendingListingsReviewPanel: View {
    let events: [LocalEvent]
    let updatingEventID: UUID?
    let onSetStatus: (LocalEvent, ListingStatus) -> Void

    var body: some View {
        SupportPanel(title: "Pending Listings", icon: "tray.full") {
            if events.isEmpty {
                Text("No pending listings are waiting for review.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
            } else {
                VStack(spacing: 12) {
                    ForEach(events) { event in
                        PendingListingReviewCard(
                            event: event,
                            isUpdating: updatingEventID == event.id,
                            onSetStatus: onSetStatus
                        )
                    }
                }
            }
        }
    }
}

struct PendingListingReviewCard: View {
    let event: LocalEvent
    let isUpdating: Bool
    let onSetStatus: (LocalEvent, ListingStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("\(event.category.rawValue) · \(event.town.rawValue)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }

                Spacer()

                Text(event.createdAt.formatted(.dateTime.day().month().hour().minute()))
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 7) {
                SupportDetailRow(icon: "mappin.and.ellipse", title: "Venue", value: event.venue)
                SupportDetailRow(icon: "clock", title: "Time", value: event.timeText)
                SupportDetailRow(icon: "tag", title: "Price", value: event.priceLabel)
                SupportDetailRow(icon: "person.2", title: "Audience", value: event.audience)
            }

            Text(event.longDescription)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.70))
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 7) {
                Text("Review Contact")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))

                SupportDetailRow(icon: "person", title: "Name", value: event.contactName ?? "Not supplied")
                SupportDetailRow(icon: "envelope", title: "Email", value: event.contactEmail ?? "Not supplied")
                SupportDetailRow(icon: "phone", title: "Phone", value: event.contactPhone ?? "Not supplied")
            }
            .padding(12)
            .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            HStack(spacing: 9) {
                SupportStatusButton(title: "Publish", icon: "checkmark.seal.fill", color: PCCTheme.leafGreen, isUpdating: isUpdating) {
                    onSetStatus(event, .published)
                }

                SupportStatusButton(title: "Reject", icon: "xmark.seal.fill", color: PCCTheme.pohutukawaRed, isUpdating: isUpdating) {
                    onSetStatus(event, .rejected)
                }

                SupportStatusButton(title: "Archive", icon: "archivebox.fill", color: PCCTheme.ink.opacity(0.74), isUpdating: isUpdating) {
                    onSetStatus(event, .archived)
                }
            }
        }
        .padding(14)
        .background(PCCTheme.cream.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct SupportEventListPanel: View {
    let title: String
    let icon: String
    let events: [LocalEvent]

    var body: some View {
        SupportPanel(title: title, icon: icon) {
            if events.isEmpty {
                Text("No listings in this section.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.64))
            } else {
                VStack(spacing: 10) {
                    ForEach(events.prefix(8)) { event in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(PCCTheme.ink)

                                Text("\(event.town.rawValue) · \(event.venue)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.62))

                                Text(event.dateText)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                            }

                            Spacer()

                            Text(event.listingStatus.supportLabel)
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.leafGreen)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PCCTheme.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                }
            }
        }
    }
}

struct SupportStatusButton: View {
    let title: String
    let icon: String
    let color: Color
    let isUpdating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isUpdating ? "hourglass" : icon)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(isUpdating ? PCCTheme.ink.opacity(0.28) : color, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .disabled(isUpdating)
    }
}

struct SupportPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct PCCSupportField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .padding(13)
                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
    }
}

struct SupportDetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))

                Text(value)
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.76))
            }
        }
    }
}

private extension ListingStatus {
    var supportLabel: String {
        switch self {
        case .pendingReview: return "Pending"
        case .published: return "Published"
        case .rejected: return "Rejected"
        case .archived: return "Archived"
        }
    }
}
