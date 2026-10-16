import Foundation

enum ListingTier: String, CaseIterable, Identifiable, Hashable {
    case communityFree = "community_free"
    case commercialStandard = "commercial_standard"
    case boost = "boost"
    case boostInsights = "boost_insights"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .communityFree: return "Community"
        case .commercialStandard: return "Commercial"
        case .boost: return "Boost"
        case .boostInsights: return "Boost + Insights"
        }
    }

    var priceText: String {
        switch self {
        case .communityFree: return "Free"
        case .commercialStandard: return "$15"
        case .boost: return "$35"
        case .boostInsights: return "$75"
        }
    }

    var shortDescription: String {
        switch self {
        case .communityFree:
            return "Local community, non-profit, school, sports or public-good listings."
        case .commercialStandard:
            return "Member-submitted business, class, service, shop, stall or promotion listings."
        case .boost:
            return "Legacy boosted-visibility classification for historical listings."
        case .boostInsights:
            return "Legacy priority classification for historical listings."
        }
    }

    var priceLabel: String {
        switch self {
        case .communityFree: return "Free"
        case .commercialStandard: return "Commercial $15"
        case .boost: return "Boost $35"
        case .boostInsights: return "Priority Feature $75"
        }
    }

    var reviewHint: String {
        switch self {
        case .communityFree:
            return "Free listings are checked for community fit."
        case .commercialStandard:
            return "Commercial listings require approved member publishing access."
        case .boost:
            return "Legacy boosted listings require Support review."
        case .boostInsights:
            return "Legacy priority listings require Support review."
        }
    }

    var isPaidTier: Bool {
        self != .communityFree
    }

    var includesInsights: Bool {
        self == .boostInsights
    }

    var promotionPlacement: ListingPromotionPlacement {
        switch self {
        case .communityFree, .commercialStandard:
            return .standard
        case .boost:
            return .topTen
        case .boostInsights:
            return .priorityFirst
        }
    }

    var maximumPromotionDuration: TimeInterval? {
        switch self {
        case .communityFree, .commercialStandard:
            return nil
        case .boost:
            return 60 * 60 * 24 * 3
        case .boostInsights:
            return 60 * 60 * 24 * 7
        }
    }

    var sortRank: Int {
        switch self {
        case .communityFree: return 0
        case .commercialStandard: return 1
        case .boost: return 2
        case .boostInsights: return 3
        }
    }
}

enum ListingPromotionPlacement: Int, Hashable, Comparable {
    case standard = 0
    case topTen = 1
    case priorityFirst = 2

    static func < (lhs: ListingPromotionPlacement, rhs: ListingPromotionPlacement) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PromotionWindowPolicy {
    static func clampedWindow(
        tier: ListingTier,
        eventStart: Date,
        eventEnd: Date,
        requestedStart: Date,
        requestedEnd: Date?,
        now: Date = Date()
    ) -> DateInterval? {
        guard let maximumDuration = tier.maximumPromotionDuration else { return nil }

        let start = max(requestedStart, now)
        let requestedOrDefaultEnd = requestedEnd ?? start.addingTimeInterval(maximumDuration)
        let cappedDurationEnd = start.addingTimeInterval(maximumDuration)
        let end = min(requestedOrDefaultEnd, cappedDurationEnd, eventEnd)

        guard end > start, eventStart > now else { return nil }
        return DateInterval(start: start, end: end)
    }
}

struct ListingCommercialSignal: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let detail: String
}

enum ListingCommercialSignalDetector {
    static func signals(for draft: PendingListingDraft) -> [ListingCommercialSignal] {
        let searchable = [
            draft.title,
            draft.venue,
            draft.shortDescription,
            draft.priceLabel
        ]
        .joined(separator: " ")
        .lowercased()

        var signals: [ListingCommercialSignal] = []

        let businessTerms = [
            "ltd",
            "limited",
            "cafe",
            "café",
            "salon",
            "studio",
            "clinic",
            "realty",
            "restaurant",
            "shop",
            "store",
            "services",
            "consultation",
            "book now",
            "sale",
            "discount",
            "special offer",
            "limited offer"
        ]

        let matchedTerms = businessTerms.filter { searchable.contains($0) }
        if !matchedTerms.isEmpty {
            signals.append(
                ListingCommercialSignal(
                    label: "Business wording",
                    detail: "Found: \(matchedTerms.prefix(3).joined(separator: ", "))"
                )
            )
        }

        let price = draft.priceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !price.isEmpty && !price.localizedCaseInsensitiveContains("free") && !price.localizedCaseInsensitiveContains("koha") {
            signals.append(
                ListingCommercialSignal(
                    label: "Paid entry or offer",
                    detail: "Cost is listed as \(price)."
                )
            )
        }

        switch draft.category {
        case .foodDrink, .classesWorkshops, .markets, .nightlife:
            signals.append(
                ListingCommercialSignal(
                    label: "Commercial-leaning category",
                    detail: "\(draft.category.rawValue) often needs closer review."
                )
            )
        default:
            break
        }

        return signals
    }

    static func signals(for event: LocalEvent) -> [ListingCommercialSignal] {
        var draft = PendingListingDraft()
        draft.title = event.title
        draft.category = event.category
        draft.town = event.town
        draft.venue = event.venue
        draft.priceLabel = event.priceLabel
        draft.shortDescription = event.shortDescription
        return signals(for: draft)
    }
}

struct ListingAnalyticsSnapshot: Hashable {
    let impressions: Int
    let detailViews: Int
    let engagementTaps: Int
    let saves: Int
    let shares: Int

    static let zero = ListingAnalyticsSnapshot(
        impressions: 0,
        detailViews: 0,
        engagementTaps: 0,
        saves: 0,
        shares: 0
    )

    var conversionPercentText: String {
        guard impressions > 0 else { return "0%" }
        let rate = Double(detailViews) / Double(impressions)
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }
}
