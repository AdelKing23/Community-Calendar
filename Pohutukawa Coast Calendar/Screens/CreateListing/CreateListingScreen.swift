import SwiftUI

struct CreateListingScreen: View {
    enum Field: Hashable {
        case title
        case venue
        case cost
        case contactName
        case contactEmail
        case description
    }

    enum AuthMode {
        case signUp
        case signIn
    }

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var draft = PendingListingDraft()
    @State private var authMode: AuthMode = .signUp
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var accountError: String?
    @State private var isAuthenticating = false
    @State private var didSubmit = false
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submittedListingID: UUID?
    @FocusState private var focusedField: Field?
    private let listingService: EventListingSubmitting = SupabaseEventService()
    let onNavigateHome: () -> Void
    let onNavigateWhatsOn: () -> Void

    init(
        onNavigateHome: @escaping () -> Void = {},
        onNavigateWhatsOn: @escaping () -> Void = {}
    ) {
        self.onNavigateHome = onNavigateHome
        self.onNavigateWhatsOn = onNavigateWhatsOn
    }

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    CreateListingHero()

                    if !userSessionStore.isSignedIn {
                        ListingAccountGate(
                            mode: $authMode,
                            email: $accountEmail,
                            password: $accountPassword,
                            isAuthenticating: isAuthenticating,
                            errorMessage: accountError
                        ) {
                            focusedField = nil
                            Task { await authenticate() }
                        }
                    } else if didSubmit {
                        SubmissionReceivedCard(
                            listingID: submittedListingID,
                            onCreateAnother: resetForAnotherListing,
                            onNavigateHome: onNavigateHome,
                            onNavigateWhatsOn: onNavigateWhatsOn
                        )
                    } else {
                        SignedInListingBanner(email: userSessionStore.email) {
                            userSessionStore.signOut()
                            resetForAnotherListing()
                        }

                        PendingListingForm(
                            draft: $draft,
                            focusedField: $focusedField,
                            isSubmitting: isSubmitting,
                            submissionError: submissionError
                        ) {
                            focusedField = nil
                            submitListing()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 26)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccScrollableKeyboardDismiss()
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .pccDismissesKeyboardOnTap {
            focusedField = nil
        }
        .pccKeyboardDoneToolbar {
            focusedField = nil
        }
    }

    private func resetForAnotherListing() {
        focusedField = nil
        submissionError = nil
        isSubmitting = false
        draft = PendingListingDraft()
        didSubmit = false
        submittedListingID = nil
    }

    private func submitListing() {
        guard draft.canSubmit,
              !isSubmitting,
              let accessToken = userSessionStore.session?.accessToken else { return }

        Task {
            await MainActor.run {
                isSubmitting = true
                submissionError = nil
            }

            do {
                let listingID = try await listingService.submitPendingListing(draft, accessToken: accessToken)
                await MainActor.run {
                    submittedListingID = listingID
                    didSubmit = true
                    isSubmitting = false
                    draft = PendingListingDraft()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "The listing could not be sent. Please check your connection and try again."
                }
            }
        }
    }

    @MainActor
    private func authenticate() async {
        guard !isAuthenticating else { return }

        let trimmedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.localizedCaseInsensitiveContains("@"),
              accountPassword.count >= 6 else {
            accountError = "Enter an email and a password with at least 6 characters."
            return
        }

        isAuthenticating = true
        accountError = nil

        do {
            switch authMode {
            case .signUp:
                try await userSessionStore.signUp(email: trimmedEmail, password: accountPassword)
            case .signIn:
                try await userSessionStore.signIn(email: trimmedEmail, password: accountPassword)
            }

            accountPassword = ""
            isAuthenticating = false
        } catch UserAuthError.signUpNeedsConfirmation {
            isAuthenticating = false
            accountError = "Check your email to confirm your account, then sign in."
            authMode = .signIn
            accountPassword = ""
        } catch {
            isAuthenticating = false
            accountError = authMode == .signUp
                ? "Account could not be created. Try signing in if you already have one."
                : "Sign in failed. Check your email and password, then try again."
        }
    }
}

struct ListingAccountGate: View {
    @Binding var mode: CreateListingScreen.AuthMode
    @Binding var email: String
    @Binding var password: String
    let isAuthenticating: Bool
    let errorMessage: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a free account to submit a listing.")
                    .font(.title2.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Browsing stays open to everyone. Accounts help keep submitted listings trusted and reviewable.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineSpacing(3)
            }

