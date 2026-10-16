import Foundation

enum SupabaseServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case authFailed
    case requestFailed(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .authFailed:
            return "Sign in again to continue."
        case .requestFailed(let statusCode, let message):
            let detail = Self.userFacingDetail(from: message, statusCode: statusCode)
            if let detail, !detail.isEmpty {
                return detail
            }
            return Self.userFacingHTTPMessage(statusCode: statusCode)
        }
    }

    private static func userFacingDetail(from message: String?, statusCode: Int? = nil) -> String? {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        if let data = message.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let code = object["code"] as? String,
               let translated = Self.translatedPostgRESTMessage(code: code, object: object) {
                return translated
            }

            let joinedMessage = [
                object["message"] as? String,
                object["error_description"] as? String,
                object["error"] as? String,
                object["hint"] as? String,
                object["details"] as? String
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

            if let translated = Self.translatedRawMessage(joinedMessage, statusCode: statusCode) {
                return translated
            }

            if let error = object["error"] as? String, !error.isEmpty {
                return Self.translatedRawMessage(error, statusCode: statusCode) ?? Self.userFacingHTTPMessage(statusCode: statusCode)
            }

            if let message = object["message"] as? String, !message.isEmpty {
                return Self.translatedRawMessage(message, statusCode: statusCode) ?? Self.userFacingHTTPMessage(statusCode: statusCode)
            }
        }

        return Self.translatedRawMessage(message, statusCode: statusCode) ?? Self.userFacingHTTPMessage(statusCode: statusCode)
    }

    private static func translatedPostgRESTMessage(code: String, object: [String: Any]) -> String? {
        let message = [
            object["message"] as? String,
            object["details"] as? String,
            object["hint"] as? String
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        switch code {
        case "42501":
            if message.contains("row-level security") && message.contains("events") {
                return "We couldn’t confirm your publishing access. Refresh your member status and try again. Your listing is still here."
            }
            if message.contains("row-level security") && message.contains("business_profiles") {
                return "This member profile could not be saved with this account. Sign in again, verify your email, then check the required member details. If it still fails, Support needs to review the membership state."
            }
            if message.contains("member_notices") || message.contains("notices") {
                return "This Notice can’t be published yet. Publishing Notices needs an approved membership and active subscription. You can save it as a draft or ask Support to check your member status."
            }
            if message.contains("storage") || message.contains("object") || message.contains("bucket") {
                return "This image could not be uploaded with this account. Sign in again, check membership access, then try a smaller JPG or PNG."
            }
            if message.contains("row-level security") {
                return "This action is not available for this account yet. Sign in again and check the account, membership, and permission requirements. If you believe you should have access, Support should review it."
            }
            return "You do not have permission to complete this action yet. Check your sign-in, email verification, membership approval, and subscription state."
        case "23502":
            return "A required field is missing. Please check the highlighted fields and try again."
        case "23503":
            return "This item is linked to something the app can’t find anymore. Refresh the screen and try again."
        case "23505":
            return "This already exists. Check whether it was saved earlier, then refresh and try again."
        case "23514":
            return "One of the fields has a value the app cannot accept. Check dates, category, price, contact details and membership options."
        case "22001":
            return "One of the fields is too long. Shorten the title, summary, contact details or Notice text and try again."
        case "22003":
            return "One of the numbers is outside the accepted range. Check prices, limits and counts."
        case "22P02", "22007", "22008", "22023":
            return "One of the fields is not in the right format. Check dates, times, email, website and phone details."
        case "23P01":
            return "These dates or promotion times overlap something already saved. Adjust the timing and try again."
        case "40001", "57014":
            return "The server was busy and could not finish that change. Wait a moment, then try again."
        case "53300", "08000", "08003", "08006":
            return "The service is temporarily busy. Please try again shortly."
        case "PGRST100", "PGRST102":
            return "One of the filters or fields was not accepted. Refresh the app and try again. If it keeps happening, Support should check it."
        case "PGRST103":
            return "Too much information was requested at once. Narrow the view or refresh and try again."
        case "PGRST106", "PGRST108", "PGRST118", "PGRST200", "PGRST201", "PGRST202", "42P01", "42703", "42883":
            return "The app and database are out of step. Support should check this."
        case "PGRST116":
            return "That item could not be found. It may have been changed, archived or removed. Refresh and try again."
        case "PGRST301", "PGRST302":
            return "Your sign-in session has expired. Please sign in again."
        default:
            return nil
        }
    }

    private static func translatedRawMessage(_ message: String, statusCode: Int?) -> String? {
        let lowercased = message.lowercased()

        if lowercased.contains("invalid login credentials") || lowercased.contains("invalid_grant") {
            return "Sign in failed. Check your email and password, then try again."
        }
        if lowercased.contains("email not confirmed") || lowercased.contains("email_not_confirmed") {
            return "Check your email to confirm your account, then sign in again."
        }
        if lowercased.contains("user already registered") || lowercased.contains("already registered") {
            return "That email already has an account. Sign in instead, or use Forgot password."
        }
        if lowercased.contains("password") && (lowercased.contains("weak") || lowercased.contains("least") || lowercased.contains("characters")) {
            return "Create a stronger password. Use at least 6 characters, and avoid something too easy to guess."
        }
        if lowercased.contains("invalid email") || lowercased.contains("email address is invalid") {
            return "Use a real email address, then try again."
        }
        if lowercased.contains("jwt") || lowercased.contains("token") || lowercased.contains("expired") {
            return "Your sign-in session has expired. Please sign in again."
        }
        if lowercased.contains("row-level security") || lowercased.contains("permission denied") || lowercased.contains("not authorized") {
            return "This account does not have access to complete that action yet. Check sign-in, email verification, membership approval and subscription state. If those are correct, Support should review it."
        }
        if lowercased.contains("duplicate") || lowercased.contains("already exists") {
            return "This already exists. Check whether it was saved earlier, then refresh and try again."
        }
        if lowercased.contains("violates not-null") || lowercased.contains("null value") || lowercased.contains("required") {
            return "A required field is missing. Check the form and try again."
        }
        if lowercased.contains("violates check constraint") || lowercased.contains("invalid input") {
            return "One field has a value the app cannot accept. Check dates, category, price, contact details and membership options."
        }
        if lowercased.contains("too large") || lowercased.contains("payload") || lowercased.contains("file size") {
            return "That file is too large. Try a smaller image."
        }
        if lowercased.contains("mime") || lowercased.contains("unsupported") || lowercased.contains("content type") {
            return "That file type is not supported. Use a JPG, PNG or HEIC image."
        }
        if lowercased.contains("network") || lowercased.contains("offline") || lowercased.contains("timed out") {
            return "The connection dropped. Check your internet and try again."
        }

        if let statusCode {
            return userFacingHTTPMessage(statusCode: statusCode)
        }

        return nil
    }

    private static func userFacingHTTPMessage(statusCode: Int?) -> String {
        guard let statusCode else {
            return "Something went wrong. Try again shortly, and contact Support if it keeps happening."
        }

        switch statusCode {
        case 400, 422:
            return "Something in the form needs fixing. Check the required fields, dates, contact details and image sizes."
        case 401:
            return "Your sign-in session has expired. Please sign in again."
        case 403:
            return "This account does not have access to do that yet. Check email verification, membership approval and subscription state."
        case 404:
            return "That item could not be found. It may have been changed, archived or removed."
        case 409:
            return "This looks like a duplicate or conflict. Refresh the screen and try again."
        case 413:
            return "That file is too large. Try a smaller image."
        case 415:
            return "That file type is not supported. Use a JPG, PNG or HEIC image."
        case 429:
            return "Too many tries in a short time. Wait a moment, then try again."
        case 500...599:
            return "The service hit a problem. Please try again shortly. If it keeps happening, Support should check it."
        default:
            return "Something went wrong. Try again shortly, and contact Support if it keeps happening."
        }
    }
}

extension Error {
    var pccUserFacingMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return localizedDescription
    }
}

protocol EventListingSubmitting {
    func submitPendingListing(_ draft: PendingListingDraft, businessProfileID: UUID, accessToken: String) async throws -> UUID
    func uploadListingImage(_ image: ListingPhotoUpload, eventID: UUID, userID: UUID, position: Int, accessToken: String) async throws
}

protocol UserListingFetching {
    func fetchUserListings(userID: UUID, accessToken: String) async throws -> [LocalEvent]
}

protocol BusinessAccountManaging {
    func fetchBusinessAccount(userID: UUID, accessToken: String) async throws -> BusinessAccountState
    func upsertBusinessProfile(_ draft: BusinessProfileDraft, ownerUserID: UUID, accessToken: String) async throws -> BusinessProfileRecord
    func uploadMemberProfileImage(data: Data, mimeType: String, kind: String, userID: UUID, accessToken: String) async throws -> String
    func deleteMemberProfileImage(path: String, accessToken: String) async throws
    func createFoundingSponsorRequest(profileID: UUID, package: FoundingSponsorPackage, notes: String?, ownerUserID: UUID, accessToken: String) async throws -> FoundingSponsorRequestRecord
}

protocol BusinessProfileFetching {
    func fetchBusinessProfile(profileID: UUID) async throws -> PublicBusinessProfileRecord?
    func fetchApprovedBusinessProfiles() async throws -> [PublicBusinessProfileRecord]
}

protocol MemberPublicProfileManaging {
    func fetchOwnPublicProfileDraft(profileID: UUID, accessToken: String) async throws -> PublicBusinessProfileRecord?
    func saveOwnPublicProfileDraft(profileID: UUID, draft: PublicMemberProfileDraft, accessToken: String) async throws -> PublicBusinessProfileRecord
    func confirmOwnPublicContact(profileID: UUID, revision: UUID, accessToken: String) async throws -> PublicBusinessProfileRecord
    func memberProfileImageRequest(path: String?, accessToken: String?) -> URLRequest?
}

enum MemberProfileImageDelivery {
    static func request(path: String?, accessToken: String? = nil) -> URLRequest? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              var url = SupabaseConfiguration.storageURL?
                .appendingPathComponent("object")
                .appendingPathComponent("authenticated")
                .appendingPathComponent("member-images") else {
            return nil
        }

        for pathPart in path.split(separator: "/") {
            url.appendPathComponent(String(pathPart))
        }

