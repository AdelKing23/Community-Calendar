import Foundation

enum CoastTown: String, CaseIterable, Identifiable, Hashable {
    case all = "All Areas"
    case whitford = "Whitford"
    case maraetai = "Maraetai"
    case beachlands = "Beachlands"
    case clevedon = "Clevedon"

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
}

struct PendingListingDraft: Hashable {
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

    var canSubmit: Bool {
        [
            title,
            venue,
            shortDescription
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
