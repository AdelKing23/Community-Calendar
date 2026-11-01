import SwiftUI
import PhotosUI
import UIKit

struct EventDetailScreen: View {
    let event: LocalEvent
    private let analyticsService: EventAnalyticsRecording = SupabaseEventService()
    private let reportService: EventReportSubmitting = SupabaseEventService()
    private let listingService = SupabaseEventService()

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingReportSheet = false
    @State private var photoItem: PhotosPickerItem?
    @State private var localPreview: UIImage?
    @State private var photoMessage: String?
    @State private var showPhotoPicker = false
    @State private var showRemoveConfirm = false
    @State private var showEditSheet = false

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if event.isPoll {
                        PollDetailContent(event: event)
                        EngagementActionRow(event: event)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pccCardStyle()
                    } else {
                        EventDetailHero(event: event, localPreview: localPreview, canAddPhoto: canAddPhoto, onAddPhoto: { showPhotoPicker = true })
                        EventInfoPanel(event: event)
                        if event.businessProfileID != nil || event.submittedBy != nil {
                            EventOrganiserPanel(
                                event: event,
                                organiserID: event.submittedBy,
                                profileID: event.businessProfileID
                            )
                        }
                        EventAboutPanel(event: event)
                        PublicContactNotice(event: event)
                        EngagementActionRow(event: event)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pccCardStyle()
                        if canManageCalendarItem {
                            VStack(spacing: 10) {
                                Button("Edit") { showEditSheet = true }
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.white)
                                    .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                Button("Remove from calendar") { showRemoveConfirm = true }
                                    .font(.headline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(PCCTheme.pohutukawaRed)
                            }
                        }
                        ReportListingPanel {
                            isShowingReportSheet = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                .pccLocksHorizontalScrollWidth()
            }
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .navigationTitle(event.isPoll ? "Poll" : "Event")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: event.id) {
            print("[OrgCalendar] detail gate status=\(event.listingStatus) submitted=\(String(describing: event.submittedBy)) me=\(String(describing: userSessionStore.session?.userID)) manage=\(canManageCalendarItem)")
            await recordDetailView()
        }
        .sheet(isPresented: $isShowingReportSheet) {
            ReportListingSheet(event: event, service: reportService)
                .environmentObject(userSessionStore)
        }
        
        .alert("Remove this date?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                Task { await removeCalendarItem() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It leaves the org calendar. Support can still see the archive.")
        }
        .sheet(isPresented: $showEditSheet) {
            OrgCreateOnThisDaySheet(day: event.startDate, profileID: event.businessProfileID, editing: event)
                .environmentObject(userSessionStore)
        }

        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            Task { await handlePickedPhoto(item) }
        }
    }

    private var canAddPhoto: Bool {
        guard let uid = userSessionStore.session?.userID else { return false }
        return event.submittedBy == uid
    }

    private var canManageCalendarItem: Bool {
        event.listingStatus == .orgCalendar && canAddPhoto
    }


    @MainActor
    private func removeCalendarItem() async {
        guard let token = userSessionStore.session?.accessToken else { return }
        do {
            print("[OrgCalendar] remove start \(event.id)")
            try await listingService.archiveOwnListing(eventID: event.id, accessToken: token)
            print("[OrgCalendar] remove ok")
            dismiss()
        } catch {
            print("[OrgCalendar] remove failed \(error)")
        }
    }

    @MainActor
    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let session = userSessionStore.session else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.72) else { return }
        localPreview = image
        let upload = ListingPhotoUpload(
            id: UUID(),
            data: jpeg,
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded()),
            mimeType: "image/jpeg"
        )
        do {
            try await listingService.uploadListingImage(upload, eventID: event.id, userID: session.userID, position: 1, accessToken: session.accessToken)
            photoMessage = "Photo saved"
        } catch {
            photoMessage = error.pccUserFacingMessage
            print("[OrgCalendar] photo failed \(error)")
        }
    }

    private func recordDetailView() async {
        await userSessionStore.refreshIfNeeded()
        try? await analyticsService.recordEventAnalytics(
            eventID: event.id,
            eventType: "detail_view",
            source: "event_detail",
            locationScopeID: nil,
            accessToken: userSessionStore.session?.accessToken
        )
    }
}

struct PollDetailContent: View {
    let event: LocalEvent

    var body: some View {
        PollDetailHero(event: event)
        PollDetailInfoPanel(event: event)

        if let pollDetails = event.pollDetails {
            VStack(alignment: .leading, spacing: 14) {
                Label("Cast your answer", systemImage: "checklist")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)

                PollInlineResponseView(event: event, pollDetails: pollDetails)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .pccCardStyle()
        } else {
            PollUnavailablePanel()
        }

        if event.businessProfileID != nil || event.submittedBy != nil {
            EventOrganiserPanel(
                event: event,
                organiserID: event.submittedBy,
                profileID: event.businessProfileID
            )
        }

        PollAboutPanel(event: event)
    }
}

struct PollDetailHero: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ListingRemoteImageView(
                image: event.primaryImage,
                context: "detail poll=\(String(event.id.uuidString.prefix(8)))",
                contentMode: .fit
            ) {
                PollImagePlaceholderView()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 184)
            .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

            HStack(spacing: 10) {
                PollBadge()

                Text(event.category.shortLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                Spacer(minLength: 8)

                Text(event.displayLocationName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.leafGreen.opacity(0.08), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(event.shortDescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.70))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}

struct PollDetailInfoPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(spacing: 12) {
            EventInfoRow(icon: "calendar.badge.clock", title: "Closes", value: event.dateText)
            EventInfoRow(icon: "location", title: "Area", value: event.displayLocationName)
            EventInfoRow(icon: "person.crop.circle", title: "Asked by", value: event.organiserDisplayName)
        }
        .padding(18)
        .pccCardStyle()
    }
}