        var request = URLRequest(url: url)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

protocol MemberFollowingManaging {
    func fetchMemberFollow(profileID: UUID, userID: UUID, accessToken: String) async throws -> Bool
    func setMemberFollow(profileID: UUID, userID: UUID, isFollowing: Bool, accessToken: String) async throws
}

protocol MemberNoticeManaging {
    func fetchMemberNotices(profileID: UUID, accessToken: String?) async throws -> [MemberNoticeRecord]
    func createMemberNotice(profileID: UUID, ownerUserID: UUID, title: String, summary: String, body: String, accessToken: String) async throws -> MemberNoticeRecord
    func fetchNoticeReads(accessToken: String) async throws -> [UUID]
    func markNoticeRead(noticeID: UUID, userID: UUID, accessToken: String) async throws
    func markAllNoticesRead(noticeIDs: [UUID], userID: UUID, accessToken: String) async throws
}

protocol EventChangeRequesting {
    func createEditRequest(event: LocalEvent, draft: ListingEditDraft, requesterID: UUID, requesterNote: String?, accessToken: String) async throws
    func createRemovalRequest(event: LocalEvent, requesterID: UUID, requesterNote: String?, accessToken: String) async throws
    func archiveOwnListing(eventID: UUID, accessToken: String) async throws
    func fetchMyChangeRequests(userID: UUID, accessToken: String) async throws -> [EventChangeRequest]
}

protocol PublishedEventFetching {
    func fetchPublishedEvents() async throws -> [LocalEvent]
    func fetchPublishedEvents(from rangeStart: Date, to rangeEnd: Date) async throws -> [LocalEvent]
    func fetchPublishedEvents(locationScopeID: String) async throws -> [LocalEvent]
    func fetchPublishedEvents(businessProfileID profileID: UUID) async throws -> [LocalEvent]
    func fetchPublishedEvents(submittedBy userID: UUID) async throws -> [LocalEvent]
}

protocol LocationScopeFetching {
    func fetchLocationCatalog() async throws -> LocationCatalog
}

protocol NearestLocationScopeResolving {
    func nearestLocationScopes(latitude: Double, longitude: Double, maxResults: Int) async throws -> [NearestLocationScopeMatch]
}

protocol PollResponding {
    func submitPollResponse(eventID: UUID, userID: UUID, selectedOption: String?, customAnswer: String?, accessToken: String) async throws
    func fetchPollResponseCounts(eventID: UUID) async throws -> PollResults
    func fetchOwnerPollResponseCounts(eventID: UUID, accessToken: String) async throws -> PollResults
    func fetchMyPollResponse(eventID: UUID, userID: UUID, accessToken: String) async throws -> PollUserResponse?
    func withdrawPollResponse(eventID: UUID, accessToken: String) async throws
    func fetchPollCustomResponses(eventID: UUID, accessToken: String) async throws -> [PollCustomResponse]
}

protocol ListingAnalyticsFetching {
    func fetchListingAnalytics(eventID: UUID, accessToken: String) async throws -> ListingAnalyticsSnapshot
}

protocol EventAnalyticsRecording {
    func recordEventAnalytics(eventID: UUID, eventType: String, source: String?, locationScopeID: String?, accessToken: String?) async throws
}

protocol SupportRequestSubmitting {
    func submitSupportRequest(topic: String, message: String, listingReference: String?, accessToken: String) async throws -> UUID
    func fetchMySupportRequests(userID: UUID, accessToken: String) async throws -> [SupportRequestRecord]
}

protocol EventReportSubmitting {
    func submitEventReport(eventID: UUID, category: EventReportCategory, details: String?, accessToken: String) async throws -> UUID
}

protocol UserNotificationFetching {
    func fetchUserNotifications(userID: UUID, accessToken: String) async throws -> [UserNotificationRecord]
    func markUserNotificationRead(id: UUID, accessToken: String) async throws
}

protocol OwnerAuthenticating {
    func signInOwner(email: String, password: String) async throws -> OwnerSession
    func refreshOwnerSession(refreshToken: String) async throws -> OwnerSession
}

protocol OwnerEventReviewing {
    func currentUserHasSupportAccess(accessToken: String) async throws -> Bool
    func fetchOwnerEvents(accessToken: String) async throws -> [LocalEvent]
    func updateEventStatus(id: UUID, status: ListingStatus, accessToken: String) async throws
    func fetchMemberProfilesForSupport(accessToken: String) async throws -> [BusinessProfileRecord]
    func fetchMemberSubscriptionsForSupport(accessToken: String) async throws -> [BusinessSubscriptionRecord]
    func updateMemberProfileStatus(id: UUID, status: BusinessProfileStatus, reason: String?, supportNote: String?, accessToken: String) async throws
    func supportUnpublishMemberPublicProfile(id: UUID, reason: String, accessToken: String) async throws -> PublicBusinessProfileRecord
    func fetchSupportChangeRequests(accessToken: String) async throws -> [EventChangeRequest]
    func fetchSupportRequests(accessToken: String) async throws -> [SupportRequestRecord]
    func updateSupportRequest(id: UUID, status: SupportRequestStatus, supportNote: String?, accessToken: String) async throws
    func supportCompleteAccountDeletion(requestID: UUID, supportNote: String?, accessToken: String) async throws
    func fetchEventReportsForSupport(accessToken: String) async throws -> [EventReportRecord]
    func updateEventReport(id: UUID, status: EventReportStatus, supportNote: String?, accessToken: String) async throws
    func supportApproveChangeRequest(_ request: EventChangeRequest, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
    func supportRejectChangeRequest(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
    func supportMarkApplied(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
}

struct OwnerSession: Hashable {
    let accessToken: String
    let refreshToken: String
    let email: String?
    let expiresAt: Date?

    var shouldRefreshSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(300)
    }
}

enum SupportRequestStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case inReview = "in_review"
    case closed

    var id: String { rawValue }
}

struct SupportRequestRecord: Identifiable, Hashable {
    let id: UUID
    let submittedBy: UUID?
    let topic: String
    let listingReference: String?
    let message: String
    let status: SupportRequestStatus
    let supportNote: String?
    let createdAt: Date
    let updatedAt: Date
}

enum EventReportCategory: String, Codable, CaseIterable, Identifiable {
    case wrongOrOutdated = "wrong_or_outdated"
    case spamOrScam = "spam_or_scam"
    case unsafeOrHarmful = "unsafe_or_harmful"
    case inappropriateContent = "inappropriate_content"
    case wrongLocation = "wrong_location"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongOrOutdated: return "Wrong or outdated"
        case .spamOrScam: return "Spam or scam"
        case .unsafeOrHarmful: return "Unsafe or harmful"
        case .inappropriateContent: return "Inappropriate content"
        case .wrongLocation: return "Wrong location"
        case .other: return "Other"
        }
    }
}

enum EventReportStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case inReview = "in_review"
    case closed
    case dismissed

    var id: String { rawValue }
}

struct EventReportRecord: Identifiable, Hashable {
    let id: UUID
    let eventID: UUID
    let reporterUserID: UUID?
    let category: EventReportCategory
    let details: String?
    let status: EventReportStatus
    let supportNote: String?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let event: LocalEvent?
}

struct UserNotificationRecord: Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let title: String
    let body: String
    let notificationType: String
    let relatedTable: String?
    let relatedID: UUID?
    let readAt: Date?
    let createdAt: Date
}

