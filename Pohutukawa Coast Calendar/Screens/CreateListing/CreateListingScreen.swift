import SwiftUI
import PhotosUI
import UIKit

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
    @State private var isLoadingPhotos = false
    @State private var submissionError: String?
    @State private var submissionStatus: String?
    @State private var submissionNotice: String?
    @State private var submittedListingID: UUID?
    @State private var submittedListingTitle: String?
    @State private var myListings: [LocalEvent] = []
    @State private var isLoadingMyListings = false
    @State private var myListingsError: String?
    @State private var selectedUserListing: LocalEvent?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var selectedPhotos: [ListingPhotoUpload] = []
    @FocusState private var focusedField: Field?
    private let listingService: EventListingSubmitting & UserListingFetching = SupabaseEventService()
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
                            listingTitle: submittedListingTitle,
                            notice: submissionNotice,
                            onViewListing: showMyListings,
                            onCreateAnother: resetForAnotherListing,
                            onNavigateHome: onNavigateHome,
                            onNavigateWhatsOn: onNavigateWhatsOn
                        )
                    } else {
                        SignedInListingBanner(email: userSessionStore.email) {
                            userSessionStore.signOut()
                            resetForAnotherListing()
                            myListings = []
                        }

                        PendingListingForm(
                            draft: $draft,
                            focusedField: $focusedField,
                            photoPickerItems: $photoPickerItems,
                            selectedPhotos: selectedPhotos,
                            isLoadingPhotos: isLoadingPhotos,
                            isSubmitting: isSubmitting,
                            submissionStatus: submissionStatus,
                            submissionError: submissionError
                        ) {
                            focusedField = nil
                            submitListing()
                        } onRemovePhoto: { photo in
                            removePhoto(photo)
                        }

                        MyListingsPanel(
                            listings: myListings,
                            isLoading: isLoadingMyListings,
                            errorMessage: myListingsError,
                            onSelectListing: { listing in
                                selectedUserListing = listing
                            }
                        ) {
                            Task { await loadMyListings() }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
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
        .onChange(of: photoPickerItems) { _, newItems in
            Task { await loadPhotos(from: newItems) }
        }
        .task(id: userSessionStore.session?.userID) {
            guard userSessionStore.isSignedIn else { return }
            await loadMyListings()
        }
        .sheet(item: $selectedUserListing) { listing in
            UserListingDetailSheet(listing: listing)
        }
    }

    private func resetForAnotherListing() {
        focusedField = nil
        submissionError = nil
        submissionStatus = nil
        submissionNotice = nil
        isSubmitting = false
        draft = PendingListingDraft()
        didSubmit = false
        submittedListingID = nil
        submittedListingTitle = nil
        selectedPhotos = []
        photoPickerItems = []
    }

    private func showMyListings() {
        didSubmit = false
        Task { await loadMyListings() }
    }

    private func submitListing() {
        guard draft.canSubmit,
              !isSubmitting,
              userSessionStore.session != nil else { return }

        Task {
            await MainActor.run {
                isSubmitting = true
                submissionError = nil
                submissionStatus = "Sending listing"
                submissionNotice = nil
            }

            do {
                let photosToUpload = selectedPhotos
                let submittedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                await userSessionStore.refreshIfNeeded()
                guard let session = userSessionStore.session else {
                    throw UserAuthError.signInFailed
                }

                let listingID = try await listingService.submitPendingListing(draft, accessToken: session.accessToken)

                do {
                    for (index, photo) in photosToUpload.enumerated() {
                        await MainActor.run {
                            submissionStatus = "Uploading photo \(index + 1) of \(photosToUpload.count)"
                        }

                        try await listingService.uploadListingImage(
                            photo,
                            eventID: listingID,
                            userID: session.userID,
                            position: index + 1,
                            accessToken: session.accessToken
                        )
                    }

                    await MainActor.run {
                        submissionNotice = nil
                    }
                } catch {
                    await MainActor.run {
                        submissionNotice = "Your listing was sent for review, but one or more photos could not be uploaded. The text listing is still pending."
                    }
                }

                await MainActor.run {
                    submittedListingID = listingID
                    submittedListingTitle = submittedTitle
                    didSubmit = true
                    isSubmitting = false
                    submissionStatus = nil
                    draft = PendingListingDraft()
                    selectedPhotos = []
                    photoPickerItems = []
                }
                await loadMyListings()
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionStatus = nil
                    submissionError = "The listing could not be sent. Please check your connection and try again."
                }
            }
        }
    }

    @MainActor
    private func loadMyListings() async {
        guard let currentSession = userSessionStore.session else {
            myListings = []
            myListingsError = nil
            return
        }

        isLoadingMyListings = myListings.isEmpty
        myListingsError = nil

        do {
            await userSessionStore.refreshIfNeeded()
            let activeSession = userSessionStore.session ?? currentSession
            myListings = try await listingService.fetchUserListings(
                userID: activeSession.userID,
                accessToken: activeSession.accessToken
            )
            isLoadingMyListings = false
        } catch {
            isLoadingMyListings = false
            myListingsError = "Your listings could not be loaded. Pull down or try again soon."
        }
    }

    @MainActor
    private func loadPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isLoadingPhotos = true
        submissionError = nil

        for item in items {
            guard selectedPhotos.count < 5 else { break }

            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let photo = compressedListingPhoto(from: data) {
                    selectedPhotos.append(photo)
                }
            } catch {
                submissionError = "One photo could not be loaded. Please choose another image."
            }
        }

        photoPickerItems = []
        isLoadingPhotos = false
    }

    private func compressedListingPhoto(from data: Data) -> ListingPhotoUpload? {
        guard let image = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 1600
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

        guard let compressed = resized.jpegData(compressionQuality: 0.78) else { return nil }

        return ListingPhotoUpload(
            id: UUID(),
            data: compressed,
            width: Int(targetSize.width.rounded()),
            height: Int(targetSize.height.rounded()),
            mimeType: "image/jpeg"
        )
    }

    private func removePhoto(_ photo: ListingPhotoUpload) {
        selectedPhotos.removeAll { $0.id == photo.id }
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

struct MyListingsPanel: View {
    let listings: [LocalEvent]
    let isLoading: Bool
    let errorMessage: String?
    let onSelectListing: (LocalEvent) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Listings")
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Track posts you have sent for review.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(9)
                        .background(PCCTheme.leafGreen.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(PCCTheme.pohutukawaOrange)
                    Text("Loading your listings")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.pohutukawaRed)

                    Button("Try Again", action: onRefresh)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            } else if listings.isEmpty {
                Text("Your submitted listings will appear here after you send them.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
            } else {
                VStack(spacing: 10) {
                    ForEach(listings.prefix(4)) { listing in
                        MyListingCard(listing: listing) {
                            onSelectListing(listing)
                        }
                    }
                }
            }
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct MyListingCard: View {
    let listing: LocalEvent
    let onView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ListingRemoteImageView(
                image: listing.primaryImage,
                context: "my listing card event=\(String(listing.id.uuidString.prefix(8)))",
                contentMode: .fill
            ) {
                EventImagePlaceholderView()
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("\(listing.town.rawValue) · \(listing.venue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }

                Spacer()

                Text(listing.listingStatus.userLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(listing.listingStatus.userTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(listing.listingStatus.userTint.opacity(0.10), in: Capsule())
            }

            HStack(spacing: 9) {
                Label(listing.dateText, systemImage: "calendar")
                Label(listing.timeText, systemImage: "clock")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.58))
            .lineLimit(1)
            .minimumScaleFactor(0.74)

            Text(editNote)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.56))
                .lineSpacing(2)

            HStack(spacing: 9) {
                Button(action: onView) {
                    Label("View", systemImage: "eye.fill")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                Label("Edit soon", systemImage: "pencil")
                    .font(.caption.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))
                    .background(PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                Label("Remove soon", systemImage: "archivebox")
                    .font(.caption.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))
                    .background(PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
        }
        .padding(13)
        .background(PCCTheme.cream.opacity(0.60), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }

    private var editNote: String {
        switch listing.listingStatus {
        case .pendingReview:
            return "Pending review. Edits and removal will be connected with review safeguards next."
        case .published:
            return "Published. Future edits to price, date, venue, photos or promotion will return to review."
        case .rejected:
            return "Rejected listings can be revised after edit controls are connected."
        case .archived:
            return "Archived listing."
        }
    }
}

struct UserListingDetailSheet: View {
    let listing: LocalEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ListingRemoteImageView(
                        image: listing.primaryImage,
                        context: "my listing detail event=\(String(listing.id.uuidString.prefix(8)))",
                        contentMode: .fit
                    ) {
                        EventImagePlaceholderView()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 180)
                    .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(listing.listingStatus.userLabel)
                            .font(.caption.weight(.black))
                            .foregroundStyle(listing.listingStatus.userTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(listing.listingStatus.userTint.opacity(0.12), in: Capsule())

                        Text(listing.title)
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(listing.shortDescription)
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.68))
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .pccCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        UserListingInfoRow(icon: "calendar", title: "Date", value: listing.dateText)
                        UserListingInfoRow(icon: "clock", title: "Time", value: listing.timeText)
                        UserListingInfoRow(icon: "mappin.and.ellipse", title: "Location", value: "\(listing.venue), \(listing.town.rawValue)")
                        UserListingInfoRow(icon: "tag", title: "Price", value: listing.priceLabel)
                        UserListingInfoRow(icon: "person.2", title: "Audience", value: listing.audience)
                    }
                    .padding(18)
                    .pccCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Editing and removal controls are being connected next.", systemImage: "lock.shield")
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.ink)

                        Text("For launch safety, changes that affect price, promotion, event details or photos need to return to review before they appear publicly.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.64))
                            .lineSpacing(3)

                        HStack(spacing: 9) {
                            DisabledListingAction(title: "Edit", icon: "pencil")
                            DisabledListingAction(title: "Remove", icon: "archivebox")
                        }
                    }
                    .padding(18)
                    .pccCardStyle()
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, PCCKeyboardSpacing.standardBottomInset)
            }
            .background(PCCScreenBackground())
            .navigationTitle("Your Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                }
            }
        }
    }
}

