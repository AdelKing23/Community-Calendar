import Foundation

enum SupabaseServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .requestFailed:
            return "The events service is unavailable."
        }
    }
}

protocol EventListingSubmitting {
    func submitPendingListing(_ draft: PendingListingDraft) async throws
}

protocol PublishedEventFetching {
    func fetchPublishedEvents() async throws -> [LocalEvent]
}

struct SupabaseEventService: EventListingSubmitting, PublishedEventFetching {
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

    func fetchPublishedEvents() async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "end_at", value: "gte.\(Self.isoDateFormatter.string(from: Date()))"),
            URLQueryItem(name: "order", value: "is_paid_push.desc,is_featured.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, _) = try await session.data(for: request(url: url))
        return try decoder.decode([SupabaseEventRecord].self, from: data)
            .compactMap(\.localEvent)
    }

    func submitPendingListing(_ draft: PendingListingDraft) async throws {
        guard let url = eventsURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(PendingEventInsert(draft: draft))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode)
        }
    }

    private var eventsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("events"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfiguration.publishableKey)", forHTTPHeaderField: "Authorization")
        return request
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
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String?
    let contactPhone: String?
    let contactEmail: String?
    let isFeatured: Bool
    let isPaidPush: Bool
    let status: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case town
        case venue
        case startAt = "start_at"
        case endAt = "end_at"
        case priceLabel = "price_label"
        case isFree = "is_free"
        case audience
        case shortDescription = "short_description"
        case longDescription = "long_description"
        case contactPhone = "contact_phone"
        case contactEmail = "contact_email"
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var localEvent: LocalEvent? {
        guard let category = EventCategory(databaseValue: category),
              let town = CoastTown(databaseValue: town),
              let listingStatus = ListingStatus(rawValue: status) else {
            return nil
        }

        return LocalEvent(
            id: id,
            title: title,
            category: category,
            town: town,
            venue: venue,
            startDate: startAt,
            endDate: endAt,
            priceLabel: priceLabel,
            isFree: isFree,
            audience: audience,
            shortDescription: shortDescription,
            longDescription: longDescription ?? shortDescription,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            isFeatured: isFeatured,
            isPaidPush: isPaidPush,
            listingStatus: listingStatus,
            createdAt: createdAt ?? startAt,
            updatedAt: updatedAt
        )
    }
}

struct PendingEventInsert: Encodable {
    let title: String
    let category: String
    let town: String
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String
    let contactName: String
    let contactEmail: String
    let isFeatured: Bool
    let isPaidPush: Bool
    let status: String

    init(draft: PendingListingDraft) {
        let start = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: draft.time),
            minute: Calendar.current.component(.minute, from: draft.time),
            second: 0,
            of: draft.date
        ) ?? draft.date

        self.title = draft.title.trimmed
        self.category = draft.category.rawValue
        self.town = draft.town.rawValue
        self.venue = draft.venue.trimmed
        self.startAt = start
        self.endAt = Calendar.current.date(byAdding: .hour, value: 2, to: start) ?? start
        self.priceLabel = draft.priceLabel.trimmed
        self.isFree = draft.priceLabel.localizedCaseInsensitiveContains("free")
        self.audience = "Everyone"
        self.shortDescription = draft.shortDescription.trimmed
        self.longDescription = draft.shortDescription.trimmed
        self.contactName = draft.contactName.trimmed
        self.contactEmail = draft.contactEmail.trimmed
        self.isFeatured = false
        self.isPaidPush = false
        self.status = ListingStatus.pendingReview.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case town
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
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case status
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
}