struct PollAboutPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why this poll is running")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(event.publicLongDescription.isEmpty ? "No extra context was added." : event.publicLongDescription)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct EventDetailHero: View {
    let event: LocalEvent
    var localPreview: UIImage? = nil
    var canAddPhoto: Bool = false
    var onAddPhoto: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let localPreview {
                        Image(uiImage: localPreview)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ListingRemoteImageView(
                            image: event.primaryImage,
                            context: "detail event=\(String(event.id.uuidString.prefix(8)))",
                            contentMode: .fit
                        ) {
                            EventImagePlaceholderView()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 190)
                .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .onTapGesture {
                    if canAddPhoto { onAddPhoto() }
                }

                if canAddPhoto, localPreview == nil, event.primaryImage == nil {
                    Text("Add photo")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PCCTheme.leafGreen, in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if event.isPoll {
                    PollBadge()
                } else {
                    Text(event.category.rawValue.uppercased())
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }

                Spacer(minLength: 8)

                Text(event.displayLocationName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.leafGreen.opacity(0.08), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(event.shortDescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.70))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if event.isPromoted {
                Text(event.promotionBadgeTitle)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PCCTheme.leafGreen, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}

struct EventPollPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Community poll", systemImage: "chart.bar.doc.horizontal")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            if let pollDetails = event.pollDetails {
                PollInlineResponseView(event: event, pollDetails: pollDetails)
            } else {
                Label("This poll is being prepared. Check back shortly to have your say.", systemImage: "clock.badge.checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.66))
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct EventOrganiserPanel: View {
    let event: LocalEvent
    let organiserID: UUID?
    let profileID: UUID?
    @State private var isShowingOrganiserCard = false
    @State private var profile: PublicBusinessProfileRecord?

    private var listedByName: String {
        let fromOrg = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromOrg.isEmpty { return fromOrg }
        return event.organiserDisplayName
    }

    var body: some View {
        Button {
            isShowingOrganiserCard = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(PCCTheme.leafGreen, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Listed by")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.46))

                    Text(listedByName)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(2)

                    Text("Tap to view this Organisation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
            }
            .padding(18)
            .pccCardStyle()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingOrganiserCard) {
            OrganiserIdentitySheet(event: event, organiserID: organiserID, profileID: profileID)
        }
        .task(id: profileID) {
            guard let profileID else { return }
            profile = try? await SupabaseEventService().fetchBusinessProfile(profileID: profileID)
        }
    }
}

struct OrganiserIdentitySheet: View {
    let event: LocalEvent
    let organiserID: UUID?
    let profileID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var profile: PublicBusinessProfileRecord?
    @State private var isLoadingProfile = false
    @State private var profileMessage: String?

    private var displayName: String {
        clean(profile?.displayName) ?? event.organiserDisplayName
    }

    private var aboutText: String {
        clean(profile?.bio)
        ?? "Listings and updates from \(displayName)."
    }

    private var contactEmail: String? {
        clean(profile?.publicContactEmail) ?? clean(event.contactEmail)
    }

    private var contactPhone: String? {
        clean(profile?.publicPhone) ?? clean(event.contactPhone)
    }

    private var contactAddress: String? {
        clean(profile?.publicAddress) ?? clean(profile?.publicLocationText)
    }

    private var website: String? {
        clean(profile?.publicWebsite)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 14) {
                                BusinessProfileAvatar(name: displayName, isBusiness: profile != nil)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(displayName)
                                        .font(.system(size: 31, weight: .black, design: .serif))
                                        .foregroundStyle(PCCTheme.ink)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(profile != nil ? "Verified organisation" : "Organiser profile")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                }
                            }

                            Text(aboutText)
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                                .lineSpacing(3)

                            HStack(spacing: 8) {
                                Label(profile != nil ? "Verified organisation" : "Local organiser", systemImage: profile != nil ? "checkmark.seal.fill" : "person.crop.circle")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PCCTheme.leafGreen, in: Capsule())

                                Label(event.displayLocationName, systemImage: "mappin.and.ellipse")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(PCCTheme.leafGreen)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .pccCardStyle()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Public contact")
                                .font(.title3.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            if let contactEmail {
                                OrganiserContactRow(icon: "envelope", title: "Email", value: contactEmail, actionURL: mailURL(for: contactEmail))
                            }

                            if let contactPhone {
                                OrganiserContactRow(icon: "phone", title: "Phone", value: contactPhone, actionURL: phoneURL(for: contactPhone))
                            }

                            if let contactAddress {
                                OrganiserContactRow(icon: "mappin.and.ellipse", title: "Address", value: contactAddress, actionURL: mapsURL(for: contactAddress))
                            }

                            if let website {
                                OrganiserContactRow(icon: "link", title: "Website", value: website, actionURL: websiteURL(for: website))
                            }

                            if contactEmail == nil, contactPhone == nil, contactAddress == nil, website == nil {
                                Text("No public contact details have been published for this organiser yet.")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                    .lineSpacing(3)
                            }

                            if isLoadingProfile {
                                Label("Checking for member profile...", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
                            } else if let profileMessage {
                                Label(profileMessage, systemImage: "info.circle")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
                            }
                        }
                        .padding(20)
                        .pccCardStyle()

                        NavigationLink {
                            OrganiserEventsScreen(
                                organiserID: organiserID,
                                organiserName: displayName,
                                profile: profile,
                                profileID: profile?.id ?? profileID
                            )
                        } label: {
                            Label(profile != nil ? "Open member page" : "See organiser listings", systemImage: "rectangle.stack")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                        Text("These details are supplied by the listing owner and reviewed before publication.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(PCCTheme.ink.opacity(0.56))
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Organiser")
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
            .task(id: profileID) {
                await loadBusinessProfile()
            }
        }
    }

    @MainActor
    private func loadBusinessProfile() async {
        profileMessage = nil
        guard let profileID else { return }

        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            profile = try await SupabaseEventService().fetchBusinessProfile(profileID: profileID)
            if profile == nil {
                profileMessage = "This organiser has not published a member page yet."
            }
        } catch {
            profileMessage = error.pccUserFacingMessage
        }
    }

    private func clean(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }
}

struct BusinessProfileAvatar: View {
    let name: String
    let isBusiness: Bool

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "CC" : text
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(PCCTheme.leafGreen)
            if isBusiness {
                Text(initials)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 68, height: 68)
        .overlay(
            Circle()
                .stroke(.white.opacity(0.85), lineWidth: 2)
        )
    }
}

struct OrganiserContactRow: View {
    let icon: String
    let title: String
    let value: String
    var actionURL: URL? = nil

    var body: some View {
        if let actionURL {
            Link(destination: actionURL) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(title.lowercased())")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.48))

                Text(value)
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if actionURL != nil {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct EventInfoPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(spacing: 12) {
            EventInfoRow(icon: "calendar", title: "Date", value: event.dateText)
            EventInfoRow(icon: "clock", title: "Time", value: event.timeText)
            OrganiserContactRow(
                icon: "mappin.and.ellipse",
                title: "Venue",
                value: "\(event.venue), \(event.displayLocationName)",
                actionURL: mapsURL(for: "\(event.venue), \(event.displayLocationName)")
            )
            EventInfoRow(icon: "dollarsign.circle", title: "Cost", value: event.priceLabel)
            EventInfoRow(icon: "person.2", title: "Good for", value: event.audience)
        }
        .padding(18)
        .pccCardStyle()
    }
}

private func mailURL(for email: String) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(string: "mailto:\(trimmed)")
}

private func phoneURL(for phone: String) -> URL? {
    let allowed = CharacterSet(charactersIn: "+0123456789")
    let cleaned = phone
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .unicodeScalars
        .filter { allowed.contains($0) }
        .map(String.init)
        .joined()
    guard !cleaned.isEmpty else { return nil }
    return URL(string: "tel:\(cleaned)")
}

private func websiteURL(for website: String) -> URL? {
    let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), url.scheme != nil {
        return url
    }
    return URL(string: "https://\(trimmed)")
}

private func mapsURL(for address: String) -> URL? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        return nil
    }
    return URL(string: "http://maps.apple.com/?q=\(encoded)")
}

