import Foundation

enum CoastTown: String, CaseIterable, Identifiable, Hashable {
    case all = "All Areas"
    case omana = "Omana"
    case whitford = "Whitford"
    case maraetai = "Maraetai"
    case beachlands = "Beachlands"
    case clevedon = "Clevedon"
    case kawakawaBay = "Kawakawa Bay"
    case orerePoint = "Orere Point"
    case hunua = "Hunua"
    case ardmore = "Ardmore"

    var id: String { rawValue }
}

enum EventCategory: String, CaseIterable, Identifiable, Hashable {
    case liveMusic = "Live Music"
    case foodDrink = "Food & Drink"
    case markets = "Markets"
    case kidsFamily = "Kids & Family"
    case sport = "Sport"
    case community = "Community"
    case fundraisers = "Fundraisers"
    case classesWorkshops = "Classes & Workshops"
    case seniors = "Seniors"
    case churchMaraeCultural = "Church / Marae / Cultural"
    case nightlife = "Nightlife"
    case publicNotices = "Public Notices"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .classesWorkshops: return "Workshops"
        case .churchMaraeCultural: return "Culture"
        case .publicNotices: return "Notices"
        case .kidsFamily: return "Family"
        case .foodDrink: return "Food"
        default: return rawValue
        }
    }
}

enum ListingTopic: String, CaseIterable, Identifiable, Hashable {
    case all = "All Topics"
    case kids = "Kids"
    case fitness = "Fitness"
    case health = "Health"
    case business = "Business"
    case social = "Social"
    case markets = "Markets"
    case music = "Music"
    case food = "Food"
    case learning = "Learning"
    case community = "Community"
    case notices = "Notices"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .all: return "All"
        case .kids: return "Kids"
        case .fitness: return "Fitness"
        case .health: return "Health"
        case .business: return "Business"
        case .social: return "Social"
        case .markets: return "Markets"
        case .music: return "Music"
        case .food: return "Food"
        case .learning: return "Classes"
        case .community: return "Community"
        case .notices: return "Notices"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .kids: return "figure.2.and.child.holdinghands"
        case .fitness: return "figure.run"
        case .health: return "cross.case"
        case .business: return "briefcase"
        case .social: return "person.2"
        case .markets: return "basket"
        case .music: return "music.note"
        case .food: return "fork.knife"
        case .learning: return "book"
        case .community: return "heart.text.square"
        case .notices: return "megaphone"
        }
    }

    static func topics(for category: EventCategory) -> [ListingTopic] {
        switch category {
        case .liveMusic:
            return [.music, .social]
        case .foodDrink:
            return [.food, .social, .business]
        case .markets:
            return [.markets, .social, .business]
        case .kidsFamily:
            return [.kids, .social]
        case .sport:
            return [.fitness, .health, .social]
        case .community:
            return [.community, .social]
        case .fundraisers:
            return [.community, .social]
        case .classesWorkshops:
            return [.learning, .business]
        case .seniors:
            return [.community, .social, .health]
        case .churchMaraeCultural:
            return [.community, .social]
        case .nightlife:
            return [.social, .music, .food]
        case .publicNotices:
            return [.notices, .community]
        }
    }

    static func inferredTopics(category: EventCategory, searchableText: String) -> [ListingTopic] {
        var topics = topics(for: category)
        let value = searchableText.lowercased()

        let keywordTopics: [(ListingTopic, [String])] = [
            (.kids, ["kids", "children", "family", "school", "tamariki", "holiday programme"]),
            (.fitness, ["fitness", "run", "walk", "yoga", "pilates", "sport", "training", "gym"]),
            (.health, ["health", "wellbeing", "wellness", "clinic", "support group", "mental health"]),
            (.business, ["business", "shop", "sale", "discount", "ltd", "limited", "cafe", "café", "service", "consultation"]),
            (.markets, ["market", "stall", "craft", "farmers"]),
            (.music, ["music", "band", "gig", "concert", "dj", "karaoke"]),
            (.food, ["food", "dinner", "lunch", "breakfast", "coffee", "cafe", "restaurant"]),
            (.learning, ["class", "course", "workshop", "lesson", "learn"]),
            (.notices, ["notice", "road", "closure", "public notice"])
        ]

        for (topic, keywords) in keywordTopics where keywords.contains(where: value.contains) {
            topics.append(topic)
        }

        return Array(Set(topics)).sorted { $0.rawValue < $1.rawValue }
    }
}

