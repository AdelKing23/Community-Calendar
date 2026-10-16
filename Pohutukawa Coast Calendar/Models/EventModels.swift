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

    var icon: String {
        switch self {
        case .liveMusic: return "music.note"
        case .foodDrink: return "fork.knife"
        case .markets: return "basket"
        case .kidsFamily: return "figure.2.and.child.holdinghands"
        case .sport: return "figure.run"
        case .community: return "person.3"
        case .fundraisers: return "heart"
        case .classesWorkshops: return "book"
        case .seniors: return "figure.walk"
        case .churchMaraeCultural: return "building.columns"
        case .nightlife: return "moon.stars"
        case .publicNotices: return "megaphone"
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
        case .liveMusic: return [.music]
        case .foodDrink: return [.food]
        case .markets: return [.markets]
        case .kidsFamily: return [.kids]
        case .sport: return [.fitness]
        case .community: return [.community]
        case .fundraisers: return [.community]
        case .classesWorkshops: return [.learning]
        case .seniors: return [.health]
        case .churchMaraeCultural: return [.community]
        case .nightlife: return [.social]
        case .publicNotices: return [.notices]
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
            (.notices, ["notice", "road", "closure", "public notice"]),
            (.social, ["social", "meetup", "mixer", "quiz night", "party"])
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
    case upcoming = "Upcoming"

    var id: String { rawValue }

    var chipLabel: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "Week"
        case .thisMonth: return "Month"
        case .upcoming: return "Upcoming"
        }
    }

    func matches(_ event: LocalEvent, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return event.startDate < end && event.endDate >= start
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return event.startDate < end && event.endDate >= start
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return event.startDate < end && event.endDate >= start
        case .upcoming:
            let horizon = calendar.date(byAdding: .day, value: 90, to: now) ?? now
            return event.endDate >= now && event.startDate <= horizon
        }
    }
}

enum ListingStatus: String, Hashable {
    case pendingReview = "pending_review"
    case approvedAwaitingPayment = "approved_awaiting_payment"
    case published
    case rejected
    case archived
    case orgCalendar = "org_calendar"
}

enum ListingKind: String, Hashable, Codable {
    case event
    case poll

    var label: String {
        switch self {
        case .event: return "Listing"
        case .poll: return "Poll"
        }
    }
}

struct PollDetails: Hashable, Codable {
    static let maxOptions = 10
    static let customAnswerLimit = 250

    let question: String
    let options: [String]
    let allowsCustomAnswer: Bool