struct OrganiserEventsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    let organiserID: UUID?
    let organiserName: String
    let profile: PublicBusinessProfileRecord?
    let profileID: UUID?
    private let service: PublishedEventFetching & MemberFollowingManaging & MemberNoticeManaging

    @State private var events: [LocalEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var isFollowActionBusy = false
    @State private var showAccountAccess = false
    @State private var showNotices = false
    @State private var showOrgCalendar = false
    @State private var actionMessage: String?
    @State private var ownedProfileID: UUID?
    @State private var unreadNoticeCount = 0
    private let accountLookup = SupabaseEventService()

    init(
        organiserID: UUID?,
        organiserName: String,
        profile: PublicBusinessProfileRecord? = nil,
        profileID: UUID? = nil,
        service: PublishedEventFetching & MemberFollowingManaging & MemberNoticeManaging = SupabaseEventService()
    ) {
        self.organiserID = organiserID
        self.organiserName = organiserName
        self.profile = profile
        self.profileID = profileID ?? profile?.id
        self.service = service
    }

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    OrganiserHeaderCard(
                        organiserName: organiserName,
                        profile: profile,
                        eventCount: events.count,
                        pollCount: events.filter { $0.isPoll }.count,
                        isLoading: isLoading,
                        isFollowing: isFollowing,
                        isFollowActionBusy: isFollowActionBusy,
                        onFollow: toggleFollow,
                        unreadNoticeCount: unreadNoticeCount,
                        onOpenNotices: {
                            showNotices = true
                        },
                        onOpenCalendar: {
                            showOrgCalendar = true
                        }
                    )

                    if let actionMessage {
                        Label(actionMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                            .padding(.horizontal, 14)
                    }

                    if isLoading {
                        OrganiserLoadingCard()
                    } else if let errorMessage {
                        OrganiserMessageCard(
                            icon: "wifi.exclamationmark",
                            title: "Could not load listings",
                            message: errorMessage
                        )
                    } else if events.isEmpty {
                        OrganiserMessageCard(
                            icon: "calendar.badge.clock",
                            title: "Nothing coming up yet",
                            message: "\(organiserName) has no published upcoming listings right now."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest from \(organiserName)")
                                    .pccScreenTitleStyle()

                                Text("Listings and polls are shown newest first.")
                                    .pccScreenSubtitleStyle()
                            }

                            ForEach(events) { event in
                                if event.isPoll {
                                    PollFeedCard(event: event)
                                } else {
                                    NavigationLink {
                                        EventDetailScreen(event: event)
                                    } label: {
                                        EventFeedCard(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .navigationTitle(profile == nil ? "Organiser" : "Organisation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFollowState()
            await loadEvents()
        }
        .task(id: userSessionStore.session?.userID) {
            await loadFollowState()
        }
        .refreshable {
            await loadEvents()
        }
        .sheet(isPresented: $showAccountAccess) {
            AccountAccessSheet()
                .environmentObject(userSessionStore)
        }
                .sheet(isPresented: $showOrgCalendar) {
            OrgCalendarSheet(
                organiserName: organiserName,
                events: events,
                canWrite: userSessionStore.isSignedIn,
                profileID: profileID
            )
        }
        .task(id: userSessionStore.session?.userID) {
            await loadOwnedProfile()
        }
        .onChange(of: showNotices) { _, open in
            if !open { Task { await loadUnreadNotices() } }
        }
        .sheet(isPresented: $showNotices) {

            if let profileID {
                MemberNoticesScreen(
                    organiserName: organiserName,
                    profileID: profileID,
                    ownerUserID: organiserID,
                    canCreateNotice: canCreateNotice,
                    service: service
                )
                .environmentObject(userSessionStore)
            } else {
                MemberNoticeUnavailableSheet(organiserName: organiserName)
            }
        }
    }

    private var dayGroups: [OrganiserDayGroup] {
        let calendar = Calendar.current
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        let groupedByDay = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }

        return groupedByDay.keys.sorted().map { day in
            let dayEvents = groupedByDay[day, default: []]
            let buckets = OrganiserTimeBucket.allCases.compactMap { bucket -> OrganiserEventBucket? in
                let bucketEvents = dayEvents.filter { bucket.contains($0.startDate) }
                guard !bucketEvents.isEmpty else { return nil }
                return OrganiserEventBucket(kind: bucket, events: bucketEvents)
            }

            return OrganiserDayGroup(date: day, buckets: buckets)
        }
    }

    private var followStorageKey: String {
        followStorageKey(for: userSessionStore.session?.userID)
    }

    private func followStorageKey(for userID: UUID?) -> String {
        let profileKey = profileID?.uuidString.lowercased() ?? organiserID?.uuidString.lowercased() ?? organiserName.lowercased()
        return "member-follow-\(userID?.uuidString.lowercased() ?? "signed-out")-\(profileKey)"
    }


    @MainActor
    private func loadUnreadNotices() async {
        guard let profileID, let token = userSessionStore.session?.accessToken else {
            unreadNoticeCount = 0
            return
        }
        do {
            async let loaded = accountLookup.fetchMemberNotices(profileID: profileID, accessToken: token)
            async let reads = accountLookup.fetchNoticeReads(accessToken: token)
            let notices = try await loaded
            let readIDs = Set(try await reads)
            unreadNoticeCount = notices.filter { !readIDs.contains($0.id) }.count
        } catch {
            print("[Notices] unread count failed \(error)")
        }
    }

    private func loadOwnedProfile() async {
        guard let session = userSessionStore.session else {
            ownedProfileID = nil
            return
        }
        do {
            let account = try await accountLookup.fetchBusinessAccount(userID: session.userID, accessToken: session.accessToken)
            ownedProfileID = account.profile?.id
            print("[Notices] ownedProfile=\(String(describing: ownedProfileID)) page=\(String(describing: profileID))")
            await loadUnreadNotices()
        } catch {
            print("[Notices] owned profile lookup failed \(error)")
        }
    }

    private var canCreateNotice: Bool {
        guard let profileID, userSessionStore.session != nil else { return false }
        if let ownedProfileID { return ownedProfileID == profileID }
        if let organiserID { return userSessionStore.session?.userID == organiserID }
        return false
    }

    @MainActor
    private func toggleFollow() {
        guard profileID != nil else { return }
        guard userSessionStore.isSignedIn else {
            showAccountAccess = true
            return
        }

        Task { await saveFollowState(!isFollowing) }
    }

    @MainActor
    private func loadFollowState() async {
        let requestContext = userSessionStore.captureAccountContext()
        guard let profileID, let session = userSessionStore.session else {
            isFollowing = false
            return
        }
        let cacheKey = followStorageKey(for: session.userID)

        do {
            let loaded = try await service.fetchMemberFollow(
                profileID: profileID,
                userID: session.userID,
                accessToken: session.accessToken
            )
            guard userSessionStore.isCurrent(requestContext) else { return }
            isFollowing = loaded
            UserDefaults.standard.set(loaded, forKey: cacheKey)
        } catch {
            guard userSessionStore.isCurrent(requestContext) else { return }
            isFollowing = UserDefaults.standard.bool(forKey: cacheKey)
        }
    }

    @MainActor
    private func saveFollowState(_ newValue: Bool) async {
        let requestContext = userSessionStore.captureAccountContext()
        guard let profileID, let session = userSessionStore.session else {
            showAccountAccess = true
            return
        }
        let cacheKey = followStorageKey(for: session.userID)
        guard !isFollowActionBusy else { return }

        isFollowActionBusy = true
        defer { isFollowActionBusy = false }

        do {
            try await service.setMemberFollow(
                profileID: profileID,
                userID: session.userID,
                isFollowing: newValue,
                accessToken: session.accessToken
            )
            guard userSessionStore.isCurrent(requestContext) else { return }
            isFollowing = newValue
            UserDefaults.standard.set(newValue, forKey: cacheKey)
            actionMessage = newValue
                ? "You Belong with \(organiserName). Notices can appear in your updates."
                : "Removed \(organiserName) from your Belonging."
        } catch {
            guard userSessionStore.isCurrent(requestContext) else { return }
            actionMessage = "Belonging could not be saved: \(error.pccUserFacingMessage)"
        }
    }

    @MainActor
    private func loadEvents() async {
        isLoading = true
        errorMessage = nil

        do {
            if let profileID {
                events = try await service.fetchPublishedEvents(businessProfileID: profileID)
            } else if let organiserID {
                events = try await service.fetchPublishedEvents(submittedBy: organiserID)
            } else {
                events = []
            }
            events = events
                .sorted { $0.createdAt > $1.createdAt }
            isLoading = false
        } catch {
            errorMessage = error.pccUserFacingMessage
            isLoading = false
        }
    }
}

struct OrganiserHeaderCard: View {
    let organiserName: String
    let profile: PublicBusinessProfileRecord?
    let eventCount: Int
    let pollCount: Int
    let isLoading: Bool
    let isFollowing: Bool
    let isFollowActionBusy: Bool
    let onFollow: () -> Void
    let unreadNoticeCount: Int
    let onOpenNotices: () -> Void
    let onOpenCalendar: () -> Void

    private var heroRequest: URLRequest? {
        MemberProfileImageDelivery.request(path: profile?.heroImagePath)
    }

    private var avatarRequest: URLRequest? {
        MemberProfileImageDelivery.request(path: profile?.avatarImagePath)
    }

    private var aboutText: String? {
        cleaned(profile?.bio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MemberHeroImage(
                request: heroRequest,
                name: organiserName,
                positionX: profile?.heroImagePositionX ?? 50,
                positionY: profile?.heroImagePositionY ?? 50
            )
                .frame(height: 210)

            VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MemberAvatarImage(
                    request: avatarRequest,
                    name: organiserName,
                    isVerified: profile != nil,
                    positionX: profile?.avatarImagePositionX ?? 50,
                    positionY: profile?.avatarImagePositionY ?? 50
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(organiserName)
                        .font(.system(size: 31, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(profile == nil ? "Organiser listings" : "Verified organisation")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.64))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onOpenNotices) {
                    Label(unreadNoticeCount > 0 ? "Notices \(unreadNoticeCount)" : "Notices", systemImage: "megaphone.fill")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.leafGreen)
                .background(PCCTheme.leafGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                Button(action: onFollow) {
                    Label(isFollowing ? "Belonging" : "Belong", systemImage: isFollowing ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(isFollowing ? PCCTheme.leafGreen : PCCTheme.pohutukawaOrange, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                .disabled(profile == nil || isFollowActionBusy)

                if let website = cleaned(profile?.publicWebsite), let url = URL(string: website) {
                    Link(destination: url) {
                        Image(systemName: "link")
                            .font(.headline.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                            .frame(width: 46, height: 46)
                            .background(PCCTheme.leafGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                }
            }

            if let aboutText {
                Text(aboutText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This member page collects the host profile, contact actions, listings and polls in one place.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Label(isLoading ? "Loading" : "\(eventCount) published", systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PCCTheme.pohutukawaOrange, in: Capsule())

                if pollCount > 0 {
                    Label("\(pollCount) poll\(pollCount == 1 ? "" : "s")", systemImage: "chart.bar.doc.horizontal")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                }

                if profile != nil {
                    Label("Org Calendar", systemImage: "calendar")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PCCTheme.pohutukawaOrange, in: Capsule())
                        .onTapGesture(perform: onOpenCalendar)
                } else {
                    Label("Tap for details", systemImage: "hand.tap")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                }
            }

            if let profile {
                VStack(alignment: .leading, spacing: 8) {
                    if let contactName = cleaned(profile.publicContactName) {
                        OrganiserContactRow(icon: "person", title: "Contact", value: contactName)
                    }
                    if let email = cleaned(profile.publicContactEmail) {
                        OrganiserContactRow(icon: "envelope", title: "Email", value: email, actionURL: mailURL(for: email))
                    }
                    if let phone = cleaned(profile.publicPhone) {
                        OrganiserContactRow(icon: "phone", title: "Phone", value: phone, actionURL: phoneURL(for: phone))
                    }
                    if let location = cleaned(profile.publicAddress) ?? cleaned(profile.publicLocationText) {
                        OrganiserContactRow(icon: "mappin.and.ellipse", title: "Location", value: location, actionURL: mapsURL(for: location))
                    }
                    if let website = cleaned(profile.publicWebsite) {
                        OrganiserContactRow(icon: "link", title: "Website", value: website, actionURL: websiteURL(for: website))
                    }
                }
                .padding(12)
                .background(PCCTheme.cream.opacity(0.62), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }

    private func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct MemberHeroImage: View {
    let request: URLRequest?
    let name: String
    var positionX = 50.0
    var positionY = 50.0

    var body: some View {
        MemberProfileRemoteImage(
            request: request,
            fallback: placeholder,
            isCircular: false,
            positionX: positionX,
            positionY: positionY
        )
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [PCCTheme.leafGreen.opacity(0.95), PCCTheme.pohutukawaOrange.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .bottomLeading) {
            Text(name)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.78))
                .padding(14)
        }
    }
}

struct MemberAvatarImage: View {
    let request: URLRequest?
    let name: String
    let isVerified: Bool
    var positionX = 50.0
    var positionY = 50.0

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "CC" : text
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                MemberProfileRemoteImage(
                    request: request,
                    fallback: fallback,
                    isCircular: true,
                    positionX: positionX,
                    positionY: positionY
                )
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))

            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(PCCTheme.leafGreen, in: Circle())
            }
        }
    }

    private var fallback: some View {
        Circle()
            .fill(PCCTheme.leafGreen)
            .overlay {
                Text(initials)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
            }
    }
}

struct MemberProfileRemoteImage<Fallback: View>: View {
    let request: URLRequest?
    let fallback: Fallback
    let isCircular: Bool
    let positionX: Double
    let positionY: Double
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(isCircular ? 1.18 : 1.24)
                        .offset(cropOffset(in: proxy.size))
                        .clipped()
                } else {
                    fallback
                    if isLoading {
                        ProgressView()
                            .tint(PCCTheme.pohutukawaOrange)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: request?.url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let request else {
            image = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let loaded = UIImage(data: data) else {
                image = nil
                return
            }
            image = loaded
        } catch {
            image = nil
        }
    }

    private func cropOffset(in size: CGSize) -> CGSize {
        MemberProfileImageCrop.offset(in: size, isCircular: isCircular, positionX: positionX, positionY: positionY)
    }
}

struct MemberNoticesScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    let organiserName: String
    let profileID: UUID
    let ownerUserID: UUID?
    let canCreateNotice: Bool
    let service: MemberNoticeManaging

    @State private var notices: [MemberNoticeRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedNotice: MemberNoticeRecord?
    @State private var showCreateNotice = false
    @State private var readIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Notices")
                                .font(.system(size: 36, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Latest from \(organiserName)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                        }
                        .padding(20)
                        .pccCardStyle()

                        if canCreateNotice {
                            Button {
                                showCreateNotice = true
                            } label: {
                                Label("Create Notice", systemImage: "square.and.pencil")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }

                        if !notices.isEmpty, userSessionStore.session != nil {
                        let unread = notices.filter { !readIDs.contains($0.id) }.count
                        if unread > 0 {
                            Button("Mark all as read") {
                                Task { await markAllRead() }
                            }
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                        }
                    }

                    if isLoading {
                            OrganiserLoadingCard()
                        } else if let errorMessage {
                            OrganiserMessageCard(
                                icon: "wifi.exclamationmark",
                                title: "Could not load Notices",
                                message: errorMessage
                            )
                        } else if notices.isEmpty {
                            OrganiserMessageCard(
                                icon: "megaphone",
                                title: "No Notices yet",
                                message: "\(organiserName) has not published a Notice or weekly letter yet."
                            )
                        } else {
                            ForEach(notices) { notice in
                                Button {
                                    selectedNotice = notice
                                    Task { await markRead(notice.id) }
                                } label: {
                                    MemberNoticeCard(notice: notice)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
            }
            .navigationTitle("Notices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.bold))
                }
            }
            .task {
                await loadNotices()
            }
            .refreshable {
                await loadNotices()
            }
            .sheet(item: $selectedNotice) { notice in
                MemberNoticeDetailScreen(notice: notice, organiserName: organiserName)
            }
            .sheet(isPresented: $showCreateNotice) {
                if let writerID = ownerUserID ?? userSessionStore.session?.userID {
                    MemberNoticeComposerScreen(
                        organiserName: organiserName,
                        profileID: profileID,
                        ownerUserID: writerID,
                        service: service
                    ) { notice in
                        notices.insert(notice, at: 0)
                    }
                    .environmentObject(userSessionStore)
                }
            }
        }
    }

    @MainActor
    private func loadNotices() async {
        isLoading = notices.isEmpty
        errorMessage = nil

        do {
            let token = canCreateNotice ? userSessionStore.session?.accessToken : nil
            notices = try await service.fetchMemberNotices(profileID: profileID, accessToken: token)
            if let sessionToken = userSessionStore.session?.accessToken {
                readIDs = Set(try await service.fetchNoticeReads(accessToken: sessionToken))
            }
            isLoading = false
        } catch {
            errorMessage = error.pccUserFacingMessage
            isLoading = false
        }
    }

    @MainActor
    private func markRead(_ noticeID: UUID) async {
        guard let token = userSessionStore.session?.accessToken else { return }
        readIDs.insert(noticeID)
        do {
            if let userID = userSessionStore.session?.userID {
                try await service.markNoticeRead(noticeID: noticeID, userID: userID, accessToken: token)
            }
        } catch {
            print("[Notices] markRead failed \(error)")
        }
    }

    @MainActor
    private func markAllRead() async {
        guard let token = userSessionStore.session?.accessToken else { return }
        let ids = notices.map { $0.id }
        readIDs.formUnion(ids)
        do {
            if let userID = userSessionStore.session?.userID {
                try await service.markAllNoticesRead(noticeIDs: ids, userID: userID, accessToken: token)
            }
        } catch {
            print("[Notices] markAll failed \(error)")
        }
    }
}

struct MemberNoticeCard: View {
    let notice: MemberNoticeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: noticeIcon)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .frame(width: 34, height: 34)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(PCCTheme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(dateText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.52))
                }

                Spacer(minLength: 0)
            }

            if let summary = cleaned(notice.summary) {
                Text(summary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.66))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if notice.status != "published" {
                Text(notice.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PCCTheme.pohutukawaOrange.opacity(0.10), in: Capsule())
            }
        }
        .padding(16)
        .pccCardStyle()
    }

    private var noticeIcon: String {
        notice.templateStyle == "weekly_letter" ? "newspaper.fill" : "megaphone.fill"
    }

    private var dateText: String {
        let date = notice.publishedAt ?? notice.createdAt
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    private func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct MemberNoticeDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    let notice: MemberNoticeRecord
    let organiserName: String

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(organiserName, systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.leafGreen)

                            Text(notice.title)
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text((notice.publishedAt ?? notice.createdAt).formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.56))
                        }
                        .padding(20)
                        .pccCardStyle()

                        if let summary = cleaned(notice.summary) {
                            Text(summary)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.76))
                                .lineSpacing(4)
                                .padding(18)
                                .pccCardStyle()
                        }

                        if let body = cleaned(notice.body) {
                            Text(body)
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.72))
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(18)
                                .pccCardStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                }
            }
            .navigationTitle("Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.bold))
                }
            }
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}