struct UserListingInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.50))

                Text(value)
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DisabledListingAction: View {
    let title: String
    let icon: String

    var body: some View {
        Label("\(title) coming soon", systemImage: icon)
            .font(.caption.weight(.black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(PCCTheme.ink.opacity(0.48))
            .background(PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
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
    @Binding var photoPickerItems: [PhotosPickerItem]
    let selectedPhotos: [ListingPhotoUpload]
    let isLoadingPhotos: Bool
    let isSubmitting: Bool
    let submissionStatus: String?
    let submissionError: String?
    let onSubmit: () -> Void
    let onRemovePhoto: (ListingPhotoUpload) -> Void

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

            ListingPhotoPickerSection(
                photoPickerItems: $photoPickerItems,
                selectedPhotos: selectedPhotos,
                isLoadingPhotos: isLoadingPhotos,
                isDisabled: isSubmitting,
                onRemovePhoto: onRemovePhoto
            )

            ListingReviewNote()

            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }

            if let submissionStatus {
                Label(submissionStatus, systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
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

struct ListingPhotoPickerSection: View {
    @Binding var photoPickerItems: [PhotosPickerItem]
    let selectedPhotos: [ListingPhotoUpload]
    let isLoadingPhotos: Bool
    let isDisabled: Bool
    let onRemovePhoto: (ListingPhotoUpload) -> Void

    private var remainingSlots: Int {
        max(0, 5 - selectedPhotos.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photos")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))

                    Text("Optional. Add up to 5 images for review.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }

                Spacer()

                Text("\(selectedPhotos.count)/5")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            if !selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(selectedPhotos) { photo in
                            ListingPhotoThumbnail(photo: photo) {
                                onRemovePhoto(photo)
                            }
                            .disabled(isDisabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: remainingSlots,
                matching: .images
            ) {
                Label(photoButtonTitle, systemImage: isLoadingPhotos ? "hourglass" : "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(remainingSlots > 0 && !isDisabled ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.34))
            .background(PCCTheme.leafGreen.opacity(remainingSlots > 0 && !isDisabled ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .disabled(remainingSlots == 0 || isDisabled || isLoadingPhotos)
        }
        .padding(13)
        .background(PCCTheme.cream.opacity(0.52), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }

    private var photoButtonTitle: String {
        if isLoadingPhotos {
            return "Preparing Photos"
        }

        if remainingSlots == 0 {
            return "Maximum Photos Added"
        }

        return selectedPhotos.isEmpty ? "Add Photos" : "Add More Photos"
    }
}

struct ListingPhotoThumbnail: View {
    let photo: ListingPhotoUpload
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .fill(PCCTheme.ink.opacity(0.08))
                    .frame(width: 92, height: 92)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(PCCTheme.ink.opacity(0.42))
                    }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.black))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, PCCTheme.pohutukawaRed)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
        }
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
    let listingTitle: String?
    let notice: String?
    let onViewListing: () -> Void
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

            if let listingTitle, !listingTitle.isEmpty {
                Text(listingTitle)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
            }

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

            if let notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .padding(12)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            VStack(spacing: 10) {
                Button(action: onViewListing) {
                    Label("View Your Listing", systemImage: "rectangle.stack.fill")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.pohutukawaOrange, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

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

private extension ListingStatus {
    var userLabel: String {
        switch self {
        case .pendingReview: return "Pending"
        case .published: return "Published"
        case .rejected: return "Needs Work"
        case .archived: return "Archived"
        }
    }

    var userTint: Color {
        switch self {
        case .pendingReview: return PCCTheme.pohutukawaOrange
        case .published: return PCCTheme.leafGreen
        case .rejected: return PCCTheme.pohutukawaRed
        case .archived: return PCCTheme.ink.opacity(0.62)
        }
    }
}
