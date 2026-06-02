import SwiftUI

struct SupportAdminScreen: View {
    @State private var isLoggedIn = false
    @State private var email = ""
    @State private var pin = ""
    @State private var loginError: String?

    var body: some View {
        ZStack {
            PCCScreenBackground()

            if isLoggedIn {
                SupportDashboard {
                    email = ""
                    pin = ""
                    loginError = nil
                    isLoggedIn = false
                }
            } else {
                SupportLoginGate(
                    email: $email,
                    pin: $pin,
                    loginError: loginError
                ) {
                    attemptLogin()
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func attemptLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.localizedCaseInsensitiveContains("@"),
              pin.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 else {
            loginError = "Enter an owner email placeholder and local launch PIN."
            return
        }

        loginError = nil
        isLoggedIn = true
    }
}

struct SupportLoginGate: View {
    @Binding var email: String
    @Binding var pin: String
    let loginError: String?
    let onLogin: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Launch Support Tools")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Owner-only tools for launch testing. This local gate is UI-ready only and is not Supabase Auth yet.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .lineSpacing(3)
                }
                .padding(20)
                .pccCardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    PCCSupportField(title: "Owner Email Placeholder", text: $email, prompt: "owner@example.co.nz")
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local Launch PIN")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))

                        SecureField("Enter local PIN", text: $pin)
                            .textFieldStyle(.plain)
                            .keyboardType(.numberPad)
                            .padding(13)
                            .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }

                    if let loginError {
                        Label(loginError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PCCTheme.pohutukawaRed)
                    }

                    Button(action: onLogin) {
                        Label("Open Support Dashboard", systemImage: "lock.open.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                    Text("MVP note: this is a local support gate only. Publishing, rejecting and archiving still require a safe Supabase owner policy or server function.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.56))
                        .lineSpacing(2)
                }
                .padding(20)
                .pccCardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 124)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct SupportDashboard: View {
    @State private var publishedEvents: [LocalEvent] = []
    @State private var isLoadingPublished = false
    @State private var publishedError: String?
    @State private var supportEmail = ""
    @State private var supportPhone = ""
    @State private var supportWebsite = ""

    private let eventService: PublishedEventFetching = SupabaseEventService()
    let onLogout: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Support Dashboard")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text("Owner-only launch tools for reviewing listings and keeping the public calendar tidy.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    }

                    Spacer()
                }
                .padding(20)
                .pccCardStyle()

                PendingListingsPanel()
                PublishedEventsPanel(events: publishedEvents, isLoading: isLoadingPublished, error: publishedError) {
                    Task { await loadPublishedEvents() }
                }
                SupportContactsPanel(email: $supportEmail, phone: $supportPhone, website: $supportWebsite)
                LaunchChecklistPanel()

                Button(action: onLogout) {
                    Label("Log out of Support mode", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.pohutukawaRed, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 124)
        }
        .task {
            await loadPublishedEvents()
        }
        .refreshable {
            await loadPublishedEvents()
        }
    }

    @MainActor
    private func loadPublishedEvents() async {
        isLoadingPublished = publishedEvents.isEmpty
        publishedError = nil

        do {
            publishedEvents = try await eventService.fetchPublishedEvents()
            isLoadingPublished = false
        } catch {
            isLoadingPublished = false
            publishedError = "Published events could not be loaded."
        }
    }
}

struct PendingListingsPanel: View {
    var body: some View {
        SupportPanel(title: "Pending Listings", icon: "tray.full") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pending listings are currently reviewed in Supabase Table Editor during MVP.")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("This local support screen cannot read or approve pending listings yet because public RLS blocks pending reads. In-app approval requires real owner login and owner-only RLS, coming next.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineSpacing(3)

                SupportStatusRow(icon: "tablecells", title: "Review source", value: "Supabase Table Editor")
                SupportStatusRow(icon: "checkmark.seal", title: "Approve", value: "Set status to published")
                SupportStatusRow(icon: "xmark.seal", title: "Reject", value: "Set status to rejected")
                SupportStatusRow(icon: "archivebox", title: "Archive", value: "Set status to archived")
            }
        }
    }
}

struct PublishedEventsPanel: View {
    let events: [LocalEvent]
    let isLoading: Bool
    let error: String?
    let reload: () -> Void

    var body: some View {
        SupportPanel(title: "Published Events", icon: "calendar.badge.checkmark") {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(PCCTheme.pohutukawaOrange)
                } else if let error {
                    Text(error)
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.pohutukawaRed)

                    Button("Try Again", action: reload)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                } else if events.isEmpty {
                    Text("No published events are currently visible.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                } else {
                    ForEach(events) { event in
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
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PCCTheme.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                }

                Text("Archive, unpublish, feature and edit actions need a safe owner-only Supabase policy or server-side function before going live.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
                    .lineSpacing(2)
            }
        }
    }
}

struct SupportContactsPanel: View {
    @Binding var email: String
    @Binding var phone: String
    @Binding var website: String

    var body: some View {
        SupportPanel(title: "Support Contacts", icon: "person.2.wave.2") {
            VStack(alignment: .leading, spacing: 12) {
                PCCSupportField(title: "Email", text: $email, prompt: "hello@example.co.nz")
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                PCCSupportField(title: "Phone", text: $phone, prompt: "Add public phone before launch")
                    .keyboardType(.phonePad)

                PCCSupportField(title: "Website / Social", text: $website, prompt: "website or social link")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: 10) {
                    SupportQuickAction(title: "Report an issue", icon: "exclamationmark.bubble")
                    SupportQuickAction(title: "Submit an event", icon: "paperplane")
                }

                Text("These values stay local during launch testing. Public contact details can be added before launch, and database-backed support contacts can come later.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
            }
        }
    }
}

struct LaunchChecklistPanel: View {
    private let items = [
        ("Supabase connected", true),
        ("Public feed reads published events", true),
        ("Create Listing submits pending_review", true),
        ("Support review tools available", false),
        ("Contact details added", false),
        ("Real events added", false),
        ("Test on iPhone complete", false)
    ]

    var body: some View {
        SupportPanel(title: "App / Launch Checklist", icon: "checklist") {
            VStack(spacing: 10) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.1 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.1 ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.34))

                        Text(item.0)
                            .font(.body.weight(.bold))
                            .foregroundStyle(PCCTheme.ink.opacity(item.1 ? 0.82 : 0.58))

                        Spacer()
                    }
                }
            }
        }
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

struct SupportStatusRow: View {
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

struct SupportQuickAction: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(PCCTheme.leafGreen)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}