struct MemberNoticeComposerScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    let organiserName: String
    let profileID: UUID
    let ownerUserID: UUID
    let service: MemberNoticeManaging
    let onCreated: (MemberNoticeRecord) -> Void

    @State private var title = ""
    @State private var summary = ""
    @State private var noticeBody = ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("New Notice")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Write a Notice or weekly letter for people who visit \(organiserName).")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                        }
                        .padding(20)
                        .pccCardStyle()

                        BusinessTextField(title: "Title", text: $title, required: true, showValidation: message != nil)
                        BusinessMultilineField(title: "Summary", text: $summary, prompt: "A short intro for the Notice list.")
                        BusinessMultilineField(title: "Notice", text: $noticeBody, prompt: "Write the full Notice or weekly letter.")

                        if let message {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PCCTheme.pohutukawaRed)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await publish() }
                        } label: {
                            Label(isSaving ? "Publishing" : "Publish Notice", systemImage: isSaving ? "hourglass" : "paperplane.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                }
                .pccScrollableKeyboardDismiss()
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
            }
            .navigationTitle("Create Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.headline.weight(.bold))
                }
            }
        }
    }

    @MainActor
    private func publish() async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Add a title before publishing."
            return
        }
        guard let session = userSessionStore.session, session.userID == ownerUserID else {
            message = "Sign in as this member to publish a Notice."
            return
        }
        guard !isSaving else { return }

        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            let notice = try await service.createMemberNotice(
                profileID: profileID,
                ownerUserID: ownerUserID,
                title: title,
                summary: summary,
                body: noticeBody,
                accessToken: session.accessToken
            )
            onCreated(notice)
            dismiss()
        } catch {
            message = error.pccUserFacingMessage
        }
    }
}