    var isValid: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
    }

    init(question: String, options: [String], allowsCustomAnswer: Bool) {
        self.question = question
        self.options = Array(
            options
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(Self.maxOptions)
        )
        self.allowsCustomAnswer = allowsCustomAnswer
    }

    init?(reviewText: String?) {
        guard let block = Self.reviewBlock(in: reviewText) else { return nil }

        let lines = block
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var question = ""
        var options: [String] = []
        var isReadingOptions = false
        var allowsCustomAnswer = false

        for line in lines {
            if line.hasPrefix("Question:") {
                question = String(line.dropFirst("Question:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                isReadingOptions = false
            } else if line == "Options:" {
                isReadingOptions = true
            } else if line.hasPrefix("Custom answer:") {
                allowsCustomAnswer = line.localizedCaseInsensitiveContains("Allowed")
                isReadingOptions = false
            } else if isReadingOptions,
                      let dotIndex = line.firstIndex(of: ".") {
                let option = String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !option.isEmpty {
                    options.append(option)
                }
            }
        }

        self.init(question: question, options: options, allowsCustomAnswer: allowsCustomAnswer)

        guard isValid else { return nil }
    }

    static func strippedReviewBlock(from text: String) -> String {
        guard let start = text.range(of: "[POLL]"),
              let end = text.range(of: "[/POLL]", range: start.upperBound..<text.endIndex) else {
            return text
        }

        let stripped = text[..<start.lowerBound] + text[end.upperBound...]
        return stripped
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines) != "Listing kind: Poll" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func reviewBlock(in text: String?) -> String? {
        guard let text,
              let start = text.range(of: "[POLL]"),
              let end = text.range(of: "[/POLL]", range: start.upperBound..<text.endIndex) else {
            return nil
        }

        return String(text[start.upperBound..<end.lowerBound])
    }
}

struct PollResponseCount: Identifiable, Hashable, Codable {
    let optionText: String
    let responseCount: Int

    var id: String { optionText }
}

struct PollResults: Hashable, Codable {
    let counts: [PollResponseCount]

    static let empty = PollResults(counts: [])

    var totalResponses: Int {
        counts.reduce(0) { $0 + $1.responseCount }
    }

    func count(for option: String) -> Int {
        counts.first { $0.optionText == option }?.responseCount ?? 0
    }
}

struct PollUserResponse: Hashable, Codable {
    let selectedOption: String?
    let customAnswer: String?
    let updatedAt: Date?

    var isCustomAnswer: Bool {
        selectedOption == nil && customAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var displayAnswer: String {
        if let selectedOption,
           !selectedOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedOption
        }

        return "Other"
    }
}

struct PollCustomResponse: Identifiable, Hashable, Codable {
    let id: UUID
    let customAnswer: String
    let createdAt: Date
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
        case .needsPayment: return "Needs member access"
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
    var topics: [EventCategory] = []
    let town: CoastTown
    let locationDisplayName: String?
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
    let businessProfileID: UUID?
    let organisationName: String?
    let submittedBy: UUID?
    let isFeatured: Bool
    let isPaidPush: Bool
    let listingStatus: ListingStatus
    let listingKind: ListingKind
    let pollDetails: PollDetails?
    let unverifiedUserListing: Bool
    let images: [EventImage]
    let createdAt: Date
    let updatedAt: Date?
    let activePromotionRank: Int
    let activePromotionPaidAt: Date?

    var isPubliclyVisible: Bool {
        listingStatus == .published
    }

    nonisolated var effectivePromotionRank: Int {
        max(activePromotionRank, isPaidPush ? ListingPromotionPlacement.topTen.rawValue : 0)
    }

    nonisolated var isPromoted: Bool {
        effectivePromotionRank > 0
    }

    nonisolated var promotionBadgeTitle: String {
        if effectivePromotionRank >= ListingPromotionPlacement.priorityFirst.rawValue {
            return "Top Boost"
        }

        if effectivePromotionRank >= ListingPromotionPlacement.topTen.rawValue {
            return "Boosted"
        }

        return "Featured"
    }

    var primaryImage: EventImage? {
        images.sorted { $0.position < $1.position }.first
    }

    var displayLocationName: String {
        let trimmed = locationDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? town.rawValue : trimmed
    }

    var isPoll: Bool {
        listingKind == .poll || pollDetails != nil || longDescription.contains("[POLL]")
    }

    var publicLongDescription: String {
        PollDetails.strippedReviewBlock(from: longDescription)
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: EventCategory,
        town: CoastTown,
        locationDisplayName: String? = nil,
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
        businessProfileID: UUID? = nil,
        organisationName: String? = nil,
        submittedBy: UUID? = nil,
        isFeatured: Bool,
        isPaidPush: Bool,
        listingStatus: ListingStatus = .published,
        listingKind: ListingKind = .event,
        pollDetails: PollDetails? = nil,
        unverifiedUserListing: Bool = false,
        images: [EventImage] = [],
        createdAt: Date = .distantPast,
        updatedAt: Date? = nil,
        activePromotionRank: Int = 0,
        activePromotionPaidAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.town = town
        self.locationDisplayName = locationDisplayName
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
        self.businessProfileID = businessProfileID
        self.organisationName = organisationName
        self.submittedBy = submittedBy
        self.isFeatured = isFeatured
        self.isPaidPush = isPaidPush
        self.listingStatus = listingStatus
        self.listingKind = listingKind
        self.pollDetails = pollDetails
        self.unverifiedUserListing = unverifiedUserListing
        self.images = images
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activePromotionRank = activePromotionRank
        self.activePromotionPaidAt = activePromotionPaidAt
    }

    func applyingActivePromotion(rank: Int, paidAt: Date?) -> LocalEvent {
        LocalEvent(
            id: id,
            title: title,
            category: category,
            town: town,
            locationDisplayName: locationDisplayName,
            venue: venue,
            startDate: startDate,
            endDate: endDate,
            priceLabel: priceLabel,
            isFree: isFree,
            audience: audience,
            shortDescription: shortDescription,
            longDescription: longDescription,
            contactName: contactName,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            businessProfileID: businessProfileID,
            organisationName: organisationName,
            submittedBy: submittedBy,
            isFeatured: isFeatured,
            isPaidPush: isPaidPush,
            listingStatus: listingStatus,
            listingKind: listingKind,
            pollDetails: pollDetails,
            unverifiedUserListing: unverifiedUserListing,
            images: images,
            createdAt: createdAt,
            updatedAt: updatedAt,
            activePromotionRank: rank,
            activePromotionPaidAt: paidAt
        )
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

    var organiserDisplayName: String {
        let org = organisationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !org.isEmpty { return org }
        let trimmedName = contactName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Organisation" : trimmedName
    }

    func matches(topic: EventCategory?) -> Bool {
        guard let topic else { return true }
        if topics.isEmpty { return category == topic }
        return topics.contains(topic)
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

        if value.contains("boost + insights")
            || value.contains("homepage feature")
            || value.contains("weekend feature")
            || value.contains("insights")
            || value.contains("$75")
            || value.contains("$14.99") {
            return .boostInsights
        }

        if value.contains("boost") || value.contains("$35") || value.contains("$9.99") || value.contains("$10") {
            return .boost
        }

        if value.contains("commercial") || value.contains("$15") || value.contains("$4.99") || value.contains("$5") {
            return .commercialStandard
        }

        return .communityFree
    }
}

enum EventFeedOrdering {
    nonisolated static func discovery(_ lhs: LocalEvent, _ rhs: LocalEvent) -> Bool {
        if lhs.effectivePromotionRank != rhs.effectivePromotionRank {
            return lhs.effectivePromotionRank > rhs.effectivePromotionRank
        }

        if lhs.effectivePromotionRank >= ListingPromotionPlacement.priorityFirst.rawValue,
           lhs.activePromotionPaidAt != rhs.activePromotionPaidAt {
            return (lhs.activePromotionPaidAt ?? .distantFuture) < (rhs.activePromotionPaidAt ?? .distantFuture)
        }

        if lhs.isFeatured != rhs.isFeatured {
            return lhs.isFeatured && !rhs.isFeatured
        }

        return lhs.startDate < rhs.startDate
    }

    nonisolated static func board(_ lhs: LocalEvent, _ rhs: LocalEvent) -> Bool {
        if lhs.effectivePromotionRank != rhs.effectivePromotionRank {
            return lhs.effectivePromotionRank > rhs.effectivePromotionRank
        }

        if lhs.effectivePromotionRank >= ListingPromotionPlacement.priorityFirst.rawValue,
           lhs.activePromotionPaidAt != rhs.activePromotionPaidAt {
            return (lhs.activePromotionPaidAt ?? .distantFuture) < (rhs.activePromotionPaidAt ?? .distantFuture)
        }

        if lhs.isFeatured != rhs.isFeatured {
            return lhs.isFeatured && !rhs.isFeatured
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.startDate > rhs.startDate
    }
}

struct PendingListingDraft: Hashable {
    var listingKind: ListingKind = .event
    var listingTier: ListingTier = .communityFree
    var title = ""
    var category: EventCategory = .community
    var topics: [EventCategory] = [.community]
    var town: CoastTown = .beachlands
    var locationScopeID = "beachlands"
    var locationDisplayName = "Beachlands"
    var venue = ""
    var date = Date()
    var time = Date()
    var priceLabel = "Free"
    var contactName = ""
    var contactEmail = ""
    var shortDescription = ""
    var pollQuestion = ""
    var pollOptions: [String] = ["", ""]
    var allowsCustomPollAnswer = false

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
        if listingKind == .poll {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && pollDetails?.isValid == true
        }

        return [
            title,
            venue,
            shortDescription
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var pollDetails: PollDetails? {
        let trimmedQuestion = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = pollOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(PollDetails.maxOptions)

        guard !trimmedQuestion.isEmpty else { return nil }

        return PollDetails(
            question: trimmedQuestion,
            options: Array(options),
            allowsCustomAnswer: allowsCustomPollAnswer
        )
    }

    var pollReviewText: String? {
        guard let pollDetails else { return nil }

        let options = pollDetails.options
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """
        [POLL]
        Question: \(pollDetails.question)

        Options:
        \(options)

        Custom answer: \(pollDetails.allowsCustomAnswer ? "Allowed, max \(PollDetails.customAnswerLimit) characters" : "Not allowed")
        [/POLL]
        """
    }
}