enum DateScope: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"

    var id: String { rawValue }

    func matches(_ event: LocalEvent, now: Date = Date()) -> Bool {
        let calendar = Calendar.current

        switch self {
        case .today:
            return calendar.isDate(event.startDate, inSameDayAs: now)

        case .thisWeek:
            return calendar.isDate(event.startDate, equalTo: now, toGranularity: .weekOfYear)

        case .thisMonth:
            return calendar.isDate(event.startDate, equalTo: now, toGranularity: .month)
        }
    }
}

enum ListingStatus: String, Hashable {
    case pendingReview = "pending_review"
    case published
    case rejected
    case archived
}

enum EventChangeType: String, Hashable, Codable {
    case editRequest = "edit_request"
    case removalRequest = "removal_request"
}

enum EventChangeRequestStatus: String, Hashable, Codable {
    case pending
    case approved
    case rejected
    case cancelled
    case applied
}

enum EventReviewReason: String, CaseIterable, Identifiable, Hashable, Codable {
    case approvedApplied = "approved_applied"
    case needsPayment = "needs_payment"
    case inappropriateWording = "inappropriate_wording"
    case inappropriateImage = "inappropriate_image"
    case wrongCategory = "wrong_category"
    case wrongDateTime = "wrong_date_time"
    case unclearLocation = "unclear_location"
    case duplicateListing = "duplicate_listing"
    case commercialSubmittedAsFree = "commercial_submitted_as_free"
    case promotionUpgradeRequired = "promotion_upgrade_required"
    case notEnoughInformation = "not_enough_information"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .approvedApplied: return "Approved and applied"
        case .needsPayment: return "Needs payment"
        case .inappropriateWording: return "Inappropriate wording"
        case .inappropriateImage: return "Inappropriate image"
        case .wrongCategory: return "Wrong category"
        case .wrongDateTime: return "Wrong date or time"
        case .unclearLocation: return "Unclear location"
        case .duplicateListing: return "Duplicate listing"
        case .commercialSubmittedAsFree: return "Commercial submitted as free"
        case .promotionUpgradeRequired: return "Promotion upgrade required"
        case .notEnoughInformation: return "Not enough information"
        case .other: return "Other"
        }
    }
}

enum EventChangeValue: Hashable, Codable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "Yes" : "No"
        }
    }
}

struct EventChangeRequest: Identifiable, Hashable {
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
    let event: LocalEvent?

    var isPending: Bool {
        status == .pending
    }

    var supportTitle: String {
        switch changeType {
        case .editRequest: return "Edit request"
        case .removalRequest: return "Removal request"
        }
    }
}

struct ListingEditDraft: Hashable {
    var title: String
    var category: EventCategory
    var town: CoastTown
    var venue: String
    var date: Date
    var time: Date
    var priceLabel: String
    var audience: String
    var shortDescription: String
    var longDescription: String
    var contactName: String
    var contactEmail: String
    var contactPhone: String

    init(event: LocalEvent) {
        title = event.title
        category = event.category
        town = event.town
        venue = event.venue
        date = event.startDate
        time = event.startDate
        priceLabel = event.priceLabel
        audience = event.audience
        shortDescription = event.shortDescription
        longDescription = event.longDescription
        contactName = event.contactName ?? ""
        contactEmail = event.contactEmail ?? ""
        contactPhone = event.contactPhone ?? ""
    }

