import SwiftUI

struct SupportAdminScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore

    private let supportService: OwnerEventReviewing = SupabaseEventService()

    var body: some View {
        ZStack {
            PCCScreenBackground()

            if SupportAccessPolicy.isSupportAccount(email: userSessionStore.email) {
                SupportDashboard(
                    supportService: supportService
                ) {
                    userSessionStore.signOut()
                }
            } else {
                SupportAccessUnavailableScreen()
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportAccessUnavailableScreen: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review Queue")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Support tools are only available to authorised listing reviewers.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .lineSpacing(3)
                }
                .padding(20)
                .pccCardStyle()

                Label("If you are a normal user, review your own listings from the Create tab.", systemImage: "rectangle.stack")
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.64))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, PCCKeyboardSpacing.standardTopPadding)
            .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
        }
    }
}

struct SupportDashboard: View {
    struct ReviewAction: Identifiable {
        enum Kind {
            case approve
            case reject
        }

        let id = UUID()
        let request: EventChangeRequest
        let kind: Kind
    }

    let supportService: OwnerEventReviewing
    let onLogout: () -> Void

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?
    @State private var updatingEventID: UUID?
    @State private var changeRequests: [EventChangeRequest] = []
    @State private var updatingRequestID: UUID?
    @State private var selectedReviewAction: ReviewAction?

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