            HStack(spacing: 8) {
                AccountModeButton(title: "Create Account", isSelected: mode == .signUp) {
                    mode = .signUp
                }

                AccountModeButton(title: "Sign In", isSelected: mode == .signIn) {
                    mode = .signIn
                }
            }

            PCCFormField(title: "Email", text: $email, prompt: "you@example.co.nz")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                SecureField("At least 6 characters", text: $password)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(13)
                    .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }

            Button(action: onSubmit) {
                Label(buttonTitle, systemImage: isAuthenticating ? "hourglass" : "person.crop.circle.badge.plus")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(isAuthenticating ? PCCTheme.ink.opacity(0.28) : PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .disabled(isAuthenticating)
        }
        .padding(20)
        .pccCardStyle()
    }

    private var buttonTitle: String {
        if isAuthenticating {
            return mode == .signUp ? "Creating Account" : "Signing In"
        }

        return mode == .signUp ? "Create Account" : "Sign In"
    }
}

struct AccountModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(isSelected ? .white : PCCTheme.leafGreen)
                .background(isSelected ? PCCTheme.leafGreen : PCCTheme.cream.opacity(0.70), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SignedInListingBanner: View {
    let email: String?
    let onSignOut: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(PCCTheme.leafGreen)

            VStack(alignment: .leading, spacing: 3) {
                Text("Submitting as")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.50))

                Text(email ?? "Signed-in account")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(1)
            }

            Spacer()

            Button("Sign Out", action: onSignOut)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaRed)
        }
        .padding(14)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct CreateListingHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submit an Event")
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            Text("Send a \(CommunityArea.defaultAreaName) listing for review. Approved events appear in the public calendar.")
                .font(.title3.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct PendingListingForm: View {
    @Binding var draft: PendingListingDraft
    @FocusState.Binding var focusedField: CreateListingScreen.Field?
    let isSubmitting: Bool
    let submissionError: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Listing Details")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            PCCFormField(title: "Event Name", text: $draft.title, prompt: "Coastal concert, market, class")
                .focused($focusedField, equals: .title)
            PCCFormField(title: "Venue", text: $draft.venue, prompt: "Hall, beach, club, cafe")
                .focused($focusedField, equals: .venue)

            Picker("Town", selection: $draft.town) {
                ForEach(CoastTown.allCases.filter { $0 != .all }) { town in
                    Text(town.rawValue).tag(town)
                }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $draft.category) {
                ForEach(EventCategory.allCases) { category in
                    Text(category.shortLabel).tag(category)
                }
            }

            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)

            PCCFormField(title: "Cost", text: $draft.priceLabel, prompt: "Free, koha, $20")
                .focused($focusedField, equals: .cost)
            PCCFormField(title: "Contact Name", text: $draft.contactName, prompt: "Organiser or venue")
                .focused($focusedField, equals: .contactName)
            PCCFormField(title: "Contact Email", text: $draft.contactEmail, prompt: "name@example.co.nz")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .contactEmail)

            VStack(alignment: .leading, spacing: 8) {
                Text("Short Description")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                TextEditor(text: $draft.shortDescription)
                    .frame(minHeight: 112)
                    .focused($focusedField, equals: .description)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            ListingReviewNote()

            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }

            Button(action: onSubmit) {
                Label(isSubmitting ? "Sending Listing" : "Submit for Review", systemImage: isSubmitting ? "hourglass" : "paperplane.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(draft.canSubmit && !isSubmitting ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.28), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .disabled(!draft.canSubmit || isSubmitting)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(PCCTheme.ink)
        .padding(20)
        .pccCardStyle()
    }
}

struct ListingReviewNote: View {
    var body: some View {
        Label("Listings are reviewed before they appear publicly.", systemImage: "checkmark.seal")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.64))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct PCCFormField: View {
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

struct SubmissionReceivedCard: View {
    let listingID: UUID?
    let onCreateAnother: () -> Void
    let onNavigateHome: () -> Void
    let onNavigateWhatsOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(PCCTheme.leafGreen)

            Text("Listing Sent for Review")
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("Thanks. The event will stay pending until it has been checked and approved for the public feed.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)

            if let listingID {
                Text("Listing reference: \(String(listingID.uuidString.prefix(8)))")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
                    .padding(.top, 2)
            }

            VStack(spacing: 10) {
                Button(action: onCreateAnother) {
                    Label("Create Another Listing", systemImage: "plus.circle.fill")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                HStack(spacing: 10) {
                    Button(action: onNavigateHome) {
                        Label("Back to Home", systemImage: "house.fill")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    Button(action: onNavigateWhatsOn) {
                        Label("What's On", systemImage: "calendar")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.leafGreen)
                .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}