struct MemberNoticeUnavailableSheet: View {
    let organiserName: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "megaphone")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(PCCTheme.leafGreen)

            Text("Notices unavailable")
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("\(organiserName) does not have a public member page connected to Notices yet.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.64))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

struct OrganiserDaySection: View {
    let group: OrganiserDayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            ForEach(group.buckets) { bucket in
                VStack(alignment: .leading, spacing: 10) {
                    Label(bucket.kind.title, systemImage: bucket.kind.icon)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)

                    ForEach(bucket.events) { event in
                        if event.isPoll {
                            PollFeedCard(event: event)
                        } else {
                            NavigationLink {
                                EventDetailScreen(event: event)
                            } label: {
                                EventFeedCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct OrganiserLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(PCCTheme.leafGreen)

            Text("Finding their upcoming listings...")
                .font(.body.weight(.bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))

            Spacer()
        }
        .padding(20)
        .pccCardStyle()
    }
}

struct OrganiserMessageCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(title)
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .pccCardStyle()
    }
}

struct OrganiserDayGroup: Identifiable {
    let date: Date
    let buckets: [OrganiserEventBucket]

    var id: Date { date }

    var title: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct OrganiserEventBucket: Identifiable {
    let kind: OrganiserTimeBucket
    let events: [LocalEvent]

    var id: OrganiserTimeBucket { kind }
}

enum OrganiserTimeBucket: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .later: return "Later"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "sunset"
        case .later: return "moon.stars"
        }
    }

    func contains(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)

        switch self {
        case .morning:
            return (5..<12).contains(hour)
        case .afternoon:
            return (12..<17).contains(hour)
        case .evening:
            return (17..<22).contains(hour)
        case .later:
            return hour < 5 || hour >= 22
        }
    }
}