struct SupabaseEventService: EventListingSubmitting, UserListingFetching, BusinessAccountManaging, BusinessProfileFetching, MemberPublicProfileManaging, MemberFollowingManaging, MemberNoticeManaging, EventChangeRequesting, PublishedEventFetching, LocationScopeFetching, NearestLocationScopeResolving, PollResponding, ListingAnalyticsFetching, EventAnalyticsRecording, AppOpenAnalyticsReporting, SupportRequestSubmitting, EventReportSubmitting, UserNotificationFetching, PushNotificationRegistering, OwnerAuthenticating, OwnerEventReviewing {
    static let publicMemberProfileResource = "public_member_profiles"
    static let publicHostDirectoryResource = "public_host_directory"
    static let publicEventsResource = "public_events"
    static let publicEventImagesResource = "public_event_images"
    static let publicEventSelect = [
        "id",
        "title",
        "category",
        "town",
        "location_display_name",
        "venue",
        "start_at",
        "end_at",
        "price_label",
        "is_free",
        "audience",
        "short_description",
        "long_description",
        "contact_name",
        "contact_phone",
        "contact_email",
        "business_profile_id",
        "organisation_name",
        "is_featured",
        "is_paid_push",
        "status",
        "listing_kind",
        "poll_question",
        "poll_options",
        "poll_allows_custom_answer",
        "unverified_user_listing",
        "created_at",
        "updated_at"
    ].joined(separator: ",")
    static let publicEventImageSelect = [
        "id",
        "event_id",
        "storage_path",
        "position",
        "mime_type",
        "byte_size",
        "width",
        "height"
    ].joined(separator: ",")
    static let publicMemberProfileSelect = [
        "id",
        "public_slug",
        "display_name",
        "area_scope_id",
        "bio",
        "public_contact_name",
        "public_contact_email",
        "public_phone",
        "public_location_text",
        "public_address",
        "public_website",
        "avatar_image_path",
        "hero_image_path",
        "avatar_image_position_x",
        "avatar_image_position_y",
        "hero_image_position_x",
        "hero_image_position_y",
        "published_at",
        "public_contact_revision",
        "public_contact_confirmed_revision",
        "public_contact_confirmed_at"
    ].joined(separator: ",")

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Self.fractionalISODateFormatter.date(from: value) ?? Self.isoDateFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        encoder.dateEncodingStrategy = .iso8601
    }


    private func attachingTopics(to events: [LocalEvent]) async -> [LocalEvent] {
        guard !events.isEmpty, var components = publicEventsURLComponents else { return events }
        components.path = components.path.replacingOccurrences(of: "public_events", with: "event_topics")
        let list = events.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "select", value: "event_id,topic_slug"),
            URLQueryItem(name: "event_id", value: "in.(\(list))")
        ]
        guard let url = components.url else { return events }
        do {
            let (data, response) = try await session.data(for: request(url: url))
            try validate(response)
            struct TopicRow: Decodable {
                let eventID: UUID
                let topicSlug: String
                enum CodingKeys: String, CodingKey {
                    case eventID = "event_id"
                    case topicSlug = "topic_slug"
                }
            }
            let rows = try decoder.decode([TopicRow].self, from: data)
            let grouped = Dictionary(grouping: rows, by: \.eventID)
            return events.map { event in
                var copy = event
                let slugs = (grouped[event.id] ?? []).map(\.topicSlug)
                copy.topics = slugs.compactMap(EventCategory.init(rawValue:))
                return copy
            }
        } catch {
            print("[Topics] attach failed error=\(error)")
            return events
        }
    }

    func fetchPublishedEvents() async throws -> [LocalEvent] {
        guard var components = publicEventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        let archiveCutoff = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicEventSelect),
            URLQueryItem(name: "start_at", value: "gte.\(Self.isoDateFormatter.string(from: archiveCutoff))"),
            URLQueryItem(name: "order", value: "is_paid_push.desc,is_featured.desc,start_at.asc")
        ]

        let localEvents = try await fetchPublicEvents(with: components, logContext: "public")
        let withTopics = await attachingTopics(to: localEvents)
        return await applyingActivePromotions(to: withTopics, accessToken: nil)
    }

    func fetchPublishedEvents(from rangeStart: Date, to rangeEnd: Date) async throws -> [LocalEvent] {
        guard var components = publicEventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicEventSelect),
            URLQueryItem(name: "end_at", value: "gte.\(Self.isoDateFormatter.string(from: rangeStart))"),
            URLQueryItem(name: "start_at", value: "lt.\(Self.isoDateFormatter.string(from: rangeEnd))"),
            URLQueryItem(name: "order", value: "start_at.asc")
        ]

        let localEvents = try await fetchPublicEvents(with: components, logContext: "public range")
        let withTopics = await attachingTopics(to: localEvents)
        return await applyingActivePromotions(to: withTopics, accessToken: nil)
    }

    func fetchPublishedEvents(locationScopeID: String) async throws -> [LocalEvent] {
        guard locationScopeID != LocationScope.defaultID || SupabaseConfiguration.isConfigured else {
            return try await fetchPublishedEvents()
        }

        let eventIDs = try await fetchPublishedEventIDs(locationScopeID: locationScopeID)
        print("[Home] location IDs scope=\(locationScopeID) count=\(eventIDs.count)")
        guard !eventIDs.isEmpty else { return [] }

        guard var components = publicEventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        let archiveCutoff = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicEventSelect),
            URLQueryItem(name: "id", value: "in.(\(eventIDs.map(\.uuidString).joined(separator: ",")))"),
            URLQueryItem(name: "start_at", value: "gte.\(Self.isoDateFormatter.string(from: archiveCutoff))"),
            URLQueryItem(name: "order", value: "is_paid_push.desc,is_featured.desc,start_at.asc")
        ]

        let localEvents = try await fetchPublicEvents(with: components, logContext: "public location")
        let withTopics = await attachingTopics(to: localEvents)
        return await applyingActivePromotions(to: withTopics, accessToken: nil)
    }

    func fetchPublishedEvents(submittedBy userID: UUID) async throws -> [LocalEvent] {
        _ = userID
        return []
    }

    func fetchEventsByIDs(_ ids: [UUID], accessToken: String?) async throws -> [LocalEvent] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty, var components = eventsURLComponents else { return [] }
        let list = unique.map { $0.uuidString.lowercased() }.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "id", value: "in.(\(list))")
        ]
        guard let url = components.url else { return [] }
        let token = accessToken ?? ""
        let (data, response) = try await session.data(for: token.isEmpty ? request(url: url) : request(url: url, accessToken: token))
        try validate(response)
        return await events(from: try decoder.decode([SupabaseEventRecord].self, from: data), accessToken: accessToken, logContext: "going ids")
    }

    func fetchPublishedEvents(businessProfileID profileID: UUID) async throws -> [LocalEvent] {
        guard var components = publicEventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        let archiveCutoff = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicEventSelect),
            URLQueryItem(name: "business_profile_id", value: "eq.\(profileID.uuidString.lowercased())"),
            URLQueryItem(name: "start_at", value: "gte.\(Self.isoDateFormatter.string(from: archiveCutoff))"),
            URLQueryItem(name: "order", value: "start_at.asc")
        ]

        let localEvents = try await fetchPublicEvents(with: components, logContext: "public business profile")
        let withTopics = await attachingTopics(to: localEvents)
        return await applyingActivePromotions(to: withTopics, accessToken: nil)
    }

    func submitPollResponse(eventID: UUID, userID: UUID, selectedOption: String?, customAnswer: String?, accessToken: String) async throws {
        guard var components = eventPollResponsesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "event_id,respondent_id")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(
            PollResponseUpsert(
                eventID: eventID,
                respondentID: userID,
                selectedOption: selectedOption?.trimmed.nilIfEmpty,
                customAnswer: customAnswer?
                    .trimmed
                    .prefix(PollDetails.customAnswerLimit)
                    .description
                    .nilIfEmpty
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchPollResponseCounts(eventID: UUID) async throws -> PollResults {
        guard let url = rpcURL(functionName: "poll_response_counts_for_event") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PollCountsRequest(eventID: eventID))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        let records = try decoder.decode([PollResponseCountRecord].self, from: data)
        return PollResults(
            counts: records.map {
                PollResponseCount(optionText: $0.optionText, responseCount: $0.responseCount)
            }
        )
    }

    func fetchOwnerPollResponseCounts(eventID: UUID, accessToken: String) async throws -> PollResults {
        guard let url = rpcURL(functionName: "poll_owner_response_counts_for_event") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PollCountsRequest(eventID: eventID))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        let records = try decoder.decode([PollResponseCountRecord].self, from: data)
        return PollResults(
            counts: records.map {
                PollResponseCount(optionText: $0.optionText, responseCount: $0.responseCount)
            }
        )
    }

    func withdrawPollResponse(eventID: UUID, accessToken: String) async throws {
        guard var components = eventPollResponsesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        components.queryItems = [
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString.lowercased())")
        ]
        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchMyPollResponse(eventID: UUID, userID: UUID, accessToken: String) async throws -> PollUserResponse? {
        guard var components = eventPollResponsesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "selected_option,custom_answer,updated_at"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString.lowercased())"),
            URLQueryItem(name: "respondent_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)

        return try decoder.decode([SupabasePollResponseRecord].self, from: data)
            .first?
            .pollUserResponse
    }

    func fetchPollCustomResponses(eventID: UUID, accessToken: String) async throws -> [PollCustomResponse] {
        guard let url = rpcURL(functionName: "poll_custom_responses_for_event") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PollCountsRequest(eventID: eventID))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode([SupabasePollCustomResponseRecord].self, from: data)
            .map(\.pollCustomResponse)
    }

    func fetchLocationCatalog() async throws -> LocationCatalog {
        async let scopes = fetchLocationScopes()
        async let edges = fetchLocationScopeEdges()
        async let aliases = fetchLocationAliases()

        let scopeRecords = try await scopes
        let edgeRecords = try await edges
        let aliasRecords = try await aliases
        let aliasesBySlug = Dictionary(grouping: aliasRecords, by: \.locationSlug)
            .mapValues { $0.map(\.alias) }

        let remoteScopes = scopeRecords.compactMap { record -> LocationScope? in
            guard let kind = LocationScopeKind(databaseValue: record.scopeType) else { return nil }

            return LocationScope(
                id: record.slug,
                name: record.name,
                kind: kind,
                subtitle: record.subtitle ?? record.name,
                townMatches: Self.localTownMatches(for: record.slug),
                searchTerms: Self.locationSearchTerms(for: record.slug, aliases: aliasesBySlug[record.slug, default: []]),
                ladderIDs: []
            )
        }
        .sorted { lhs, rhs in
            let lhsPriority = scopeRecords.first { $0.slug == lhs.id }?.sortPriority ?? 1000
            let rhsPriority = scopeRecords.first { $0.slug == rhs.id }?.sortPriority ?? 1000
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.name < rhs.name
        }

        guard !remoteScopes.isEmpty else {
            throw SupabaseServiceError.invalidResponse
        }

        let linksByChildID = Dictionary(grouping: edgeRecords.filter { $0.relationshipType == "widens_to" }, by: \.childSlug)
            .mapValues { edges in
                edges
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(\.parentSlug)
            }

        let quickIDs = [
            LocationScope.defaultID,
            "beachlands",
            "maraetai",
            "omana",
            "clevedon",
            "whitford"
        ].filter { slug in
            remoteScopes.contains { $0.id == slug }
        }

        return LocationCatalog(
            scopes: remoteScopes,
            linksByChildID: linksByChildID.isEmpty ? LocationScope.localLinksByChildID : linksByChildID,
            quickScopeIDs: quickIDs.isEmpty ? LocationScope.quickScopes.map(\.id) : quickIDs
        )
    }

    func nearestLocationScopes(latitude: Double, longitude: Double, maxResults: Int = 1) async throws -> [NearestLocationScopeMatch] {
        guard let url = rpcURL(functionName: "nearest_location_scope") else {
            throw SupabaseServiceError.notConfigured
        }

        let limitedResults = min(max(maxResults, 1), 12)
        var request = request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(NearestLocationScopeRequest(
            latitude: latitude,
            longitude: longitude,
            maxResults: limitedResults
        ))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode([SupabaseNearestLocationScopeRecord].self, from: data)
            .compactMap(\.match)
    }

    func fetchListingAnalytics(eventID: UUID, accessToken: String) async throws -> ListingAnalyticsSnapshot {
        guard var components = eventAnalyticsDailyURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "impressions,detail_views,interested_taps,going_taps,save_taps,share_taps,poll_answers,promotion_impressions"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)

        let rows = try decoder.decode([SupabaseListingAnalyticsDailyRecord].self, from: data)
        return rows.reduce(.zero) { partial, row in
            ListingAnalyticsSnapshot(
                impressions: partial.impressions + row.impressions,
                detailViews: partial.detailViews + row.detailViews,
                engagementTaps: partial.engagementTaps + row.interestedTaps + row.goingTaps + row.pollAnswers,
                saves: partial.saves + row.saveTaps,
                shares: partial.shares + row.shareTaps
            )
        }
    }

    func recordEventAnalytics(eventID: UUID, eventType: String, source: String?, locationScopeID: String?, accessToken: String?) async throws {
        guard let url = rpcURL(functionName: "record_event_analytics") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            EventAnalyticsRecordRequest(
                eventID: eventID,
                eventType: eventType,
                source: source,
                locationScopeSlug: locationScopeID,
                sessionID: nil,
                metadata: [:]
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func recordAppOpenAndFetchWeeklyViews(installationID: String) async throws -> Int {
        guard let url = rpcURL(functionName: "record_app_open") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AppOpenRecordRequest(installationID: installationID))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(Int.self, from: data)
    }

    func fetchWeeklyAppOpenViews() async throws -> Int {
        guard let url = rpcURL(functionName: "get_weekly_app_open_count") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(Int.self, from: data)
    }

    func submitSupportRequest(topic: String, message: String, listingReference: String?, accessToken: String) async throws -> UUID {
        guard let url = rpcURL(functionName: "submit_support_request") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            SupportRequestSubmitRequest(
                topic: topic,
                message: message,
                listingReference: listingReference
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode(UUID.self, from: data)
    }

    func submitEventReport(eventID: UUID, category: EventReportCategory, details: String?, accessToken: String) async throws -> UUID {
        guard let url = rpcURL(functionName: "submit_event_report") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            EventReportSubmitRequest(
                eventID: eventID,
                category: category,
                details: details?.trimmed.nilIfEmpty
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode(UUID.self, from: data)
    }

    func fetchMySupportRequests(userID: UUID, accessToken: String) async throws -> [SupportRequestRecord] {
        guard var components = supportRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "submitted_by", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try decoder.decode([SupabaseSupportRequestRecord].self, from: data).map(\.supportRequest)
    }

    private func insertEventTopics(eventID: UUID, draft: PendingListingDraft, accessToken: String) async {
        let selected = draft.topics.isEmpty ? [draft.category] : draft.topics
        guard var components = eventsURLComponents else { return }
        components.path = components.path.replacingOccurrences(of: "/events", with: "/event_topics")
        components.queryItems = nil
        guard let url = components.url else { return }

        struct TopicInsert: Encodable {
            let eventID: UUID
            let topicSlug: String
            let source: String
            enum CodingKeys: String, CodingKey {
                case eventID = "event_id"
                case topicSlug = "topic_slug"
                case source
            }
        }

        let rows = selected.map { TopicInsert(eventID: eventID, topicSlug: $0.rawValue, source: "user") }
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? encoder.encode(rows)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("[Topics] insert failed status=\(http.statusCode) body=\(String(data: data, encoding: .utf8) ?? "")")
            } else {
                print("[Topics] insert ok event=\(eventID.uuidString) count=\(rows.count)")
            }
        } catch {
            print("[Topics] insert failed error=\(error)")
        }
    }

    func submitPendingListing(_ draft: PendingListingDraft, businessProfileID: UUID, accessToken: String) async throws -> UUID {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "id")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let insert = PendingEventInsert(
            draft: draft,
            businessProfileID: businessProfileID,
            includeStructuredPollColumns: true
        )
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(insert)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            debugService(step: "submit listing", message: "failed status=\(httpResponse.statusCode), body=\(body ?? "<unreadable response body>")")

            if draft.listingKind == .poll,
               shouldRetryPollInsertWithoutStructuredColumns(statusCode: httpResponse.statusCode, responseBody: body) {
                return try await submitPendingListingWithoutStructuredPollColumns(insert, url: url, accessToken: accessToken)
            }

            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, body)
        }

        guard let inserted = try decoder.decode([InsertedEventResponse].self, from: data).first else {
            throw SupabaseServiceError.invalidResponse
        }

        await insertEventTopics(eventID: inserted.id, draft: draft, accessToken: accessToken)
        return inserted.id
    }

    private func submitPendingListingWithoutStructuredPollColumns(_ insert: PendingEventInsert, url: URL, accessToken: String) async throws -> UUID {
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(insert.withoutStructuredPollColumns())

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            debugService(step: "submit listing fallback", message: "failed status=\(httpResponse.statusCode), body=\(body ?? "<unreadable response body>")")
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, body)
        }

        guard let inserted = try decoder.decode([InsertedEventResponse].self, from: data).first else {
            throw SupabaseServiceError.invalidResponse
        }

        return inserted.id
    }

    private func shouldRetryPollInsertWithoutStructuredColumns(statusCode: Int, responseBody: String?) -> Bool {
        guard statusCode == 400 || statusCode == 404 else { return false }
        let body = responseBody?.lowercased() ?? ""
        return body.contains("schema cache")
            || body.contains("listing_kind")
            || body.contains("poll_question")
            || body.contains("poll_options")
            || body.contains("poll_allows_custom_answer")
    }

    func uploadListingImage(_ image: ListingPhotoUpload, eventID: UUID, userID: UUID, position: Int, accessToken: String) async throws {
        let imageID = UUID()
        let storagePath = ListingImageStoragePath.make(userID: userID, eventID: eventID, imageID: imageID)

        try await uploadStorageObject(data: image.data, storagePath: storagePath, mimeType: image.mimeType, accessToken: accessToken)
        try await insertEventImageMetadata(
            image: image,
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            accessToken: accessToken
        )
    }

    func fetchUserListings(userID: UUID, accessToken: String) async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "submitted_by", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await events(from: try decoder.decode([SupabaseEventRecord].self, from: data), accessToken: accessToken, logContext: "user listings")
    }

    func fetchBusinessAccount(userID: UUID, accessToken: String) async throws -> BusinessAccountState {
        guard var subscriptionComponents = businessSubscriptionsURLComponents,
              var sponsorComponents = businessSponsorRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        let userIDText = userID.uuidString.lowercased()
        subscriptionComponents.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "owner_user_id", value: "eq.\(userIDText)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        sponsorComponents.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "owner_user_id", value: "eq.\(userIDText)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let profileURL = rpcURL(functionName: "my_business_profile"),
              let subscriptionURL = subscriptionComponents.url,
              let sponsorURL = sponsorComponents.url else {
            throw SupabaseServiceError.notConfigured
        }

        async let profileResponse = session.data(for: rpcRequest(url: profileURL, body: EmptyRPCRequest(), accessToken: accessToken))
        async let subscriptionResponse = session.data(for: request(url: subscriptionURL, accessToken: accessToken))
        async let sponsorResponse = session.data(for: request(url: sponsorURL, accessToken: accessToken))

        let (profileData, profileHTTPResponse) = try await profileResponse
        let (subscriptionData, subscriptionHTTPResponse) = try await subscriptionResponse
        let (sponsorData, sponsorHTTPResponse) = try await sponsorResponse

        try validate(profileHTTPResponse, data: profileData)
        try validate(subscriptionHTTPResponse, data: subscriptionData)
        try validate(sponsorHTTPResponse, data: sponsorData)

        let profiles = try decoder.decode([BusinessProfileRecord].self, from: profileData)
        return BusinessAccountState(
            profile: profiles.first,
            subscriptions: try decoder.decode([BusinessSubscriptionRecord].self, from: subscriptionData),
            sponsorRequests: try decoder.decode([FoundingSponsorRequestRecord].self, from: sponsorData)
        )
    }

    func fetchBusinessProfile(profileID: UUID) async throws -> PublicBusinessProfileRecord? {
        guard var components = publicHostDirectoryURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicMemberProfileSelect),
            URLQueryItem(name: "id", value: "eq.\(profileID.uuidString.lowercased())"),
            URLQueryItem(name: "published_at", value: "not.is.null"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response, data: data)
        return try decoder.decode([PublicBusinessProfileRecord].self, from: data).first
    }

    func fetchApprovedBusinessProfiles() async throws -> [PublicBusinessProfileRecord] {
        guard var components = publicHostDirectoryURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicMemberProfileSelect),
            URLQueryItem(name: "published_at", value: "not.is.null"),
            URLQueryItem(name: "order", value: "display_name.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response, data: data)
        return try decoder.decode([PublicBusinessProfileRecord].self, from: data)
    }

    func fetchOwnPublicProfileDraft(profileID: UUID, accessToken: String) async throws -> PublicBusinessProfileRecord? {
        guard var components = publicMemberProfilesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicMemberProfileSelect),
            URLQueryItem(name: "id", value: "eq.\(profileID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { throw SupabaseServiceError.notConfigured }
        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try decoder.decode([PublicBusinessProfileRecord].self, from: data).first
    }

    func saveOwnPublicProfileDraft(profileID: UUID, draft: PublicMemberProfileDraft, accessToken: String) async throws -> PublicBusinessProfileRecord {
        try await callPublicProfileRPC(
            "save_member_public_profile_with_images",
            body: SaveMemberPublicProfileRequest(profileID: profileID, draft: draft),
            accessToken: accessToken
        )
    }

    func confirmOwnPublicContact(profileID: UUID, revision: UUID, accessToken: String) async throws -> PublicBusinessProfileRecord {
        try await callPublicProfileRPC(
            "confirm_member_public_contact",
            body: ConfirmMemberPublicContactRequest(profileID: profileID, revision: revision),
            accessToken: accessToken
        )
    }

    func supportUnpublishMemberPublicProfile(id: UUID, reason: String, accessToken: String) async throws -> PublicBusinessProfileRecord {
        try await callPublicProfileRPC(
            "support_unpublish_member_public_profile",
            body: SupportUnpublishMemberPublicProfileRequest(profileID: id, reason: reason),
            accessToken: accessToken
        )
    }

    func memberProfileImageRequest(path: String?, accessToken: String?) -> URLRequest? {
        MemberProfileImageDelivery.request(path: path, accessToken: accessToken)
    }

    private func callPublicProfileRPC<Body: Encodable>(_ functionName: String, body: Body, accessToken: String) async throws -> PublicBusinessProfileRecord {
        guard let url = rpcURL(functionName: functionName) else { throw SupabaseServiceError.notConfigured }
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if let record = try? decoder.decode(PublicBusinessProfileRecord.self, from: data) {
            return record
        }
        if let record = try decoder.decode([PublicBusinessProfileRecord].self, from: data).first {
            return record
        }
        throw SupabaseServiceError.invalidResponse
    }

    func fetchMemberFollow(profileID: UUID, userID: UUID, accessToken: String) async throws -> Bool {
        guard var components = memberFollowsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "business_profile_id", value: "eq.\(profileID.uuidString)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try !decoder.decode([MemberFollowLookup].self, from: data).isEmpty
    }

    func setMemberFollow(profileID: UUID, userID: UUID, isFollowing: Bool, accessToken: String) async throws {
        guard var components = memberFollowsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        if isFollowing {
            components.queryItems = [
                URLQueryItem(name: "on_conflict", value: "user_id,business_profile_id")
            ]
            guard let url = components.url else {
                throw SupabaseServiceError.notConfigured
            }

            var request = request(url: url, accessToken: accessToken)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try encoder.encode(MemberFollowUpsert(userID: userID, businessProfileID: profileID))
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data)
        } else {
            components.queryItems = [
                URLQueryItem(name: "business_profile_id", value: "eq.\(profileID.uuidString)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ]
            guard let url = components.url else {
                throw SupabaseServiceError.notConfigured
            }

            var request = request(url: url, accessToken: accessToken)
            request.httpMethod = "DELETE"
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data)
        }
    }

    func fetchMemberNotices(profileID: UUID, accessToken: String? = nil) async throws -> [MemberNoticeRecord] {
        guard var components = memberNoticesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        var queryItems = [
            URLQueryItem(name: "select", value: "id,business_profile_id,owner_user_id,title,summary,body,template_style,status,hero_image_url,published_at,created_at,updated_at"),
            URLQueryItem(name: "business_profile_id", value: "eq.\(profileID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "published_at.desc.nullslast,created_at.desc")
        ]
        if accessToken == nil {
            queryItems.append(URLQueryItem(name: "status", value: "eq.published"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try decoder.decode([MemberNoticeRecord].self, from: data)
    }

    func fetchNoticeReads(accessToken: String) async throws -> [UUID] {
        guard var components = noticeReadsURLComponents else { throw SupabaseServiceError.notConfigured }
        components.queryItems = [URLQueryItem(name: "select", value: "notice_id")]
        guard let url = components.url else { throw SupabaseServiceError.notConfigured }
        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        struct Row: Decodable { let notice_id: UUID }
        return try decoder.decode([Row].self, from: data).map(\.notice_id)
    }

    func markNoticeRead(noticeID: UUID, userID: UUID, accessToken: String) async throws {
        guard let url = noticeReadsURLComponents?.url else { throw SupabaseServiceError.notConfigured }
        var req = request(url: url, accessToken: accessToken)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        struct Body: Encodable {
            let notice_id: UUID
            let user_id: UUID
        }
        req.httpBody = try encoder.encode(Body(notice_id: noticeID, user_id: userID))
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    func markAllNoticesRead(noticeIDs: [UUID], userID: UUID, accessToken: String) async throws {
        for id in noticeIDs { try await markNoticeRead(noticeID: id, userID: userID, accessToken: accessToken) }
    }

    func createMemberNotice(profileID: UUID, ownerUserID: UUID, title: String, summary: String, body: String, accessToken: String) async throws -> MemberNoticeRecord {
        guard let url = memberNoticesURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(MemberNoticeCreateRequest(
            businessProfileID: profileID,
            ownerUserID: ownerUserID,
            title: title.trimmed,
            summary: summary.trimmed.nilIfEmpty,
            body: body.trimmed.nilIfEmpty,
            templateStyle: "weekly_letter",
            status: "published"
        ))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let notice = try decoder.decode([MemberNoticeRecord].self, from: data).first else {
            throw SupabaseServiceError.invalidResponse
        }
        return notice
    }

    func upsertBusinessProfile(_ draft: BusinessProfileDraft, ownerUserID: UUID, accessToken: String) async throws -> BusinessProfileRecord {
        guard let url = rpcURL(functionName: "save_my_business_profile") else {
            throw SupabaseServiceError.notConfigured
        }

        let request = try rpcRequest(
            url: url,
            body: BusinessProfileSaveRequest(draft: draft),
            accessToken: accessToken
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if let profile = try? decoder.decode(BusinessProfileRecord.self, from: data) {
            return profile
        }
        if let profile = try decoder.decode([BusinessProfileRecord].self, from: data).first {
            return profile
        }
        throw SupabaseServiceError.invalidResponse
    }

    func uploadMemberProfileImage(data: Data, mimeType: String, kind: String, userID: UUID, accessToken: String) async throws -> String {
        let safeKind = kind == "avatar" ? "avatar" : "hero"
        let imageID = UUID()
        let storagePath = "\(userID.uuidString.lowercased())/\(safeKind)-\(imageID.uuidString.lowercased()).jpg"
        try await uploadStorageObject(data: data, bucket: "member-images", storagePath: storagePath, mimeType: mimeType, accessToken: accessToken)
        return storagePath
    }

    func deleteMemberProfileImage(path: String, accessToken: String) async throws {
        guard let url = storageObjectURL(bucket: "member-images", storagePath: path) else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func createFoundingSponsorRequest(profileID: UUID, package: FoundingSponsorPackage, notes: String?, ownerUserID: UUID, accessToken: String) async throws -> FoundingSponsorRequestRecord {
        guard let url = businessSponsorRequestsURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(
            FoundingSponsorRequestInsert(
                businessProfileID: profileID,
                ownerUserID: ownerUserID,
                packageID: package.rawValue,
                notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let sponsorRequest = try decoder.decode([FoundingSponsorRequestRecord].self, from: data).first else {
            throw SupabaseServiceError.invalidResponse
        }
        return sponsorRequest
    }

    func createEditRequest(
        event: LocalEvent,
        draft: ListingEditDraft,
        requesterID: UUID,
        requesterNote: String?,
        accessToken: String
    ) async throws {
        try await insertChangeRequest(
            EventChangeRequestInsert(
                eventID: event.id,
                requestedBy: requesterID,
                changeType: .editRequest,
                proposedChanges: draft.proposedChanges,
                requesterNote: requesterNote?.trimmed.nilIfEmpty
            ),
            accessToken: accessToken
        )
    }

    func createRemovalRequest(
        event: LocalEvent,
        requesterID: UUID,
        requesterNote: String?,
        accessToken: String
    ) async throws {
        try await insertChangeRequest(
            EventChangeRequestInsert(
                eventID: event.id,
                requestedBy: requesterID,
                changeType: .removalRequest,
                proposedChanges: [:],
                requesterNote: requesterNote?.trimmed.nilIfEmpty
            ),
            accessToken: accessToken
        )
    }


    func updateOrgCalendarListing(eventID: UUID, title: String, venue: String, details: String, day: Date, isPublic: Bool, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "owner_update_org_calendar_listing") else {
            throw SupabaseServiceError.notConfigured
        }
        struct Body: Encodable {
            let p_event_id: UUID
            let p_title: String
            let p_venue: String
            let p_details: String
            let p_start_at: Date
            let p_visibility: String
        }
        let request = try rpcRequest(
            url: url,
            body: Body(
                p_event_id: eventID,
                p_title: title,
                p_venue: venue,
                p_details: details,
                p_start_at: day,
                p_visibility: isPublic ? "public" : "private"
            ),
            accessToken: accessToken
        )
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func archiveOwnListing(eventID: UUID, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "owner_archive_own_listing") else {
            throw SupabaseServiceError.notConfigured
        }
        let request = try rpcRequest(
            url: url,
            body: OwnerArchiveListingRequest(eventID: eventID),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchMyChangeRequests(userID: UUID, accessToken: String) async throws -> [EventChangeRequest] {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,events(*,event_images(*))"),
            URLQueryItem(name: "requested_by", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await changeRequests(from: try decoder.decode([SupabaseEventChangeRequestRecord].self, from: data), accessToken: accessToken)
    }

    func markUserNotificationRead(id: UUID, accessToken: String) async throws {
        guard var components = userNotificationsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")
        ]
        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        struct ReadStamp: Encodable { let read_at: String }
        request.httpBody = try encoder.encode(ReadStamp(read_at: ISO8601DateFormatter().string(from: Date())))
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchUserNotifications(userID: UUID, accessToken: String) async throws -> [UserNotificationRecord] {
        guard var components = userNotificationsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "20")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return try decoder.decode([SupabaseUserNotificationRecord].self, from: data).map(\.record)
    }

    func upsertPushDeviceToken(_ registration: PushDeviceTokenRegistration, accessToken: String) async throws {
        guard var components = userPushTokensURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id,token")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(registration)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func deletePushDeviceToken(token: String, userID: UUID, accessToken: String) async throws {
        guard var components = userPushTokensURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "token", value: "eq.\(token)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func signInOwner(email: String, password: String) async throws -> OwnerSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "password")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(OwnerPasswordLogin(email: email.trimmed, password: password))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.authFailed
        }

        let token = try decoder.decode(SupabaseAuthTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken else {
            throw SupabaseServiceError.authFailed
        }

        return OwnerSession(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func refreshOwnerSession(refreshToken: String) async throws -> OwnerSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(OwnerRefreshLogin(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.authFailed
        }

        let token = try decoder.decode(SupabaseAuthTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken else {
            throw SupabaseServiceError.authFailed
        }

        return OwnerSession(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func currentUserHasSupportAccess(accessToken: String) async throws -> Bool {
        guard let url = rpcURL(functionName: "current_user_is_support") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(Bool.self, from: data)
    }

    func fetchOwnerEvents(accessToken: String) async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "order", value: "created_at.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        let records = try decoder.decode([SupabaseEventRecord].self, from: data)
        return await events(from: records, accessToken: accessToken, logContext: "owner")
    }

    private func events(from records: [SupabaseEventRecord], accessToken: String?, logContext: String) async -> [LocalEvent] {
        var events: [LocalEvent] = []

        for record in records {
            let imageRecords = record.eventImages ?? []
            let signedImages = await signedEventImages(from: imageRecords, eventID: record.id, accessToken: accessToken)
            if let event = record.localEvent(images: signedImages) {
                events.append(event)
            }
        }

        return events
    }

    private func fetchPublicEvents(with components: URLComponents, logContext: String) async throws -> [LocalEvent] {
        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        let records = try decoder.decode([SupabaseEventRecord].self, from: data)
        let imageRecords: [UUID: [SupabaseEventImageRecord]]
        do {
            imageRecords = try await fetchPublicEventImages(eventIDs: records.map(\.id))
        } catch {
            print("[Home] public images skipped \(error)")
            imageRecords = [:]
        }
        return await events(from: records, imageRecordsByEventID: imageRecords, accessToken: nil, logContext: logContext)
    }

    private func events(
        from records: [SupabaseEventRecord],
        imageRecordsByEventID: [UUID: [SupabaseEventImageRecord]],
        accessToken: String?,
        logContext: String
    ) async -> [LocalEvent] {
        var events: [LocalEvent] = []

        for record in records {
            let signedImages = await signedEventImages(from: imageRecordsByEventID[record.id] ?? [], eventID: record.id, accessToken: accessToken)
            if let event = record.localEvent(images: signedImages) {
                events.append(event)
            }
        }

        return events
    }

    private func fetchPublicEventImages(eventIDs: [UUID]) async throws -> [UUID: [SupabaseEventImageRecord]] {
        guard !eventIDs.isEmpty else { return [:] }
        guard var components = publicEventImagesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: Self.publicEventImageSelect),
            URLQueryItem(name: "event_id", value: "in.(\(eventIDs.map(\.uuidString).joined(separator: ",")))"),
            URLQueryItem(name: "order", value: "position.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return Dictionary(grouping: try decoder.decode([SupabaseEventImageRecord].self, from: data), by: \.eventID)
    }

    private func applyingActivePromotions(to events: [LocalEvent], accessToken: String?) async -> [LocalEvent] {
        let eventIDs = events.map(\.id)
        guard !eventIDs.isEmpty,
              let promotions = try? await fetchActivePromotions(eventIDs: eventIDs, accessToken: accessToken),
              !promotions.isEmpty else {
            return events
        }

        return events.map { event in
            guard let promotion = promotions[event.id] else { return event }
            return event.applyingActivePromotion(rank: promotion.placementRank, paidAt: promotion.paidAt)
        }
    }

    private func fetchActivePromotions(eventIDs: [UUID], accessToken: String?) async throws -> [UUID: SupabaseActiveEventPromotionRecord] {
        guard var components = activeEventPromotionsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        let idList = eventIDs
            .map { $0.uuidString.lowercased() }
            .joined(separator: ",")

        components.queryItems = [
            URLQueryItem(name: "select", value: "event_id,tier,placement,starts_at,ends_at,paid_at,placement_rank"),
            URLQueryItem(name: "event_id", value: "in.(\(idList))"),
            URLQueryItem(name: "order", value: "placement_rank.desc,paid_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)

        return try decoder.decode([SupabaseActiveEventPromotionRecord].self, from: data)
            .reduce(into: [:]) { partial, promotion in
                guard let existing = partial[promotion.eventID] else {
                    partial[promotion.eventID] = promotion
                    return
                }

                if promotion.sortsBefore(existing) {
                    partial[promotion.eventID] = promotion
                }
            }
    }

    private func fetchLocationScopes() async throws -> [SupabaseLocationScopeRecord] {
        guard var components = locationScopesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "slug,name,scope_type,subtitle,sort_priority"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "is_selectable", value: "eq.true"),
            URLQueryItem(name: "order", value: "sort_priority.asc,name.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return try decoder.decode([SupabaseLocationScopeRecord].self, from: data)
    }

    private func fetchLocationScopeEdges() async throws -> [SupabaseLocationScopeEdgeRecord] {
        guard var components = locationScopeEdgesURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "child_slug,parent_slug,relationship_type,sort_order"),
            URLQueryItem(name: "relationship_type", value: "eq.widens_to"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return try decoder.decode([SupabaseLocationScopeEdgeRecord].self, from: data)
    }

    private func fetchLocationAliases() async throws -> [SupabaseLocationAliasRecord] {
        guard var components = locationAliasSearchTermsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "location_slug,alias")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return try decoder.decode([SupabaseLocationAliasRecord].self, from: data)
    }

    private func fetchPublishedEventIDs(locationScopeID: String) async throws -> [UUID] {
        guard var components = publishedEventLocationTargetsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "event_id,sort_order"),
            URLQueryItem(name: "location_slug", value: "eq.\(locationScopeID)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return try decoder.decode([SupabasePublishedEventLocationTargetRecord].self, from: data).map(\.eventID)
    }

    func insertOrgCalendarListing(profileID: UUID, title: String, venue: String, details: String, day: Date, isPublic: Bool, accessToken: String) async throws -> UUID {
        guard let url = rpcURL(functionName: "owner_insert_org_calendar_listing") else {
            throw SupabaseServiceError.notConfigured
        }
        let dayStart = Calendar.current.startOfDay(for: day)
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart
        struct Body: Encodable {
            let p_profile_id: UUID
            let p_title: String
            let p_start_at: Date
            let p_end_at: Date
            let p_visibility: String
            let p_town: String
            let p_location_scope_id: String
            let p_location_display_name: String
            let p_details: String
        }
        let request = try rpcRequest(
            url: url,
            body: Body(
                p_profile_id: profileID,
                p_title: title,
                p_start_at: start,
                p_end_at: start.addingTimeInterval(7200),
                p_visibility: isPublic ? "public" : "private",
                p_town: "Beachlands",
                p_location_scope_id: "",
                p_location_display_name: venue,
                p_details: details
            ),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if let id = try? decoder.decode(UUID.self, from: data) { return id }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
        if let id = UUID(uuidString: raw) { return id }
        throw SupabaseServiceError.notConfigured
    }


    func fetchMyCalendarListings(accessToken: String) async throws -> [LocalEvent] {
        guard let url = rpcURL(functionName: "fetch_my_calendar_listings") else {
            throw SupabaseServiceError.notConfigured
        }
        let request = try rpcRequest(url: url, body: EmptyRPCRequest(), accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let records = try decoder.decode([SupabaseEventRecord].self, from: data)
        let images = (try? await fetchOwnerEventImages(eventIDs: records.map(\.id), accessToken: accessToken)) ?? [:]
        return await events(from: records, imageRecordsByEventID: images, accessToken: accessToken, logContext: "my calendar")
    }

    func fetchOrgCalendarListings(profileID: UUID, accessToken: String?) async throws -> [LocalEvent] {
        guard let url = rpcURL(functionName: "fetch_org_calendar_listings") else {
            throw SupabaseServiceError.notConfigured
        }
        struct Body: Encodable { let p_profile_id: UUID }
        let token = accessToken ?? ""
        let request = try rpcRequest(url: url, body: Body(p_profile_id: profileID), accessToken: token.isEmpty ? "" : token)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let records = try decoder.decode([SupabaseEventRecord].self, from: data)
        let images = (try? await fetchOwnerEventImages(eventIDs: records.map(\.id), accessToken: accessToken)) ?? [:]
        return await events(from: records, imageRecordsByEventID: images, accessToken: accessToken, logContext: "org calendar")
    }


    private func fetchOwnerEventImages(eventIDs: [UUID], accessToken: String?) async throws -> [UUID: [SupabaseEventImageRecord]] {
        guard !eventIDs.isEmpty,
              let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_images") else {
            return [:]
        }
        var components = URLComponents(url: restURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "event_id", value: "in.(\(eventIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
            URLQueryItem(name: "order", value: "position.asc")
        ]
        guard let url = components?.url else { return [:] }
        let token = accessToken ?? ""
        let (data, response) = try await session.data(for: token.isEmpty ? request(url: url) : request(url: url, accessToken: token))
        try validate(response)
        return Dictionary(grouping: try decoder.decode([SupabaseEventImageRecord].self, from: data), by: \.eventID)
    }

    func updateEventStatus(id: UUID, status: ListingStatus, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "support_transition_listing_moderation") else {
            throw SupabaseServiceError.notConfigured
        }

        let request = try rpcRequest(
            url: url,
            body: SupportListingModerationRequest(
                eventID: id,
                targetStatus: status,
                reason: nil
            ),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchMemberProfilesForSupport(accessToken: String) async throws -> [BusinessProfileRecord] {
        guard let url = rpcURL(functionName: "support_member_profiles") else {
            throw SupabaseServiceError.notConfigured
        }

        let request = try rpcRequest(url: url, body: EmptyRPCRequest(), accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try decoder.decode([BusinessProfileRecord].self, from: data)
    }

    func fetchMemberSubscriptionsForSupport(accessToken: String) async throws -> [BusinessSubscriptionRecord] {
        guard var components = businessSubscriptionsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "updated_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try decoder.decode([BusinessSubscriptionRecord].self, from: data)
    }

    func updateMemberProfileStatus(id: UUID, status: BusinessProfileStatus, reason: String?, supportNote: String?, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "support_transition_member_profile") else {
            throw SupabaseServiceError.notConfigured
        }

        let request = try rpcRequest(
            url: url,
            body: SupportMemberProfileTransitionRequest(
                profileID: id,
                targetStatus: status,
                reason: reason?.trimmed ?? "",
                supportNote: supportNote?.trimmed ?? ""
            ),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchSupportChangeRequests(accessToken: String) async throws -> [EventChangeRequest] {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,events(*,event_images(*))"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await changeRequests(from: try decoder.decode([SupabaseEventChangeRequestRecord].self, from: data), accessToken: accessToken)
    }

    func fetchSupportRequests(accessToken: String) async throws -> [SupportRequestRecord] {
        guard var components = supportRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response, data: data)
        return try decoder.decode([SupabaseSupportRequestRecord].self, from: data).map(\.supportRequest)
    }

    func updateSupportRequest(id: UUID, status: SupportRequestStatus, supportNote: String?, accessToken: String) async throws {
        guard var components = supportRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(
            SupportRequestUpdate(
                status: status,
                supportNote: supportNote?.trimmed.nilIfEmpty
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func supportCompleteAccountDeletion(requestID: UUID, supportNote: String?, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "support_complete_account_deletion") else {
            throw SupabaseServiceError.notConfigured
        }
        let request = try rpcRequest(
            url: url,
            body: SupportCompleteAccountDeletionRequest(requestID: requestID, supportNote: supportNote),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func fetchEventReportsForSupport(accessToken: String) async throws -> [EventReportRecord] {
        guard var components = eventReportsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,events(*,event_images(*))"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return []
        }
        try validate(response, data: data)
        return await eventReports(from: try decoder.decode([SupabaseEventReportRecord].self, from: data), accessToken: accessToken)
    }

    func updateEventReport(id: UUID, status: EventReportStatus, supportNote: String?, accessToken: String) async throws {
        guard var components = eventReportsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(
            EventReportUpdate(
                status: status,
                supportNote: supportNote?.trimmed.nilIfEmpty,
                reviewedAt: Date()
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func supportApproveChangeRequest(_ request: EventChangeRequest, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        switch request.changeType {
        case .editRequest:
            try await supportApplyEventChangeRequest(id: request.id, reviewReason: reviewReason, supportNote: supportNote, accessToken: accessToken)
        case .removalRequest:
            try await updateEventStatus(id: request.eventID, status: .archived, accessToken: accessToken)
            try await updateChangeRequest(
                id: request.id,
                update: EventChangeRequestUpdate(status: .applied, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: Date()),
                accessToken: accessToken
            )
        }
    }

    private func supportApplyEventChangeRequest(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        guard let url = rpcURL(functionName: "support_apply_event_change_request") else {
            throw SupabaseServiceError.notConfigured
        }

        let request = try rpcRequest(
            url: url,
            body: SupportApplyEventChangeRequest(
                changeRequestID: id,
                reviewReason: reviewReason,
                supportNote: supportNote?.trimmed.nilIfEmpty
            ),
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func supportRejectChangeRequest(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        try await updateChangeRequest(
            id: id,
            update: EventChangeRequestUpdate(status: .rejected, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: nil),
            accessToken: accessToken
        )
    }

    func supportMarkApplied(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        try await updateChangeRequest(
            id: id,
            update: EventChangeRequestUpdate(status: .applied, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: Date()),
            accessToken: accessToken
        )
    }

    private func insertChangeRequest(_ insert: EventChangeRequestInsert, accessToken: String) async throws {
        guard let url = eventChangeRequestsURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(insert)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func changeRequests(from records: [SupabaseEventChangeRequestRecord], accessToken: String?) async -> [EventChangeRequest] {
        var requests: [EventChangeRequest] = []

        for record in records {
            let eventImages = record.event?.eventImages ?? []
            let signedImages = await signedEventImages(from: eventImages, eventID: record.eventID, accessToken: accessToken)
            requests.append(record.changeRequest(event: record.event?.localEvent(images: signedImages)))
        }

        return requests
    }

    private func eventReports(from records: [SupabaseEventReportRecord], accessToken: String?) async -> [EventReportRecord] {
        var reports: [EventReportRecord] = []

        for record in records {
            let eventImages = record.event?.eventImages ?? []
            let signedImages = await signedEventImages(from: eventImages, eventID: record.eventID, accessToken: accessToken)
            reports.append(record.eventReport(event: record.event?.localEvent(images: signedImages)))
        }

        return reports
    }

    private func updateEvent(id: UUID, proposedChanges: [String: EventChangeValue], accessToken: String) async throws {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(proposedChanges)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func updateChangeRequest(id: UUID, update: EventChangeRequestUpdate, accessToken: String) async throws {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(update)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func uploadStorageObject(data: Data, storagePath: String, mimeType: String, accessToken: String) async throws {
        try await uploadStorageObject(data: data, bucket: "listing-images", storagePath: storagePath, mimeType: mimeType, accessToken: accessToken)
    }

    private func uploadStorageObject(data: Data, bucket: String, storagePath: String, mimeType: String, accessToken: String) async throws {
        guard let url = storageObjectURL(bucket: bucket, storagePath: storagePath) else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        try validatePhotoUploadResponse(response, data: responseData, step: "storage upload", storagePath: storagePath)
    }

    private func insertEventImageMetadata(
        image: ListingPhotoUpload,
        eventID: UUID,
        storagePath: String,
        position: Int,
        accessToken: String
    ) async throws {
        guard let url = eventImagesURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        let metadata = EventImageInsert(
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            mimeType: image.mimeType,
            byteSize: image.byteSize,
            width: image.width,
            height: image.height
        )

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(metadata)

        let (responseData, response) = try await session.data(for: request)
        try validatePhotoUploadResponse(response, data: responseData, step: "event_images insert", storagePath: storagePath)
    }

    private func signedEventImages(from records: [SupabaseEventImageRecord], eventID: UUID, accessToken: String?) async -> [EventImage] {
        var images: [EventImage] = []

        for record in records.sorted(by: { $0.position < $1.position }) {
            let signedURL: URL?
            do {
                signedURL = try await signedStorageURL(storagePath: record.storagePath, accessToken: accessToken)
            } catch {
                signedURL = nil
                debugPhotoUpload(
                    step: "signed URL",
                    message: "failed event=\(eventID.redactedForLog), image=\(record.id.redactedForLog), path=\(record.storagePath), error=\(error.localizedDescription)"
                )
            }

            images.append(record.eventImage(signedURL: signedURL))
        }

        return images
    }

    private func signedStorageURL(storagePath: String, accessToken: String?) async throws -> URL? {
        guard let url = storageSignURL(storagePath: storagePath) else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(StorageSignRequest(expiresIn: 3600))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            debugPhotoUpload(step: "signed URL", message: "invalid response, path=\(storagePath)")
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable response body>"
            debugPhotoUpload(step: "signed URL", message: "failed status=\(httpResponse.statusCode), path=\(storagePath), body=\(body)")
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, body)
        }

        let signed = try decoder.decode(StorageSignedURLResponse.self, from: data)
        guard let signedURL = signed.signedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !signedURL.isEmpty else {
            debugPhotoUpload(step: "signed URL", message: "empty response status=\(httpResponse.statusCode), path=\(storagePath)")
            return nil
        }

        return absoluteSignedStorageURL(from: signedURL)
    }

    private func absoluteSignedStorageURL(from signedURL: String) -> URL? {
        if let absoluteURL = URL(string: signedURL), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let projectURL = SupabaseConfiguration.projectURL else {
            return nil
        }

        let path = signedURL.hasPrefix("/") ? String(signedURL.dropFirst()) : signedURL

        if path.hasPrefix("storage/v1/") {
            return URL(string: path, relativeTo: projectURL)?.absoluteURL
        }

        if path.hasPrefix("object/") {
            return URL(string: "storage/v1/\(path)", relativeTo: projectURL)?.absoluteURL
        }

        return URL(string: "storage/v1/object/sign/listing-images/\(path)", relativeTo: projectURL)?.absoluteURL
    }

    private var eventsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("events"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var publicEventsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent(Self.publicEventsResource),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventImagesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_images"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var publicEventImagesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent(Self.publicEventImagesResource),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventChangeRequestsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_change_requests"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var supportRequestsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("support_requests"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventReportsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_reports"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var userPushTokensURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("user_push_tokens"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var userNotificationsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("user_notifications"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var businessProfilesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("business_profiles"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var publicMemberProfilesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent(Self.publicMemberProfileResource),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var publicHostDirectoryURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent(Self.publicHostDirectoryResource),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var businessSubscriptionsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("business_subscriptions"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var memberFollowsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("member_follows"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var noticeReadsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("notice_reads"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }
        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var memberNoticesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("member_notices"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var businessSponsorRequestsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("business_sponsor_requests"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var locationScopesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("location_scopes"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var locationScopeEdgesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("location_scope_edges"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var locationAliasSearchTermsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("location_alias_search_terms"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var publishedEventLocationTargetsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("published_event_location_targets"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventPollResponsesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_poll_responses"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventAnalyticsDailyURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_analytics_daily"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var activeEventPromotionsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("active_event_promotions"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private func rpcURL(functionName: String) -> URL? {
        guard SupabaseConfiguration.isConfigured else { return nil }
        return SupabaseConfiguration.restURL?
            .appendingPathComponent("rpc")
            .appendingPathComponent(functionName)
    }

    private static func localTownMatches(for slug: String) -> Set<CoastTown> {
        LocationScope.scope(id: slug)?.townMatches ?? []
    }

    private static func locationSearchTerms(for slug: String, aliases: [String]) -> [String] {
        let localTerms = LocationScope.scope(id: slug)?.searchTerms ?? []
        return Array(Set([slug] + aliases + localTerms)).sorted()
    }

    private func storageObjectURL(storagePath: String) -> URL? {
        storageObjectURL(bucket: "listing-images", storagePath: storagePath)
    }

    private func storageObjectURL(bucket: String, storagePath: String) -> URL? {
        storagePath.split(separator: "/").reduce(
            SupabaseConfiguration.storageURL?
            .appendingPathComponent("object")
            .appendingPathComponent(bucket)
        ) { partialURL, pathPart in
            partialURL?.appendingPathComponent(String(pathPart))
        }
    }

    private func publicStorageURL(bucket: String, storagePath: String) -> URL? {
        storagePath.split(separator: "/").reduce(
            SupabaseConfiguration.storageURL?
            .appendingPathComponent("object")
            .appendingPathComponent("public")
            .appendingPathComponent(bucket)
        ) { partialURL, pathPart in
            partialURL?.appendingPathComponent(String(pathPart))
        }
    }

    private func storageSignURL(storagePath: String) -> URL? {
        storagePath.split(separator: "/").reduce(
            SupabaseConfiguration.storageURL?
            .appendingPathComponent("object")
            .appendingPathComponent("sign")
            .appendingPathComponent("listing-images")
        ) { partialURL, pathPart in
            partialURL?.appendingPathComponent(String(pathPart))
        }
    }

    private func request(url: URL, accessToken: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func rpcRequest<Body: Encodable>(url: URL, body: Body, accessToken: String) throws -> URLRequest {
        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, nil)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
    }

    private func validatePhotoUploadResponse(_ response: URLResponse, data: Data, step: String, storagePath: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            debugPhotoUpload(step: step, message: "invalid response, path=\(storagePath)")
            throw SupabaseServiceError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return
        }

        let body = String(data: data, encoding: .utf8) ?? "<unreadable response body>"
        debugPhotoUpload(step: step, message: "failed status=\(httpResponse.statusCode), path=\(storagePath), body=\(body)")
        throw SupabaseServiceError.requestFailed(httpResponse.statusCode, body)
    }

    private func debugPhotoUpload(step: String, message: String) {
        #if DEBUG
        print("[PhotoUpload] \(step): \(message)")
        #endif
    }

    private func debugService(step: String, message: String) {
        #if DEBUG
        print("[SupabaseEventService] \(step): \(message)")
        #endif
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISODateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct SupabaseEventRecord: Decodable {
    let id: UUID
    let title: String
    let category: String
    let town: String
    let locationDisplayName: String?
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String?
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let businessProfileID: UUID?
    let organisationName: String?
    let submittedBy: UUID?
    let isFeatured: Bool
    let isPaidPush: Bool
    let status: String
    let listingKind: String?
    let pollQuestion: String?
    let pollOptions: [String]?
    let pollAllowsCustomAnswer: Bool?
    let unverifiedUserListing: Bool?
    let eventImages: [SupabaseEventImageRecord]?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case town
        case locationDisplayName = "location_display_name"
        case venue
        case startAt = "start_at"
        case endAt = "end_at"
        case priceLabel = "price_label"
        case isFree = "is_free"
        case audience
        case shortDescription = "short_description"
        case longDescription = "long_description"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
        case contactEmail = "contact_email"
        case businessProfileID = "business_profile_id"
        case organisationName = "organisation_name"
        case submittedBy = "submitted_by"
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case status
        case listingKind = "listing_kind"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case pollAllowsCustomAnswer = "poll_allows_custom_answer"
        case unverifiedUserListing = "unverified_user_listing"
        case eventImages = "event_images"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func localEvent(images: [EventImage] = []) -> LocalEvent? {
        guard let category = EventCategory(databaseValue: category),
              let listingStatus = ListingStatus(rawValue: status) else {
            return nil
        }
        let matchedTown = CoastTown(databaseValue: town)
        let townValue = matchedTown ?? .all
        let resolvedLocationName = locationDisplayName?.nilIfEmpty
            ?? (matchedTown == nil ? town.nilIfEmpty : nil)

        let parsedPollDetails = PollDetails(reviewText: longDescription)
        let resolvedPollDetails = pollQuestion.map {
            PollDetails(
                question: $0,
                options: pollOptions ?? [],
                allowsCustomAnswer: pollAllowsCustomAnswer ?? false
            )
        } ?? parsedPollDetails
        let resolvedListingKind = listingKind.flatMap(ListingKind.init(rawValue:)) ?? (resolvedPollDetails != nil ? .poll : .event)

        return LocalEvent(
            id: id,
            title: title,
            category: category,
            town: townValue,
            locationDisplayName: resolvedLocationName,
            venue: venue,
            startDate: startAt,
            endDate: endAt,
            priceLabel: priceLabel,
            isFree: isFree,
            audience: audience,
            shortDescription: shortDescription,
            longDescription: longDescription ?? shortDescription,
            contactName: contactName,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            businessProfileID: businessProfileID,
            organisationName: organisationName,
            submittedBy: submittedBy,
            isFeatured: isFeatured,
            isPaidPush: isPaidPush,
            listingStatus: listingStatus,
            listingKind: resolvedListingKind,
            pollDetails: resolvedPollDetails,
            unverifiedUserListing: unverifiedUserListing ?? false,
            images: images,
            createdAt: createdAt ?? startAt,
            updatedAt: updatedAt
        )
    }
}

struct SaveMemberPublicProfileRequest: Encodable {
    let profileID: UUID
    let displayName: String
    let areaScopeID: String
    let bio: String?
    let publicContactName: String?
    let publicContactEmail: String?
    let publicPhone: String?
    let publicLocationText: String?
    let publicAddress: String?
    let publicWebsite: String?
    let avatarImagePath: String?
    let heroImagePath: String?
    let avatarImagePositionX: Double
    let avatarImagePositionY: Double
    let heroImagePositionX: Double
    let heroImagePositionY: Double

    init(profileID: UUID, draft: PublicMemberProfileDraft) {
        self.profileID = profileID
        displayName = draft.displayName.trimmed
        areaScopeID = draft.areaScopeID.trimmed
        bio = draft.bio.trimmed.nilIfEmpty
        publicContactName = draft.publicContactName.trimmed.nilIfEmpty
        publicContactEmail = draft.publicContactEmail.trimmed.nilIfEmpty
        publicPhone = draft.publicPhone.trimmed.nilIfEmpty
        publicLocationText = draft.publicLocationText.trimmed.nilIfEmpty
        publicAddress = draft.publicAddress.trimmed.nilIfEmpty
        publicWebsite = draft.publicWebsite.trimmed.nilIfEmpty
        avatarImagePath = draft.avatarImagePath?.trimmed.nilIfEmpty
        heroImagePath = draft.heroImagePath?.trimmed.nilIfEmpty
        avatarImagePositionX = draft.avatarImagePositionX
        avatarImagePositionY = draft.avatarImagePositionY
        heroImagePositionX = draft.heroImagePositionX
        heroImagePositionY = draft.heroImagePositionY
    }

    enum CodingKeys: String, CodingKey {
        case profileID = "p_business_profile_id"
        case displayName = "p_display_name"
        case areaScopeID = "p_area_scope_id"
        case bio = "p_bio"
        case publicContactName = "p_public_contact_name"
        case publicContactEmail = "p_public_contact_email"
        case publicPhone = "p_public_phone"
        case publicLocationText = "p_public_location_text"
        case publicAddress = "p_public_address"
        case publicWebsite = "p_public_website"
        case avatarImagePath = "p_avatar_image_path"
        case heroImagePath = "p_hero_image_path"
        case avatarImagePositionX = "p_avatar_image_position_x"
        case avatarImagePositionY = "p_avatar_image_position_y"
        case heroImagePositionX = "p_hero_image_position_x"
        case heroImagePositionY = "p_hero_image_position_y"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(areaScopeID, forKey: .areaScopeID)
        try container.encodeNullable(bio, forKey: .bio)
        try container.encodeNullable(publicContactName, forKey: .publicContactName)
        try container.encodeNullable(publicContactEmail, forKey: .publicContactEmail)
        try container.encodeNullable(publicPhone, forKey: .publicPhone)
        try container.encodeNullable(publicLocationText, forKey: .publicLocationText)
        try container.encodeNullable(publicAddress, forKey: .publicAddress)
        try container.encodeNullable(publicWebsite, forKey: .publicWebsite)
        try container.encodeNullable(avatarImagePath, forKey: .avatarImagePath)
        try container.encodeNullable(heroImagePath, forKey: .heroImagePath)
        try container.encode(avatarImagePositionX, forKey: .avatarImagePositionX)
        try container.encode(avatarImagePositionY, forKey: .avatarImagePositionY)
        try container.encode(heroImagePositionX, forKey: .heroImagePositionX)
        try container.encode(heroImagePositionY, forKey: .heroImagePositionY)
    }
}

private struct OwnerArchiveListingRequest: Encodable {
    let eventID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
    }
}

private struct ConfirmMemberPublicContactRequest: Encodable {
    let profileID: UUID
    let revision: UUID

    enum CodingKeys: String, CodingKey {
        case profileID = "p_business_profile_id"
        case revision = "p_public_contact_revision"
    }
}

private struct SupportUnpublishMemberPublicProfileRequest: Encodable {
    let profileID: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case profileID = "p_business_profile_id"
        case reason = "p_reason"
    }
}

struct PollResponseUpsert: Encodable {
    let eventID: UUID
    let respondentID: UUID
    let selectedOption: String?
    let customAnswer: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case respondentID = "respondent_id"
        case selectedOption = "selected_option"
        case customAnswer = "custom_answer"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(respondentID, forKey: .respondentID)
        if let selectedOption {
            try container.encode(selectedOption, forKey: .selectedOption)
        } else {
            try container.encodeNil(forKey: .selectedOption)
        }
        if let customAnswer {
            try container.encode(customAnswer, forKey: .customAnswer)
        } else {
            try container.encodeNil(forKey: .customAnswer)
        }
    }
}

struct PollCountsRequest: Encodable {
    let eventID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
    }
}

struct EventAnalyticsRecordRequest: Encodable {
    let eventID: UUID
    let eventType: String
    let source: String?
    let locationScopeSlug: String?
    let sessionID: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case eventType = "p_event_type"
        case source = "p_source"
        case locationScopeSlug = "p_location_scope_slug"
        case sessionID = "p_session_id"
        case metadata = "p_metadata"
    }
}

struct AppOpenRecordRequest: Encodable {
    let installationID: String

    enum CodingKeys: String, CodingKey {
        case installationID = "p_session_id"
    }
}

struct SupportRequestSubmitRequest: Encodable {
    let topic: String
    let message: String
    let listingReference: String?

    enum CodingKeys: String, CodingKey {
        case topic = "p_topic"
        case message = "p_message"
        case listingReference = "p_listing_reference"
    }
}

struct EventReportSubmitRequest: Encodable {
    let eventID: UUID
    let category: EventReportCategory
    let details: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case category = "p_category"
        case details = "p_details"
    }
}

struct EventReportUpdate: Encodable {
    let status: EventReportStatus
    let supportNote: String?
    let reviewedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case supportNote = "support_note"
        case reviewedAt = "reviewed_at"
    }
}

struct SupportListingModerationRequest: Encodable {
    let eventID: UUID
    let targetStatus: String
    let reason: String?

    init(eventID: UUID, targetStatus: ListingStatus, reason: String?) {
        self.eventID = eventID
        self.targetStatus = targetStatus.rawValue
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case targetStatus = "p_target_status"
        case reason = "p_reason"
    }
}

struct SupportApplyEventChangeRequest: Encodable {
    let changeRequestID: UUID
    let reviewReason: String
    let supportNote: String?

    init(changeRequestID: UUID, reviewReason: EventReviewReason, supportNote: String?) {
        self.changeRequestID = changeRequestID
        self.reviewReason = reviewReason.rawValue
        self.supportNote = supportNote
    }

    enum CodingKeys: String, CodingKey {
        case changeRequestID = "p_change_request_id"
        case reviewReason = "p_review_reason"
        case supportNote = "p_support_note"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeRequestID, forKey: .changeRequestID)
        try container.encode(reviewReason, forKey: .reviewReason)
        try container.encodeNullable(supportNote, forKey: .supportNote)
    }
}

struct SupportCompleteAccountDeletionRequest: Encodable {
    let requestID: UUID
    let supportNote: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case supportNote = "p_support_note"
    }
}

struct SupportRequestUpdate: Encodable {
    let status: SupportRequestStatus
    let supportNote: String?

    enum CodingKeys: String, CodingKey {
        case status
        case supportNote = "support_note"
    }
}

struct SupabaseSupportRequestRecord: Decodable {
    let id: UUID
    let submittedBy: UUID?
    let topic: String
    let listingReference: String?
    let message: String
    let status: SupportRequestStatus
    let supportNote: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case submittedBy = "submitted_by"
        case topic
        case listingReference = "listing_reference"
        case message
        case status
        case supportNote = "support_note"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var supportRequest: SupportRequestRecord {
        SupportRequestRecord(
            id: id,
            submittedBy: submittedBy,
            topic: topic,
            listingReference: listingReference,
            message: message,
            status: status,
            supportNote: supportNote,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SupabaseEventReportRecord: Decodable {
    let id: UUID
    let eventID: UUID
    let reporterUserID: UUID?
    let category: EventReportCategory
    let details: String?
    let status: EventReportStatus
    let supportNote: String?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let event: SupabaseEventRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case reporterUserID = "reporter_user_id"
        case category
        case details
        case status
        case supportNote = "support_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case event = "events"
    }

    func eventReport(event: LocalEvent?) -> EventReportRecord {
        EventReportRecord(
            id: id,
            eventID: eventID,
            reporterUserID: reporterUserID,
            category: category,
            details: details,
            status: status,
            supportNote: supportNote,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            event: event
        )
    }
}

struct SupabaseListingAnalyticsDailyRecord: Decodable {
    let impressions: Int
    let detailViews: Int
    let interestedTaps: Int
    let goingTaps: Int
    let saveTaps: Int
    let shareTaps: Int
    let pollAnswers: Int
    let promotionImpressions: Int

    enum CodingKeys: String, CodingKey {
        case impressions
        case detailViews = "detail_views"
        case interestedTaps = "interested_taps"
        case goingTaps = "going_taps"
        case saveTaps = "save_taps"
        case shareTaps = "share_taps"
        case pollAnswers = "poll_answers"
        case promotionImpressions = "promotion_impressions"
    }
}

struct SupabaseActiveEventPromotionRecord: Decodable {
    let eventID: UUID
    let tier: String
    let placement: String
    let startsAt: Date
    let endsAt: Date
    let paidAt: Date?
    let placementRank: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case tier
        case placement
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case paidAt = "paid_at"
        case placementRank = "placement_rank"
    }

    func sortsBefore(_ other: SupabaseActiveEventPromotionRecord) -> Bool {
        if placementRank != other.placementRank {
            return placementRank > other.placementRank
        }

        return (paidAt ?? .distantFuture) < (other.paidAt ?? .distantFuture)
    }
}

struct PollResponseCountRecord: Decodable {
    let optionText: String
    let responseCount: Int

    enum CodingKeys: String, CodingKey {
        case optionText = "option_text"
        case responseCount = "response_count"
    }
}

struct SupabasePollResponseRecord: Decodable {
    let selectedOption: String?
    let customAnswer: String?
    let updatedAt: Date?

    var pollUserResponse: PollUserResponse {
        PollUserResponse(
            selectedOption: selectedOption,
            customAnswer: customAnswer,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case selectedOption = "selected_option"
        case customAnswer = "custom_answer"
        case updatedAt = "updated_at"
    }
}

struct SupabasePollCustomResponseRecord: Decodable {
    let id: UUID
    let customAnswer: String
    let createdAt: Date

    var pollCustomResponse: PollCustomResponse {
        PollCustomResponse(id: id, customAnswer: customAnswer, createdAt: createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case customAnswer = "custom_answer"
        case createdAt = "created_at"
    }
}

struct SupabaseEventImageRecord: Decodable {
    let id: UUID
    let eventID: UUID
    let storagePath: String
    let position: Int
    let mimeType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case storagePath = "storage_path"
        case position
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case width
        case height
    }

    func eventImage(signedURL: URL?) -> EventImage {
        EventImage(
            id: id,
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            mimeType: mimeType,
            byteSize: byteSize,
            width: width,
            height: height,
            signedURL: signedURL
        )
    }
}

struct SupabaseLocationScopeRecord: Decodable {
    let slug: String
    let name: String
    let scopeType: String
    let subtitle: String?
    let sortPriority: Int

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case scopeType = "scope_type"
        case subtitle
        case sortPriority = "sort_priority"
    }
}

struct NearestLocationScopeRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let maxResults: Int

    enum CodingKeys: String, CodingKey {
        case latitude = "p_latitude"
        case longitude = "p_longitude"
        case maxResults = "p_max_results"
    }
}

struct SupabaseNearestLocationScopeRecord: Decodable {
    let slug: String
    let name: String
    let scopeType: String
    let subtitle: String?
    let distanceKilometers: Double
    let isWithinRadius: Bool

    var match: NearestLocationScopeMatch? {
        guard let kind = LocationScopeKind(databaseValue: scopeType) else { return nil }

        return NearestLocationScopeMatch(
            id: slug,
            name: name,
            kind: kind,
            subtitle: subtitle,
            distanceKilometers: distanceKilometers,
            isWithinRadius: isWithinRadius
        )
    }

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case scopeType = "scope_type"
        case subtitle
        case distanceKilometers = "distance_kilometers"
        case isWithinRadius = "is_within_radius"
    }
}

struct SupabaseLocationScopeEdgeRecord: Decodable {
    let childSlug: String
    let parentSlug: String
    let relationshipType: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case childSlug = "child_slug"
        case parentSlug = "parent_slug"
        case relationshipType = "relationship_type"
        case sortOrder = "sort_order"
    }
}

struct SupabaseLocationAliasRecord: Decodable {
    let locationSlug: String
    let alias: String

    enum CodingKeys: String, CodingKey {
        case locationSlug = "location_slug"
        case alias
    }
}

struct SupabasePublishedEventLocationTargetRecord: Decodable {
    let eventID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
    }
}

struct SupabaseEventChangeRequestRecord: Decodable {
    let id: UUID
    let eventID: UUID
    let requestedBy: UUID
    let changeType: EventChangeType
    let status: EventChangeRequestStatus
    let proposedChanges: [String: EventChangeValue]
    let requesterNote: String?
    let reviewReason: EventReviewReason?
    let supportNote: String?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let appliedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let event: SupabaseEventRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case requestedBy = "requested_by"
        case changeType = "change_type"
        case status
        case proposedChanges = "proposed_changes"
        case requesterNote = "requester_note"
        case reviewReason = "review_reason"
        case supportNote = "support_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case appliedAt = "applied_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case event = "events"
    }

    func changeRequest(event: LocalEvent?) -> EventChangeRequest {
        EventChangeRequest(
            id: id,
            eventID: eventID,
            requestedBy: requestedBy,
            changeType: changeType,
            status: status,
            proposedChanges: proposedChanges,
            requesterNote: requesterNote,
            reviewReason: reviewReason,
            supportNote: supportNote,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            appliedAt: appliedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            event: event
        )
    }
}

struct SupabaseUserNotificationRecord: Decodable {
    let id: UUID
    let userID: UUID
    let title: String
    let body: String
    let notificationType: String
    let relatedTable: String?
    let relatedID: UUID?
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case body
        case notificationType = "notification_type"
        case relatedTable = "related_table"
        case relatedID = "related_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var record: UserNotificationRecord {
        UserNotificationRecord(
            id: id,
            userID: userID,
            title: title,
            body: body,
            notificationType: notificationType,
            relatedTable: relatedTable,
            relatedID: relatedID,
            readAt: readAt,
            createdAt: createdAt
        )
    }
}

struct EventChangeRequestInsert: Encodable {
    let eventID: UUID
    let requestedBy: UUID
    let changeType: EventChangeType
    let status: EventChangeRequestStatus = .pending
    let proposedChanges: [String: EventChangeValue]
    let requesterNote: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case requestedBy = "requested_by"
        case changeType = "change_type"
        case status
        case proposedChanges = "proposed_changes"
        case requesterNote = "requester_note"
    }
}

struct EventChangeRequestUpdate: Encodable {
    let status: EventChangeRequestStatus
    let reviewReason: EventReviewReason
    let supportNote: String?
    let reviewedAt: Date?
    let appliedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case reviewReason = "review_reason"
        case supportNote = "support_note"
        case reviewedAt = "reviewed_at"
        case appliedAt = "applied_at"
    }
}

struct OwnerPasswordLogin: Encodable {
    let email: String
    let password: String
}

struct OwnerRefreshLogin: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct SupabaseAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct AuthUserMetadata: Decodable, Hashable {
    let fullNameSnake: String?
    let fullNameCamel: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case fullNameSnake = "full_name"
        case fullNameCamel = "fullName"
        case name
    }

    var resolvedName: String? {
        let raw = (fullNameSnake ?? fullNameCamel ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}

struct SupabaseAuthUser: Decodable, Hashable {
    let id: UUID?
    let email: String?
    let emailConfirmedAt: String?
    let confirmedAt: String?

    var isEmailVerified: Bool {
        emailConfirmedAt != nil || confirmedAt != nil
    }

    enum CodingKeys: String, CodingKey {
        case userMetadata = "user_metadata"
        case id
        case email
        case emailConfirmedAt = "email_confirmed_at"
        case confirmedAt = "confirmed_at"
    }

    let userMetadata: AuthUserMetadata?

    var fullName: String? {
        let raw = userMetadata?.resolvedName ?? ""
        return raw.isEmpty ? nil : raw
    }
}

struct OwnerStatusUpdate: Encodable {
    let status: String
}

struct InsertedEventResponse: Decodable {
    let id: UUID
}

struct EventImageInsert: Encodable {
    let eventID: UUID
    let storagePath: String
    let position: Int
    let mimeType: String
    let byteSize: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case storagePath = "storage_path"
        case position
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case width
        case height
    }
}

struct StorageSignRequest: Encodable {
    let expiresIn: Int
}

struct StorageSignedURLResponse: Decodable {
    let signedURL: String?

    enum CodingKeys: String, CodingKey {
        case signedURL
        case signedUrl
        case url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signedURL = try c.decodeIfPresent(String.self, forKey: .signedURL)
            ?? c.decodeIfPresent(String.self, forKey: .signedUrl)
            ?? c.decodeIfPresent(String.self, forKey: .url)
    }
}

nonisolated private struct EmptyRPCRequest: Encodable {}

struct BusinessProfileSaveRequest: Encodable {
    let businessName: String
    let organisationType: String?
    let contactName: String?
    let contactEmail: String
    let phone: String?
    let address: String?
    let website: String?
    let about: String?
    let areaScopeID: String
    let selectedPlanID: String
    let heroImageURL: String?
    let avatarImageURL: String?
    let heroImagePositionX: Double
    let heroImagePositionY: Double
    let avatarImagePositionX: Double
    let avatarImagePositionY: Double

    init(draft: BusinessProfileDraft) {
        self.businessName = draft.name.trimmed
        self.organisationType = draft.organisationType?.rawValue
        self.contactName = draft.contactName.trimmed.nilIfEmpty
        self.contactEmail = MembershipContactEmailValidator.normalized(draft.email)
        self.phone = draft.phone.trimmed.nilIfEmpty
        self.address = draft.address.trimmed.nilIfEmpty
        self.website = draft.website.trimmed.nilIfEmpty
        self.about = draft.about.trimmed.nilIfEmpty
        self.areaScopeID = draft.areaScopeID
        self.selectedPlanID = draft.selectedPlan.rawValue
        self.heroImageURL = draft.heroImageURL.trimmed.nilIfEmpty
        self.avatarImageURL = draft.avatarImageURL.trimmed.nilIfEmpty
        self.heroImagePositionX = draft.heroImagePositionX
        self.heroImagePositionY = draft.heroImagePositionY
        self.avatarImagePositionX = draft.avatarImagePositionX
        self.avatarImagePositionY = draft.avatarImagePositionY
    }

    enum CodingKeys: String, CodingKey {
        case businessName = "p_business_name"
        case organisationType = "p_organisation_type"
        case contactName = "p_contact_name"
        case contactEmail = "p_contact_email"
        case phone = "p_phone"
        case address = "p_address"
        case website = "p_website"
        case about = "p_about"
        case areaScopeID = "p_area_scope_id"
        case selectedPlanID = "p_selected_plan_id"
        case heroImageURL = "p_hero_image_url"
        case avatarImageURL = "p_avatar_image_url"
        case heroImagePositionX = "p_hero_image_position_x"
        case heroImagePositionY = "p_hero_image_position_y"
        case avatarImagePositionX = "p_avatar_image_position_x"
        case avatarImagePositionY = "p_avatar_image_position_y"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(businessName, forKey: .businessName)
        try container.encodeNullable(organisationType, forKey: .organisationType)
        try container.encodeNullable(contactName, forKey: .contactName)
        try container.encode(contactEmail, forKey: .contactEmail)
        try container.encodeNullable(phone, forKey: .phone)
        try container.encodeNullable(address, forKey: .address)
        try container.encodeNullable(website, forKey: .website)
        try container.encodeNullable(about, forKey: .about)
        try container.encode(areaScopeID, forKey: .areaScopeID)
        try container.encode(selectedPlanID, forKey: .selectedPlanID)
        try container.encodeNullable(heroImageURL, forKey: .heroImageURL)
        try container.encodeNullable(avatarImageURL, forKey: .avatarImageURL)
        try container.encode(heroImagePositionX, forKey: .heroImagePositionX)
        try container.encode(heroImagePositionY, forKey: .heroImagePositionY)
        try container.encode(avatarImagePositionX, forKey: .avatarImagePositionX)
        try container.encode(avatarImagePositionY, forKey: .avatarImagePositionY)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

private struct MemberNoticeCreateRequest: Encodable {
    let businessProfileID: UUID
    let ownerUserID: UUID
    let title: String
    let summary: String?
    let body: String?
    let templateStyle: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case businessProfileID = "business_profile_id"
        case ownerUserID = "owner_user_id"
        case title
        case summary
        case body
        case templateStyle = "template_style"
        case status
    }
}

private struct SupportMemberProfileTransitionRequest: Encodable {
    let profileID: UUID
    let targetStatus: BusinessProfileStatus
    let reason: String
    let supportNote: String

    enum CodingKeys: String, CodingKey {
        case profileID = "p_business_profile_id"
        case targetStatus = "p_target_status"
        case reason = "p_reason"
        case supportNote = "p_support_note"
    }
}

private struct MemberFollowLookup: Decodable {
    let id: UUID
}

private struct MemberFollowUpsert: Encodable {
    let userID: UUID
    let businessProfileID: UUID
    let notificationLevel: String = "all"

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case businessProfileID = "business_profile_id"
        case notificationLevel = "notification_level"
    }
}

private struct FoundingSponsorRequestInsert: Encodable {
    let businessProfileID: UUID
    let ownerUserID: UUID
    let packageID: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case businessProfileID = "business_profile_id"
        case ownerUserID = "owner_user_id"
        case packageID = "package_id"
        case notes
    }
}

struct PendingEventInsert: Encodable {
    let title: String
    let category: String
    let town: String
    let primaryLocationScopeID: String?
    let locationDisplayName: String?
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String
    let contactName: String?
    let contactEmail: String?
    let businessProfileID: UUID
    let isFeatured: Bool
    let isPaidPush: Bool
    let unverifiedUserListing: Bool
    let status: String
    let listingKind: String
    let pollQuestion: String?
    let pollOptions: [String]?
    let pollAllowsCustomAnswer: Bool
    private var includeStructuredPollColumns: Bool

    init(draft: PendingListingDraft, businessProfileID: UUID, includeStructuredPollColumns: Bool = true) {
        let start = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: draft.time),
            minute: Calendar.current.component(.minute, from: draft.time),
            second: 0,
            of: draft.date
        ) ?? draft.date

        self.title = draft.title.trimmed
        self.category = draft.category.rawValue
        self.town = draft.town.rawValue
        self.primaryLocationScopeID = UUID(uuidString: draft.locationScopeID) == nil ? nil : draft.locationScopeID
        self.locationDisplayName = draft.locationDisplayName.nilIfEmpty
        self.venue = draft.venue.trimmed.nilIfEmpty ?? "Community poll in \(draft.locationDisplayName)"
        self.startAt = start
        self.endAt = Calendar.current.date(byAdding: .hour, value: 2, to: start) ?? start
        let price = draft.priceLabel.trimmed
        self.priceLabel = price.isEmpty ? "Free" : price
        self.isFree = price.isEmpty || price.localizedCaseInsensitiveContains("free")
        self.audience = "Everyone"
        let resolvedShortDescription = draft.shortDescription.trimmed.nilIfEmpty ?? draft.pollDetails?.question ?? draft.title.trimmed
        self.shortDescription = resolvedShortDescription
        self.longDescription = [
            draft.listingKind == .poll ? "Listing kind: Poll" : nil,
            resolvedShortDescription,
            draft.pollReviewText,
            draft.commercialSignals.isEmpty ? nil : "Review signals: \(draft.commercialSignals.map { $0.label }.joined(separator: ", "))."
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: "\n\n")
        self.contactName = draft.contactName.trimmed.nilIfEmpty
        self.contactEmail = draft.contactEmail.trimmed.nilIfEmpty
        self.businessProfileID = businessProfileID
        self.isFeatured = false
        self.isPaidPush = false
        self.unverifiedUserListing = false
        self.status = ListingStatus.pendingReview.rawValue
        self.listingKind = draft.listingKind.rawValue
        self.pollQuestion = draft.pollDetails?.question
        self.pollOptions = draft.pollDetails?.options
        self.pollAllowsCustomAnswer = draft.pollDetails?.allowsCustomAnswer ?? false
        self.includeStructuredPollColumns = includeStructuredPollColumns
    }

    func withoutStructuredPollColumns() -> PendingEventInsert {
        var copy = self
        copy.includeStructuredPollColumns = false
        return copy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(town, forKey: .town)
        try container.encodeIfPresent(primaryLocationScopeID, forKey: .primaryLocationScopeID)
        try container.encodeIfPresent(locationDisplayName, forKey: .locationDisplayName)
        try container.encode(venue, forKey: .venue)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(priceLabel, forKey: .priceLabel)
        try container.encode(isFree, forKey: .isFree)
        try container.encode(audience, forKey: .audience)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(longDescription, forKey: .longDescription)
        try container.encodeIfPresent(contactName, forKey: .contactName)
        try container.encodeIfPresent(contactEmail, forKey: .contactEmail)
        try container.encode(businessProfileID, forKey: .businessProfileID)
        try container.encode(isFeatured, forKey: .isFeatured)
        try container.encode(isPaidPush, forKey: .isPaidPush)
        try container.encode(unverifiedUserListing, forKey: .unverifiedUserListing)
        try container.encode(status, forKey: .status)

        if includeStructuredPollColumns {
            try container.encode(listingKind, forKey: .listingKind)
            try container.encodeIfPresent(pollQuestion, forKey: .pollQuestion)
            try container.encodeIfPresent(pollOptions, forKey: .pollOptions)
            try container.encode(pollAllowsCustomAnswer, forKey: .pollAllowsCustomAnswer)
        }
    }

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case town
        case primaryLocationScopeID = "primary_location_scope_id"
        case locationDisplayName = "location_display_name"
        case venue
        case startAt = "start_at"
        case endAt = "end_at"
        case priceLabel = "price_label"
        case isFree = "is_free"
        case audience
        case shortDescription = "short_description"
        case longDescription = "long_description"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case businessProfileID = "business_profile_id"
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case unverifiedUserListing = "unverified_user_listing"
        case status
        case listingKind = "listing_kind"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case pollAllowsCustomAnswer = "poll_allows_custom_answer"
    }
}

enum ListingImageStoragePath {
    static func make(userID: UUID, eventID: UUID, imageID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(eventID.uuidString.lowercased())/\(imageID.uuidString.lowercased()).jpg"
    }
}

private extension EventCategory {
    init?(databaseValue: String) {
        self.init(rawValue: databaseValue)
    }
}

private extension CoastTown {
    init?(databaseValue: String) {
        self.init(rawValue: databaseValue)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension UUID {
    var redactedForLog: String {
        "\(uuidString.prefix(8))..."
    }
}
