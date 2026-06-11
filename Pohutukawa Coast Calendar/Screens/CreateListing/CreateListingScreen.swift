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
    @State private var submittedListingTier: ListingTier?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var selectedPhotos: [ListingPhotoUpload] = []
    @FocusState private var focusedField: Field?
    private let listingService: EventListingSubmitting & UserListingFetching & EventChangeRequesting = SupabaseEventService()
    let onNavigateHome: () -> Void
    let onNavigateWhatsOn: () -> Void
    let onNavigateSettings: () -> Void

    init(
        onNavigateHome: @escaping () -> Void = {},
        onNavigateWhatsOn: @escaping () -> Void = {},
        onNavigateSettings: @escaping () -> Void = {}
    ) {
        self.onNavigateHome = onNavigateHome
        self.onNavigateWhatsOn = onNavigateWhatsOn
        self.onNavigateSettings = onNavigateSettings
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
                            listingTier: submittedListingTier,
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
        submittedListingTier = nil
        selectedPhotos = []
        photoPickerItems = []
    }

    private func showMyListings() {
        didSubmit = false
        onNavigateSettings()
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
                let selectedTier = draft.listingTier
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
                    submittedListingTier = selectedTier
                    didSubmit = true
                    isSubmitting = false
                    submissionStatus = nil
                    draft = PendingListingDraft()
                    selectedPhotos = []
                    photoPickerItems = []
                }
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
    let changeRequests: [EventChangeRequest]
    let isLoading: Bool
    let errorMessage: String?
    let actionMessage: String?
    let onSelectListing: (LocalEvent) -> Void
    let onEditListing: (LocalEvent) -> Void
    let onRemoveListing: (LocalEvent) -> Void
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

            if let actionMessage {
                Label(actionMessage, systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
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
                        MyListingCard(
                            listing: listing,
                            pendingRequest: pendingRequest(for: listing),
                            latestRequest: latestRequest(for: listing),
                            onView: {
                                onSelectListing(listing)
                            },
                            onEdit: {
                                onEditListing(listing)
                            },
                            onRemove: {
                                onRemoveListing(listing)
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .pccCardStyle()
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
}

struct MyListingCard: View {
    let listing: LocalEvent
    let pendingRequest: EventChangeRequest?
    let latestRequest: EventChangeRequest?
    let onView: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

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

            ListingAnalyticsCompactView(event: listing)

            if let pendingRequest {
                Label("\(pendingRequest.supportTitle) pending support review", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Capsule())
            } else if latestRequest?.status == .rejected {
                Label("Action needed: tap to review Support feedback", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PCCTheme.pohutukawaRed.opacity(0.10), in: Capsule())
            } else if let latestRequest, latestRequest.status != .pending {
                ReviewedRequestSummary(request: latestRequest)
            }

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

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingRequest == nil ? PCCTheme.ink.opacity(0.72) : PCCTheme.ink.opacity(0.34))
                .background(PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .disabled(pendingRequest != nil)

                Button(action: onRemove) {
                    Label("Remove", systemImage: "archivebox")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingRequest == nil ? PCCTheme.pohutukawaRed : PCCTheme.ink.opacity(0.34))
                .background(PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .disabled(pendingRequest != nil)
            }
        }
        .padding(13)
        .background(PCCTheme.cream.opacity(0.60), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .onTapGesture(perform: onView)
    }

    private var editNote: String {
        switch listing.listingStatus {
        case .pendingReview:
            return "Pending review. Edits and removal are sent back through Support."
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
    let pendingRequest: EventChangeRequest?
    let latestRequest: EventChangeRequest?
    let requests: [EventChangeRequest]
    let onEdit: () -> Void
    let onRemove: () -> Void
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

                    ListingAnalyticsDetailCard(event: listing)

                    VStack(alignment: .leading, spacing: 10) {
                        Label(pendingRequest == nil ? "Changes go back through review." : "Request already waiting for review.", systemImage: "lock.shield")
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.ink)

                        Text(reviewCopy)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.64))
                            .lineSpacing(3)

                        HStack(spacing: 9) {
                            Button {
                                dismiss()
                                onEdit()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.caption.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(pendingRequest == nil ? .white : PCCTheme.ink.opacity(0.36))
                            .background(pendingRequest == nil ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            .disabled(pendingRequest != nil)

                            Button {
                                dismiss()
                                onRemove()
                            } label: {
                                Label("Remove", systemImage: "archivebox")
                                    .font(.caption.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(pendingRequest == nil ? .white : PCCTheme.ink.opacity(0.36))
                            .background(pendingRequest == nil ? PCCTheme.pohutukawaRed : PCCTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                            .disabled(pendingRequest != nil)
                        }
                    }
                    .padding(18)
                    .pccCardStyle()

                    if !requests.isEmpty {
                        ListingRequestHistory(requests: requests)
                    }
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

    private var reviewCopy: String {
        if let pendingRequest {
            return "\(pendingRequest.supportTitle) is pending. Support will review it before anything changes publicly."
        }

        return "For launch safety, edits and removal requests are reviewed before they affect the public listing."
    }
}

struct ListingAnalyticsCompactView: View {
    let event: LocalEvent

    private var analytics: ListingAnalyticsSnapshot {
        ListingAnalyticsSnapshot.softLaunchEstimate(for: event)
    }

    var body: some View {
        HStack(spacing: 8) {
            AnalyticsPill(value: "\(analytics.impressions)", label: "shown")
            AnalyticsPill(value: "\(analytics.detailViews)", label: "opened")
            AnalyticsPill(value: "\(analytics.engagementTaps)", label: "engaged")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Listing analytics. \(analytics.impressions) shown, \(analytics.detailViews) opened, \(analytics.engagementTaps) engaged.")
    }
}

struct AnalyticsPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ListingAnalyticsDetailCard: View {
    let event: LocalEvent

    private var analytics: ListingAnalyticsSnapshot {
        ListingAnalyticsSnapshot.softLaunchEstimate(for: event)
    }

    private var isInsightsTier: Bool {
        event.inferredListingTier.includesInsights
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isInsightsTier ? "Listing Insights" : "Basic Analytics")
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(isInsightsTier ? "Useful performance detail for deciding if a boost helped." : "A simple launch view of activity. Deeper reporting is included with Boost + Insights.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .lineSpacing(2)
                }
            }

            ListingAnalyticsCompactView(event: event)

            if isInsightsTier {
                AnalyticsBarGraph(analytics: analytics)

                Text("Use this to compare normal listings against boosted ones once real tracking is connected.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
            } else {
                Label("Boost + Insights will add a deeper graph and share/save breakdown.", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.footnote.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }

            Text("Soft-launch numbers are placeholders until server analytics are connected.")
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.42))
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct AnalyticsBarGraph: View {
    let analytics: ListingAnalyticsSnapshot

    private var rows: [(label: String, value: Int)] {
        [
            ("Shown", analytics.impressions),
            ("Opened", analytics.detailViews),
            ("Engaged", analytics.engagementTaps),
            ("Saved", analytics.saves),
            ("Shared", analytics.shares)
        ]
    }

    private var maxValue: Int {
        max(rows.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(rows, id: \.label) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                        .frame(width: 64, alignment: .leading)

                    GeometryReader { proxy in
                        let width = max(8, proxy.size.width * CGFloat(row.value) / CGFloat(maxValue))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(row.label == "Shown" ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
                            .frame(width: width)
                    }
                    .frame(height: 12)

                    Text("\(row.value)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ListingRequestHistory: View {
    let requests: [EventChangeRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Listing Activity")
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Support decisions and notes stay attached to this listing.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
            }

            VStack(spacing: 10) {
                ForEach(requests) { request in
                    UserRequestTimelineCard(request: request)
                }
            }
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct UserRequestTimelineCard: View {
    let request: EventChangeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.supportTitle.capitalized)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(request.createdAt.formatted(.dateTime.day().month().year().hour().minute()))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.48))
                }

                Spacer()

                Text(request.status.userStatusLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(request.status.userStatusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(request.status.userStatusTint.opacity(0.10), in: Capsule())
            }

            if let requesterNote = request.requesterNote, !requesterNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your note")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.50))

                    Text(requesterNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.66))
                }
            }

            if let reviewReason = request.reviewReason {
                VStack(alignment: .leading, spacing: 8) {
                    Label(reviewReason.label, systemImage: request.status == .rejected ? "exclamationmark.circle.fill" : "tag.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(request.status == .rejected ? PCCTheme.pohutukawaRed : PCCTheme.leafGreen)

                    Text(reviewReason.userNextStep(for: request.changeType, status: request.status))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .lineSpacing(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(request.status == .rejected ? PCCTheme.pohutukawaRed.opacity(0.07) : PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            if let supportNote = request.supportNote, !supportNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support note")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.50))

                    Text(supportNote)
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.70))
                        .lineSpacing(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PCCTheme.cream.opacity(0.68), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            if request.status == .pending {
                Label("Support has not reviewed this request yet.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
        }
        .padding(13)
        .background(PCCTheme.cream.opacity(0.54), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ReviewedRequestSummary: View {
    let request: EventChangeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(request.userSummary, systemImage: request.userSummaryIcon)
                .font(.caption.weight(.black))
                .foregroundStyle(request.userSummaryTint)

            if let supportNote = request.supportNote, !supportNote.isEmpty {
                Text(supportNote)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct ListingEditRequestSheet: View {
    let listing: LocalEvent
    let onSubmit: (ListingEditDraft, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ListingEditDraft
    @State private var requesterNote = ""
    @State private var isSubmitting = false

    init(listing: LocalEvent, onSubmit: @escaping (ListingEditDraft, String?) async -> Void) {
        self.listing = listing
        self.onSubmit = onSubmit
        _draft = State(initialValue: ListingEditDraft(event: listing))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Request an edit")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text("Your public listing will not change until Support reviews this request.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.66))
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .pccCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        PCCFormField(title: "Event Name", text: $draft.title, prompt: "Event name")
                        PCCFormField(title: "Venue", text: $draft.venue, prompt: "Venue")

                        ListingLocationPicker(town: $draft.town)

                        Picker("Category", selection: $draft.category) {
                            ForEach(EventCategory.allCases) { category in
                                Text(category.shortLabel).tag(category)
                            }
                        }

                        ListingTopicPreview(topics: ListingTopic.inferredTopics(
                            category: draft.category,
                            searchableText: [draft.title, draft.venue, draft.shortDescription, draft.priceLabel].joined(separator: " ")
                        ))

                        DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)

                        PCCFormField(title: "Cost", text: $draft.priceLabel, prompt: "Free, koha, $20")
                        PCCFormField(title: "Audience", text: $draft.audience, prompt: "Everyone")
                        PCCFormField(title: "Contact Name", text: $draft.contactName, prompt: "Organiser or venue")
                        PCCFormField(title: "Contact Email", text: $draft.contactEmail, prompt: "name@example.co.nz")
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        PCCFormField(title: "Contact Phone", text: $draft.contactPhone, prompt: "Optional phone")
                            .keyboardType(.phonePad)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Short Description")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))

                            TextEditor(text: $draft.shortDescription)
                                .frame(minHeight: 96)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extra details")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))

                            TextEditor(text: $draft.longDescription)
                                .frame(minHeight: 118)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note for Support")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))

                            TextEditor(text: $requesterNote)
                                .frame(minHeight: 82)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }

                        Label("Photo changes will be connected in a later pass.", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.60))
                    }
                    .padding(20)
                    .pccCardStyle()

                    Button {
                        submit()
                    } label: {
                        Label(isSubmitting ? "Sending Request" : "Send Edit Request", systemImage: isSubmitting ? "hourglass" : "paperplane.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(draft.canSubmit && !isSubmitting ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.28), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    .disabled(!draft.canSubmit || isSubmitting)
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .background(PCCScreenBackground())
            .navigationTitle("Edit Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task {
            await onSubmit(draft, requesterNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            await MainActor.run {
                isSubmitting = false
            }
        }
    }
}

struct ListingRemovalRequestSheet: View {
    let listing: LocalEvent
    let onSubmit: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var requesterNote = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Request removal?")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text(listing.title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)

                        Text("This sends a request to Support. Your listing may remain visible until the request is approved.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.66))
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .pccCardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note for Support")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))

                        TextEditor(text: $requesterNote)
                            .frame(minHeight: 112)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                    .padding(20)
                    .pccCardStyle()

                    Button {
                        submit()
                    } label: {
                        Label(isSubmitting ? "Sending Request" : "Send Removal Request", systemImage: isSubmitting ? "hourglass" : "archivebox.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(isSubmitting ? PCCTheme.ink.opacity(0.28) : PCCTheme.pohutukawaRed, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .background(PCCScreenBackground())
            .navigationTitle("Remove Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task {
            await onSubmit(requesterNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            await MainActor.run {
                isSubmitting = false
            }
        }
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

            ListingTierSelector(draft: $draft)

            PCCFormField(title: "Event Name", text: $draft.title, prompt: "Coastal concert, market, class")
                .focused($focusedField, equals: .title)
            PCCFormField(title: "Venue", text: $draft.venue, prompt: "Hall, beach, club, cafe")
                .focused($focusedField, equals: .venue)

            ListingLocationPicker(town: $draft.town)

            Picker("Category", selection: $draft.category) {
                ForEach(EventCategory.allCases) { category in
                    Text(category.shortLabel).tag(category)
                }
            }

            ListingTopicPreview(topics: draft.inferredTopics)

            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)

            if draft.listingTier == .communityFree {
                PCCFormField(title: "Cost", text: $draft.priceLabel, prompt: "Free, koha, $20")
                    .focused($focusedField, equals: .cost)
            } else {
                PaidTierCostSummary(tier: draft.listingTier)
            }

            if draft.listingTier == .communityFree && !draft.commercialSignals.isEmpty {
                CommercialSignalWarning(signals: draft.commercialSignals)
            }

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

struct ListingTierSelector: View {
    @Binding var draft: PendingListingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listing Type")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                Text("Choose the path that best matches this listing. Paid options will be connected after soft-launch testing.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineSpacing(2)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ListingTier.allCases) { tier in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            draft.listingTier = tier
                            draft.priceLabel = tier.priceLabel
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(tier.title)
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(draft.listingTier == tier ? .white : PCCTheme.ink)
                                    .lineLimit(2)

                                Spacer(minLength: 6)

                                Text(tier.priceText)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(draft.listingTier == tier ? .white.opacity(0.92) : PCCTheme.pohutukawaOrange)
                            }

                            Text(tier.shortDescription)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(draft.listingTier == tier ? .white.opacity(0.82) : PCCTheme.ink.opacity(0.56))
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .padding(12)
                        .background(
                            draft.listingTier == tier ? PCCTheme.leafGreen : PCCTheme.cream.opacity(0.64),
                            in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Label(draft.listingTier.reviewHint, systemImage: draft.listingTier.isPaidTier ? "creditcard.fill" : "checkmark.seal.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(draft.listingTier.isPaidTier ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
        }
        .padding(13)
        .background(PCCTheme.leafGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ListingLocationPicker: View {
    @Binding var town: CoastTown
    @State private var query = ""

    private var selectedScope: LocationScope {
        LocationScope.primaryScope(for: town)
    }

    private var matchingScopes: [LocationScope] {
        let scopes = LocationScope.listingInputScopes
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return scopes }
        return scopes.filter { $0.matchesSearch(trimmedQuery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                Text("Choose the closest place. The app can still show it in wider areas like \(CommunityArea.defaultAreaName), Franklin and Auckland.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineSpacing(2)
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))

                TextField("Search place", text: $query)
                    .font(.body.weight(.bold))
                    .textInputAutocapitalization(.words)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PCCTheme.ink.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(PCCTheme.cream.opacity(0.74), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(matchingScopes) { scope in
                        Button {
                            if let primaryTown = scope.primaryTown {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                                    town = primaryTown
                                    query = ""
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scope.name)
                                    .font(.subheadline.weight(.black))
                                    .lineLimit(1)

                                Text(scope.kind.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .opacity(0.78)
                            }
                            .foregroundStyle(scope.id == selectedScope.id ? .white : PCCTheme.leafGreen)
                            .frame(minWidth: 112, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(scope.id == selectedScope.id ? PCCTheme.pohutukawaOrange : .white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 18)
            }

            Text(selectedScope.ladder.map(\.name).joined(separator: "  →  "))
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(13)
        .background(PCCTheme.leafGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct PaidTierCostSummary: View {
    let tier: ListingTier

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "creditcard.fill")
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Selected price")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                Text("\(tier.priceText) · \(tier.title)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text("Payment is not charged yet. Support will review and request payment when paid options are connected.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineSpacing(2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ListingTopicPreview: View {
    let topics: [ListingTopic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topics")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))

            Text("These are based on the category and wording. They help people browse What’s On by interest.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                .lineSpacing(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topics.filter { $0 != .all }) { topic in
                        HStack(spacing: 6) {
                            Image(systemName: topic.icon)
                                .font(.caption.weight(.black))

                            Text(topic.shortLabel)
                                .font(.caption.weight(.black))
                        }
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.72), in: Capsule())
                    }
                }
                .padding(.trailing, 20)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCCTheme.leafGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct CommercialSignalWarning: View {
    let signals: [ListingCommercialSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("This may need a paid listing", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text("We spotted wording that can look commercial. If this promotes a business, choose Commercial or Boost so Support can approve it faster.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .lineSpacing(2)

            ForEach(signals.prefix(3)) { signal in
                Text("\(signal.label): \(signal.detail)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
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
    let listingTier: ListingTier?
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

            if let listingTier, listingTier.isPaidTier {
                Label("\(listingTier.title) selected. No payment has been charged in soft-launch mode; Support will review the listing and payment path.", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .padding(12)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

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
                    Label("Open My Listings", systemImage: "rectangle.stack.fill")
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

private extension EventChangeRequest {
    var userSummary: String {
        let reason = reviewReason?.label

        switch status {
        case .pending:
            return "\(supportTitle) pending review"
        case .applied:
            return reason.map { "Applied: \($0)" } ?? "Applied"
        case .approved:
            return reason.map { "Approved: \($0)" } ?? "Approved"
        case .rejected:
            return reason.map { "Rejected: \($0)" } ?? "Rejected"
        case .cancelled:
            return reason.map { "Cancelled: \($0)" } ?? "Cancelled"
        }
    }

    var userSummaryIcon: String {
        switch status {
        case .pending:
            return "clock.badge.exclamationmark"
        case .applied, .approved:
            return "checkmark.seal.fill"
        case .rejected:
            return "exclamationmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var userSummaryTint: Color {
        switch status {
        case .pending:
            return PCCTheme.pohutukawaOrange
        case .applied, .approved:
            return PCCTheme.leafGreen
        case .rejected, .cancelled:
            return PCCTheme.pohutukawaRed
        }
    }
}

private extension EventChangeRequestStatus {
    var userStatusLabel: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .rejected: return "Action Needed"
        case .cancelled: return "Cancelled"
        case .applied: return "Applied"
        }
    }

    var userStatusTint: Color {
        switch self {
        case .pending:
            return PCCTheme.pohutukawaOrange
        case .approved, .applied:
            return PCCTheme.leafGreen
        case .rejected, .cancelled:
            return PCCTheme.pohutukawaRed
        }
    }
}

private extension EventReviewReason {
    func userNextStep(for changeType: EventChangeType, status: EventChangeRequestStatus) -> String {
        if status == .applied || status == .approved {
            switch changeType {
            case .editRequest:
                return "Your edit has been reviewed and applied to the listing."
            case .removalRequest:
                return "Your removal request has been approved and the listing has been archived."
            }
        }

        if status == .pending {
            return "Support is reviewing this request. Nothing changes publicly until it is approved."
        }

        switch self {
        case .approvedApplied:
            return "Support approved this request."
        case .needsPayment:
            return "This listing needs a paid option before it can be approved. Update the listing or choose the right paid listing path when payments are connected."
        case .inappropriateWording:
            return "Update the wording so it is clear, local and suitable for public viewing, then send another edit request."
        case .inappropriateImage:
            return "Replace or remove the photo before sending another request. Photo edits will be connected in a later pass."
        case .wrongCategory:
            return "Choose the category that best matches the listing, then resubmit."
        case .wrongDateTime:
            return "Check the event date and time, then send an updated request."
        case .unclearLocation:
            return "Add a clearer venue or location so people can find the event."
        case .duplicateListing:
            return "This appears to duplicate another listing. Use the existing listing or change this one so it is clearly different."
        case .commercialSubmittedAsFree:
            return "This appears commercial. Adjust it to a community listing or use a paid listing option when payments are connected."
        case .promotionUpgradeRequired:
            return "This request needs a promotion or featured listing option before it can be applied."
        case .notEnoughInformation:
            return "Add the missing details people need, such as what is happening, where it is, and who it is for."
        case .other:
            return "Read the Support note below, then update the listing if needed."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