struct EventInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.45))

                Text(value)
                    .font(.body.weight(.bold))
                    .foregroundStyle(PCCTheme.ink)
            }

            Spacer()
        }
    }
}

struct EventAboutPanel: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About this event")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(event.publicLongDescription)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct PublicContactNotice: View {
    let event: LocalEvent

    private var email: String? {
        let value = event.contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private var phone: String? {
        let value = event.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var body: some View {
        if email != nil || phone != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Public Contact")
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                if let email {
                    Text(email)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.72))
                }

                if let phone {
                    Text(phone)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .pccCardStyle()
        }
    }
}

struct ReportListingPanel: View {
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Something not right?")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("Report a listing if it looks unsafe, misleading, spammy or out of date. Reports go privately to Support.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                .lineSpacing(2)

            Button(action: onReport) {
                Label("Report this listing", systemImage: "flag.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PCCTheme.pohutukawaRed)
            .background(PCCTheme.pohutukawaRed.opacity(0.10), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .accessibilityHint("Opens a private report form for Support review")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .pccCardStyle()
    }
}

struct ReportListingSheet: View {
    let event: LocalEvent
    let service: EventReportSubmitting

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var category: EventReportCategory = .wrongOrOutdated
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var didSubmit = false
    @State private var showAccountAccess = false

    private var canSubmit: Bool {
        userSessionStore.isSignedIn && !isSubmitting && !didSubmit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("REPORT LISTING", systemImage: "flag.fill")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(PCCTheme.pohutukawaRed)

                            Text(event.title)
                                .font(.system(size: 30, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tell Support what needs checking. Your report is private and is not shown to the organiser or public users.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                                .lineSpacing(3)
                        }
                        .padding(20)
                        .pccCardStyle()

                        if !userSessionStore.isSignedIn {
                            Button {
                                showAccountAccess = true
                            } label: {
                                Label("Sign in to send a private report", systemImage: "person.crop.circle.badge.exclamationmark")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Reason", selection: $category) {
                                ForEach(EventReportCategory.allCases) { category in
                                    Text(category.title).tag(category)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(PCCTheme.leafGreen)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Optional details")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                                TextEditor(text: $details)
                                    .font(.body.weight(.medium))
                                    .frame(minHeight: 118)
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
                                title: didSubmit ? "Report sent" : "Report not sent",
                                message: message
                            )
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Label(isSubmitting ? "Sending report" : "Send report", systemImage: "paperplane.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(canSubmit ? PCCTheme.pohutukawaRed : PCCTheme.ink.opacity(0.28), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationTitle("Report")
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
            .sheet(isPresented: $showAccountAccess) {
                AccountAccessSheet()
                    .environmentObject(userSessionStore)
            }
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            await userSessionStore.refreshIfNeeded()
            guard let session = userSessionStore.session else {
                throw SupabaseServiceError.authFailed
            }

            _ = try await service.submitEventReport(
                eventID: event.id,
                category: category,
                details: details,
                accessToken: session.accessToken
            )
            didSubmit = true
            message = "Thanks. Support will review this listing."
            details = ""
        } catch {
            message = error.pccUserFacingMessage
        }
    }
}


struct OrgCalendarSheet: View {
    let organiserName: String
    let events: [LocalEvent]
    let canWrite: Bool
    let profileID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var visibleMonth = Date()
    @State private var selectedDay = Date()
    @State private var showCreateOnThisDay = false
    @State private var calendarEvents: [LocalEvent] = []
    private let calendarService = SupabaseEventService()

    private var calendar: Calendar { Calendar.current }

    private var allCalendarItems: [LocalEvent] {
        var seen = Set<UUID>()
        var merged: [LocalEvent] = []
        for item in calendarEvents + events {
            if seen.insert(item.id).inserted { merged.append(item) }
        }
        return merged
    }

    private var daysEvents: [LocalEvent] {
        allCalendarItems.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDay) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        OrgMonthGrid(month: $visibleMonth, selectedDay: $selectedDay, markedDays: Set(allCalendarItems.map { calendar.startOfDay(for: $0.startDate) }), onChooseDay: { day in
                            selectedDay = day
                            if canWrite { showCreateOnThisDay = true }
                        })

                        Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)

                        if daysEvents.isEmpty {
                            Text("Nothing on this day yet.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.92))
                        } else {
                            ForEach(daysEvents) { event in
                                NavigationLink {
                                    EventDetailScreen(event: event)
                                } label: {
                                    OrgCalendarNoteCard(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if canWrite {
                            Button {
                                showCreateOnThisDay = true
                            } label: {
                                Label("Create on this day", systemImage: "plus.circle.fill")
                                    .font(.headline.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        } else {
                            Text("This calendar is filled by \(organiserName). Belong to see private dates when they exist.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 92)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task(id: profileID) { await loadCalendar() }
            .fullScreenCover(isPresented: $showCreateOnThisDay) {
                OrgCreateOnThisDaySheet(day: selectedDay, profileID: profileID)
            }
            .onChange(of: showCreateOnThisDay) { _, open in
                if !open { Task { await loadCalendar() } }
            }
        }
    }

    @MainActor
    private func loadCalendar() async {
        guard let profileID else {
            print("[OrgCalendar] month load skipped — profileID nil")
            return
        }
        do {
            let notes = try await calendarService.fetchOrgCalendarListings(
                profileID: profileID,
                accessToken: userSessionStore.session?.accessToken
            )
            let published = (try? await calendarService.fetchPublishedEvents(businessProfileID: profileID)) ?? []
            var seen = Set<UUID>()
            var merged: [LocalEvent] = []
            for item in notes + published where seen.insert(item.id).inserted {
                merged.append(item)
            }
            calendarEvents = merged
            print("[OrgCalendar] month loaded \(calendarEvents.count) notes=\(notes.count) published=\(published.count) profile=\(profileID)")
        } catch {
            print("[OrgCalendar] month load failed \(error)")
        }
    }

}

private struct OrgCreateOnThisDaySheet: View {
    let day: Date
    let profileID: UUID?
    var editing: LocalEvent? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var words = ""
    @State private var venue = ""
    @State private var details = ""
    @State private var startTime = Date()
    @State private var isPublic = true
    @State private var existing: [LocalEvent] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var fieldFocused: Bool
    private let service = SupabaseEventService()

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Create on this day")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)
                            Spacer()
                            Button("Close") { dismiss() }
                                .font(.headline.weight(.bold))
                                .foregroundStyle(PCCTheme.leafGreen)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.title3.weight(.black))
                                .foregroundStyle(PCCTheme.ink)
                            Text("Listing")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                            TextField("Title", text: $words)
                                .textInputAutocapitalization(.sentences)
                                .padding(14)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                .foregroundStyle(PCCTheme.ink)
                            Text("Venue")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                            TextField("Beachlands Boat Club", text: $venue)
                                .textInputAutocapitalization(.words)
                                .padding(14)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                .foregroundStyle(PCCTheme.ink)
                            Text("Time")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(PCCTheme.leafGreen)
                            Text("Details")
                                .font(.caption.weight(.black))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                            TextField("Julie is bringing lunch", text: $details, axis: .vertical)
                                .lineLimit(2...4)
                                .textInputAutocapitalization(.sentences)
                                .submitLabel(.done)
                                .padding(14)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                .foregroundStyle(PCCTheme.ink)
                                .focused($fieldFocused)
                                .onSubmit { fieldFocused = false }
                            Toggle("Public listing", isOn: $isPublic)
                                .tint(PCCTheme.leafGreen)
                                .foregroundStyle(PCCTheme.ink)
                            Text("People who Belong to this organisation can see this date. It is not on the public board.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pccCardStyle()
                        Button { Task { await save() } } label: {
                            Label(isSaving ? "Saving" : "Save", systemImage: "checkmark.circle.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(canSave ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.28), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        .disabled(!canSave || isSaving)
                        if let saveError {
                            Text(saveError)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(PCCTheme.pohutukawaRed)
                        }
                        if !existing.isEmpty {
                            Text("On this day")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)
                            ForEach(existing) { item in
                                NavigationLink {
                                    EventDetailScreen(event: item)
                                } label: {
                                    OrgCalendarNoteCard(event: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
                }
                .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
                .pccScrollableKeyboardDismiss()
            }
            .navigationBarHidden(true)
            .pccKeyboardDoneToolbar {
                fieldFocused = false
                UIApplication.pccDismissKeyboard()
            }
            .task { await loadExisting() }
        }
    }

    private var canSave: Bool {
        words.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && profileID != nil
    }

    @MainActor
    private func loadExisting() async {
        guard let profileID else { return }
        do {
            let all = try await service.fetchOrgCalendarListings(profileID: profileID, accessToken: userSessionStore.session?.accessToken)
            let dayStart = Calendar.current.startOfDay(for: day)
            existing = all.filter { Calendar.current.startOfDay(for: $0.startDate) == dayStart }
        } catch {
            print("[OrgCalendar] load day failed \(error)")
        }
    }

    @MainActor
    private func save() async {
        guard let profileID, let token = userSessionStore.session?.accessToken else {
            saveError = "Sign in as the organisation owner to save."
            return
        }
        let title = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return }
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: startTime)
        let combinedDay = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: cal.startOfDay(for: day)) ?? day
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if let editing {
                try await service.updateOrgCalendarListing(
                    eventID: editing.id,
                    title: title,
                    venue: venue,
                    details: details,
                    day: combinedDay,
                    isPublic: isPublic,
                    accessToken: token
                )
            } else {
                _ = try await service.insertOrgCalendarListing(
                    profileID: profileID,
                    title: title,
                    venue: venue,
                    details: details,
                    day: combinedDay,
                    isPublic: isPublic,
                    accessToken: token
                )
            }
            words = ""
            venue = ""
            details = ""
            fieldFocused = false
            await loadExisting()
            if editing != nil { dismiss() }
        } catch {
            saveError = error.pccUserFacingMessage
            print("[OrgCalendar] save failed \(error)")
        }
    }
}

struct OrgMonthGrid: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let markedDays: Set<Date>
    var onChooseDay: (Date) -> Void = { _ in }
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline.weight(.black))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(PCCTheme.ink)

            Button("Today") {
                let now = Date()
                month = now
                selectedDay = now
            }
            .font(.caption.weight(.black))
            .foregroundStyle(PCCTheme.leafGreen)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(["S","M","T","W","T","F","S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.45))
                }
                ForEach(daysInMonth, id: \.self) { day in
                    let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                    let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                    let marked = markedDays.contains(calendar.startOfDay(for: day))
                    Button {
                        onChooseDay(day)
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.weight(selected ? .black : .bold))
                            Circle()
                                .fill(marked ? PCCTheme.pohutukawaOrange : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(inMonth ? PCCTheme.ink : PCCTheme.ink.opacity(0.28))
                        .background(selected ? PCCTheme.leafGreen.opacity(0.16) : Color.clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!inMonth)
                    .opacity(inMonth ? 1 : 0)
                }
            }
        }
        .padding(16)
        .pccCardStyle()
    }

    private func shiftMonth(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private var daysInMonth: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        var pad = firstWeekday - calendar.firstWeekday
        if pad < 0 { pad += 7 }
        var days: [Date] = []
        days.reserveCapacity(42)
        for offset in 0..<42 {
            if let day = calendar.date(byAdding: .day, value: offset - pad, to: interval.start) {
                days.append(day)
            }
        }
        return days
    }
}



struct OrgCalendarNoteCard: View {
    let event: LocalEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)
            if !event.venue.isEmpty {
                Text(event.venue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.78))
            }
            Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                 + " · "
                 + event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.bold))
                .foregroundStyle(PCCTheme.leafGreen)
            if !event.shortDescription.isEmpty, event.shortDescription != event.title {
                Text(event.shortDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pccCardStyle()
    }
}



struct MyCalendarSheet: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @Environment(\.dismiss) private var dismiss
    @State private var visibleMonth = Date()
    @State private var selectedDay = Date()
    @State private var calendarEvents: [LocalEvent] = []
    private let calendarService = SupabaseEventService()
    private var calendar: Calendar { Calendar.current }

    private var daysEvents: [LocalEvent] {
        calendarEvents.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDay) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        OrgMonthGrid(
                            month: $visibleMonth,
                            selectedDay: $selectedDay,
                            markedDays: Set(calendarEvents.map { calendar.startOfDay(for: $0.startDate) }),
                            onChooseDay: { selectedDay = $0 }
                        )
                        Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                        if daysEvents.isEmpty {
                            Text("Nothing on this day from organisations you belong to.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.92))
                        } else {
                            ForEach(daysEvents) { event in
                                NavigationLink {
                                    EventDetailScreen(event: event)
                                } label: {
                                    OrgCalendarNoteCard(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 92)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("My Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard let token = userSessionStore.session?.accessToken else { return }
        do {
            let notes = try await calendarService.fetchMyCalendarListings(accessToken: token)
            let goingIDs = Array(engagementStore.goingEventIDs)
            let going = goingIDs.isEmpty ? [] : (try? await calendarService.fetchEventsByIDs(goingIDs, accessToken: token)) ?? []
            var seen = Set<UUID>()
            var merged: [LocalEvent] = []
            for item in notes + going where seen.insert(item.id).inserted {
                merged.append(item)
            }
            calendarEvents = merged
            print("[MyCalendar] loaded \(notes.count) notes + \(going.count) going = \(merged.count)")
        } catch {
            print("[MyCalendar] load failed \(error)")
        }
    }
}