    var canSubmit: Bool {
        [
            title,
            venue,
            shortDescription
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var startDate: Date {
        Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: time),
            minute: Calendar.current.component(.minute, from: time),
            second: 0,
            of: date
        ) ?? date
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .hour, value: 2, to: startDate) ?? startDate
    }

    var proposedChanges: [String: EventChangeValue] {
        let price = priceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrice = price.isEmpty ? "Free" : price
        let description = shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let longText = longDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "category": .string(category.rawValue),
            "town": .string(town.rawValue),
            "venue": .string(venue.trimmingCharacters(in: .whitespacesAndNewlines)),
            "start_at": .string(SupabaseDateEncoding.string(from: startDate)),
            "end_at": .string(SupabaseDateEncoding.string(from: endDate)),
            "price_label": .string(resolvedPrice),
            "is_free": .bool(resolvedPrice.localizedCaseInsensitiveContains("free")),
            "audience": .string(audience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Everyone" : audience.trimmingCharacters(in: .whitespacesAndNewlines)),
            "short_description": .string(description),
            "long_description": .string(longText.isEmpty ? description : longText),
            "contact_name": .string(contactName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "contact_email": .string(contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)),
            "contact_phone": .string(contactPhone.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
    }
}

enum SupabaseDateEncoding {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct EventImage: Identifiable, Hashable {
    let id: UUID
    let eventID: UUID
    let storagePath: String
    let position: Int
    let mimeType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let signedURL: URL?
}

struct ListingPhotoUpload: Identifiable, Hashable {
    let id: UUID
    let data: Data
    let width: Int
    let height: Int
    let mimeType: String

    var byteSize: Int {
        data.count
    }
}

struct LocalEvent: Identifiable, Hashable {
    let id: UUID
    let title: String
    let category: EventCategory
    let town: CoastTown
    let venue: String
    let startDate: Date
    let endDate: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let isFeatured: Bool
    let isPaidPush: Bool
    let listingStatus: ListingStatus
    let unverifiedUserListing: Bool
    let images: [EventImage]
    let createdAt: Date
    let updatedAt: Date?

    var isPubliclyVisible: Bool {
        listingStatus == .published
    }

    var primaryImage: EventImage? {
        images.sorted { $0.position < $1.position }.first
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: EventCategory,
        town: CoastTown,
        venue: String,
        startDate: Date,
        endDate: Date,
        priceLabel: String,
        isFree: Bool,
        audience: String,
        shortDescription: String,
        longDescription: String,
        contactName: String? = nil,
        contactPhone: String?,
        contactEmail: String?,
        isFeatured: Bool,
        isPaidPush: Bool,
        listingStatus: ListingStatus = .published,
        unverifiedUserListing: Bool = false,
        images: [EventImage] = [],
        createdAt: Date = .distantPast,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.town = town
        self.venue = venue
        self.startDate = startDate
        self.endDate = endDate
        self.priceLabel = priceLabel
        self.isFree = isFree
        self.audience = audience
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.isFeatured = isFeatured
        self.isPaidPush = isPaidPush
        self.listingStatus = listingStatus
        self.unverifiedUserListing = unverifiedUserListing
        self.images = images
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var searchableText: String {
        [
            title,
            category.rawValue,
            category.shortLabel,
            town.rawValue,
            venue,
            dayText,
            dateText,
            timeText,
            priceLabel,
            audience,
            shortDescription
        ].joined(separator: " ")
    }

    var inferredTopics: [ListingTopic] {
        ListingTopic.inferredTopics(category: category, searchableText: searchableText)
    }

    func matches(topic: ListingTopic) -> Bool {
        topic == .all || inferredTopics.contains(topic)
    }

    var dayText: String {
        startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var dateText: String {
        startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    var timeText: String {
        let start = startDate.formatted(.dateTime.hour().minute())
        let end = endDate.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    var monthShort: String {
        startDate.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    var dayNumber: String {
        startDate.formatted(.dateTime.day())
    }

    var weekdayShort: String {
        startDate.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    var inferredListingTier: ListingTier {
        let value = priceLabel.lowercased()

        if value.contains("boost + insights") || value.contains("insights") || value.contains("$15") {
            return .boostInsights
        }

        if value.contains("boost") || value.contains("$10") {
            return .boost
        }

        if value.contains("commercial") || value.contains("$5") {
            return .commercialStandard
        }

        return .communityFree
    }
}

struct PendingListingDraft: Hashable {
    var listingTier: ListingTier = .communityFree
    var title = ""
    var category: EventCategory = .community
    var town: CoastTown = .beachlands
    var venue = ""
    var date = Date()
    var time = Date()
    var priceLabel = "Free"
    var contactName = ""
    var contactEmail = ""
    var shortDescription = ""

    var commercialSignals: [ListingCommercialSignal] {
        ListingCommercialSignalDetector.signals(for: self)
    }

    var inferredTopics: [ListingTopic] {
        ListingTopic.inferredTopics(
            category: category,
            searchableText: [title, venue, shortDescription, priceLabel].joined(separator: " ")
        )
    }

    var canSubmit: Bool {
        [
            title,
            venue,
            shortDescription
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