    private var sortedChangeRequests: [EventChangeRequest] {
        changeRequests.sorted {
            if $0.status != $1.status {
                return $0.status == .pending
            }

            return $0.createdAt > $1.createdAt
        }
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

                ChangeRequestsReviewPanel(
                    requests: sortedChangeRequests,
                    updatingRequestID: updatingRequestID,
                    onApprove: { request in
                        selectedReviewAction = ReviewAction(request: request, kind: .approve)
                    },
                    onReject: { request in
                        selectedReviewAction = ReviewAction(request: request, kind: .reject)
                    }
                )

                SupportEventListPanel(title: "Published Events", icon: "calendar.badge.checkmark", events: publishedEvents, defaultExpanded: false)
                SupportEventListPanel(title: "Rejected", icon: "xmark.seal", events: rejectedEvents, defaultExpanded: false)
                SupportEventListPanel(title: "Archived", icon: "archivebox", events: archivedEvents, defaultExpanded: false)

                Text("User edits and removal requests are reviewed here. Published listings stay unchanged until Support applies a request.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, PCCKeyboardSpacing.standardTopPadding)
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
        .sheet(item: $selectedReviewAction) { action in
            SupportReviewDecisionSheet(
                request: action.request,
                kind: action.kind
            ) { reason, note in
                switch action.kind {
                case .approve:
                    await approve(action.request, reason: reason, note: note)
                case .reject:
                    await reject(action.request, reason: reason, note: note)
                }
            }
        }
    }

    @MainActor
    private func loadOwnerEvents() async {
        isLoading = events.isEmpty
        loadError = nil

        do {
            await userSessionStore.refreshIfNeeded()
            guard let activeSession = userSessionStore.session,
                  SupportAccessPolicy.isSupportAccount(email: activeSession.email) else {
                throw SupabaseServiceError.authFailed
            }

            events = try await supportService.fetchOwnerEvents(accessToken: activeSession.accessToken)
            changeRequests = try await supportService.fetchSupportChangeRequests(accessToken: activeSession.accessToken)
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
            await userSessionStore.refreshIfNeeded()
            guard let activeSession = userSessionStore.session,
                  SupportAccessPolicy.isSupportAccount(email: activeSession.email) else {
                throw SupabaseServiceError.authFailed
            }

            try await supportService.updateEventStatus(id: event.id, status: status, accessToken: activeSession.accessToken)
            actionMessage = "\(event.title) moved to \(status.supportLabel)."
            updatingEventID = nil
            await loadOwnerEvents()
        } catch {
            updatingEventID = nil
            loadError = "Could not update this listing. If your session expired, log out and sign in again."
        }
    }

    @MainActor
    private func approve(_ request: EventChangeRequest, reason: EventReviewReason, note: String?) async {
        updatingRequestID = request.id
        actionMessage = nil
        selectedReviewAction = nil

        do {
            await userSessionStore.refreshIfNeeded()
            guard let activeSession = userSessionStore.session,
                  SupportAccessPolicy.isSupportAccount(email: activeSession.email) else {
                throw SupabaseServiceError.authFailed
            }

            try await supportService.supportApproveChangeRequest(
                request,
                reviewReason: reason,
                supportNote: note,
                accessToken: activeSession.accessToken
            )
            actionMessage = "\(request.supportTitle) applied."
            updatingRequestID = nil
            await loadOwnerEvents()
        } catch {
            updatingRequestID = nil
            loadError = "Could not apply this request. Check the request details and try again."
        }
    }

    @MainActor
    private func reject(_ request: EventChangeRequest, reason: EventReviewReason, note: String?) async {
        updatingRequestID = request.id
        actionMessage = nil
        selectedReviewAction = nil

        do {
            await userSessionStore.refreshIfNeeded()
            guard let activeSession = userSessionStore.session,
                  SupportAccessPolicy.isSupportAccount(email: activeSession.email) else {
                throw SupabaseServiceError.authFailed
            }

            try await supportService.supportRejectChangeRequest(
                id: request.id,
                reviewReason: reason,
                supportNote: note,
                accessToken: activeSession.accessToken
            )
            actionMessage = "\(request.supportTitle) rejected."
            updatingRequestID = nil
            await loadOwnerEvents()
        } catch {
            updatingRequestID = nil
            loadError = "Could not reject this request. If your session expired, log out and sign in again."
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

            if event.unverifiedUserListing {
                Label("Unverified user listing", systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Capsule())
            }

            ListingTierSupportSummary(event: event)

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

            if !event.images.isEmpty {
                SupportImageStrip(images: event.images)
            }

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

struct ListingTierSupportSummary: View {
    let event: LocalEvent

    private var tier: ListingTier {
        event.inferredListingTier
    }

    private var signals: [ListingCommercialSignal] {
        ListingCommercialSignalDetector.signals(for: event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(tier.title) path · \(tier.priceText)", systemImage: tier.isPaidTier ? "creditcard.fill" : "checkmark.seal.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(tier.isPaidTier ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)

            if !signals.isEmpty && tier == .communityFree {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Possible commercial free listing", systemImage: "flag.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaRed)

                    ForEach(signals.prefix(3)) { signal in
                        Text("\(signal.label): \(signal.detail)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    }
                }
                .padding(10)
                .background(PCCTheme.pohutukawaRed.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct SupportImageStrip: View {
    let images: [EventImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Submitted Photos")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.52))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images) { image in
                        SupportImageThumbnail(image: image)
                    }
                }
            }
        }
        .padding(12)
        .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct SupportImageThumbnail: View {
    let image: EventImage

    var body: some View {
        ListingRemoteImageView(
            image: image,
            context: "support image=\(String(image.id.uuidString.prefix(8)))",
            contentMode: .fill
        ) {
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .fill(PCCTheme.cream.opacity(0.68))
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.44))
                }
        }
        .frame(width: 112, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ChangeRequestsReviewPanel: View {
    let requests: [EventChangeRequest]
    let updatingRequestID: UUID?
    let onApprove: (EventChangeRequest) -> Void
    let onReject: (EventChangeRequest) -> Void

    var body: some View {
        SupportPanel(title: "Change Requests", icon: "square.and.pencil") {
            if requests.isEmpty {
                Text("No edit or removal requests are waiting for review.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
            } else {
                VStack(spacing: 12) {
                    ForEach(requests.prefix(10)) { request in
                        ChangeRequestReviewCard(
                            request: request,
                            isUpdating: updatingRequestID == request.id,
                            onApprove: {
                                onApprove(request)
                            },
                            onReject: {
                                onReject(request)
                            }
                        )
                    }
                }
            }
        }
    }
}

struct ChangeRequestReviewCard: View {
    let request: EventChangeRequest
    let isUpdating: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(request.supportTitle)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text(request.event?.title ?? "Linked listing")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }

                Spacer()

                Text(request.status.supportLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(request.status.supportTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(request.status.supportTint.opacity(0.10), in: Capsule())
            }

            if let event = request.event {
                VStack(alignment: .leading, spacing: 7) {
                    SupportDetailRow(icon: "calendar", title: "Current Date", value: event.dateText)
                    SupportDetailRow(icon: "mappin.and.ellipse", title: "Current Venue", value: "\(event.venue), \(event.town.rawValue)")
                    SupportDetailRow(icon: "tag", title: "Current Price", value: event.priceLabel)
                }
            }

            if let requesterNote = request.requesterNote, !requesterNote.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Requester Note")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.52))

                    Text(requesterNote)
                        .font(.body.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.70))
                }
                .padding(12)
                .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            if request.changeType == .editRequest {
                ProposedChangesSummary(changes: request.proposedChanges)
            } else {
                Label("Approving this request archives the listing. It is not permanently deleted.", systemImage: "archivebox.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PCCTheme.pohutukawaRed.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            if let reviewReason = request.reviewReason {
                SupportReviewOutcome(reason: reviewReason, note: request.supportNote)
            } else if let supportNote = request.supportNote, !supportNote.isEmpty {
                SupportReviewOutcome(reason: nil, note: supportNote)
            }

            if request.isPending {
                HStack(spacing: 9) {
                    SupportStatusButton(title: request.changeType == .removalRequest ? "Archive" : "Apply", icon: "checkmark.seal.fill", color: PCCTheme.leafGreen, isUpdating: isUpdating, action: onApprove)
                    SupportStatusButton(title: "Reject", icon: "xmark.seal.fill", color: PCCTheme.pohutukawaRed, isUpdating: isUpdating, action: onReject)
                }
            }
        }
        .padding(14)
        .background(PCCTheme.cream.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct SupportReviewDecisionSheet: View {
    let request: EventChangeRequest
    let kind: SupportDashboard.ReviewAction.Kind
    let onSubmit: (EventReviewReason, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: EventReviewReason
    @State private var supportNote = ""
    @State private var isSubmitting = false

    init(
        request: EventChangeRequest,
        kind: SupportDashboard.ReviewAction.Kind,
        onSubmit: @escaping (EventReviewReason, String?) async -> Void
    ) {
        self.request = request
        self.kind = kind
        self.onSubmit = onSubmit
        _selectedReason = State(initialValue: kind.defaultReason(for: request))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 32, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        Text(subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.66))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Main reason")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))

                        Picker("Main reason", selection: $selectedReason) {
                            ForEach(kind.reasons(for: request)) { reason in
                                Text(reason.label).tag(reason)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PCCTheme.leafGreen)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PCCTheme.cream.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Short note")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.ink.opacity(0.54))

                        TextEditor(text: $supportNote)
                            .font(.body.weight(.medium))
                            .foregroundStyle(PCCTheme.ink)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 112)
                            .padding(10)
                            .background(PCCTheme.cream.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                        Text("This is shown to the listing owner with the request result.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PCCTheme.ink.opacity(0.52))
                    }

                    Button {
                        Task {
                            isSubmitting = true
                            await onSubmit(selectedReason, supportNote.nilIfEmpty)
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        Label(buttonTitle, systemImage: isSubmitting ? "hourglass" : buttonIcon)
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(buttonColor, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccScrollableKeyboardDismiss()
            .pccDismissesKeyboardOnTap()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .approve:
            return request.changeType == .removalRequest ? "Archive Listing" : "Apply Edit"
        case .reject:
            return "Reject Request"
        }
    }

    private var subtitle: String {
        switch kind {
        case .approve:
            return request.changeType == .removalRequest
                ? "Choose why this listing should be removed from public view."
                : "Choose why this request is being approved and applied."
        case .reject:
            return "Choose one clear reason so the listing owner knows what to fix."
        }
    }

    private var buttonTitle: String {
        switch kind {
        case .approve:
            return request.changeType == .removalRequest ? "Archive Listing" : "Apply Edit"
        case .reject:
            return "Reject Request"
        }
    }

    private var buttonIcon: String {
        switch kind {
        case .approve:
            return request.changeType == .removalRequest ? "archivebox.fill" : "checkmark.seal.fill"
        case .reject:
            return "xmark.seal.fill"
        }
    }

    private var buttonColor: Color {
        switch kind {
        case .approve:
            return request.changeType == .removalRequest ? PCCTheme.ink.opacity(0.76) : PCCTheme.leafGreen
        case .reject:
            return PCCTheme.pohutukawaRed
        }
    }
}

struct SupportReviewOutcome: View {
    let reason: EventReviewReason?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let reason {
                Label(reason.label, systemImage: "tag.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct ProposedChangesSummary: View {
    let changes: [String: EventChangeValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed Changes")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.52))

            ForEach(summaryRows, id: \.key) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.label)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.50))
                        .frame(width: 92, alignment: .leading)

                    Text(row.value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }

    private var summaryRows: [(key: String, label: String, value: String)] {
        let orderedKeys = [
            "title",
            "category",
            "town",
            "venue",
            "start_at",
            "price_label",
            "audience",
            "short_description",
            "contact_name",
            "contact_email",
            "contact_phone"
        ]

        return orderedKeys.compactMap { key in
            guard let value = changes[key] else { return nil }
            return (key, key.changeRequestLabel, value.displayText)
        }
    }
}

struct SupportEventListPanel: View {
    let title: String
    let icon: String
    let events: [LocalEvent]
    var defaultExpanded = true

    var body: some View {
        SupportPanel(title: title, icon: icon, defaultExpanded: defaultExpanded) {
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

                                if !event.images.isEmpty {
                                    SupportImageStrip(images: event.images)
                                }
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
    let content: Content
    @State private var isExpanded: Bool

    init(title: String, icon: String, defaultExpanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label(title, systemImage: icon)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.42))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
            }
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

private extension EventChangeRequestStatus {
    var supportLabel: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .cancelled: return "Cancelled"
        case .applied: return "Applied"
        }
    }

    var supportTint: Color {
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

private extension SupportDashboard.ReviewAction.Kind {
    func defaultReason(for request: EventChangeRequest) -> EventReviewReason {
        switch self {
        case .approve:
            return .approvedApplied
        case .reject:
            return request.changeType == .removalRequest ? .other : .notEnoughInformation
        }
    }

    func reasons(for request: EventChangeRequest) -> [EventReviewReason] {
        switch self {
        case .approve:
            return [.approvedApplied, .other]
        case .reject:
            return [
                .needsPayment,
                .commercialSubmittedAsFree,
                .promotionUpgradeRequired,
                .notEnoughInformation,
                .unclearLocation,
                .wrongDateTime,
                .wrongCategory,
                .inappropriateWording,
                .inappropriateImage,
                .duplicateListing,
                .other
            ]
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var changeRequestLabel: String {
        switch self {
        case "title": return "Title"
        case "category": return "Category"
        case "town": return "Town"
        case "venue": return "Venue"
        case "start_at": return "Starts"
        case "end_at": return "Ends"
        case "price_label": return "Price"
        case "is_free": return "Free"
        case "audience": return "Audience"
        case "short_description": return "Summary"
        case "long_description": return "Details"
        case "contact_name": return "Contact"
        case "contact_email": return "Email"
        case "contact_phone": return "Phone"
        default: return replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
