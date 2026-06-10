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
        case .commercialStandard: return "$5"
        case .boost: return "$10"
        case .boostInsights: return "$15"
        }
    }

    var shortDescription: String {
        switch self {
        case .communityFree:
            return "Local community, non-profit, school, sports or public-good listings."
        case .commercialStandard:
            return "Business, class, service, shop, stall or paid promotion listings."
        case .boost:
            return "Commercial listing with higher placement once payment is connected."
        case .boostInsights:
            return "Boosted placement plus deeper listing performance insights."
        }
    }

    var priceLabel: String {
        switch self {
        case .communityFree: return "Free"
        case .commercialStandard: return "Commercial $5"
        case .boost: return "Boost $10"
        case .boostInsights: return "Boost + Insights $15"
        }
    }

    var reviewHint: String {
        switch self {
        case .communityFree:
            return "Free listings are checked for community fit."
        case .commercialStandard:
            return "Commercial listings are reviewed before payment is requested."
        case .boost:
            return "Boosted listings need payment before the placement is applied."
        case .boostInsights:
            return "Insights listings include the clearest performance report once analytics are live."
        }
    }

    var isPaidTier: Bool {
        self != .communityFree
    }

    var includesInsights: Bool {
        self == .boostInsights
    }

    var storeKitProductID: String? {
        switch self {
        case .communityFree:
            return nil
        case .commercialStandard:
            return "communitycalendar.commercial.standard"
        case .boost:
            return "communitycalendar.boost.standard"
        case .boostInsights:
            return "communitycalendar.boost.insights"
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

    static func softLaunchEstimate(for event: LocalEvent) -> ListingAnalyticsSnapshot {
        let base = abs(event.id.uuidString.hashValue)
        let impressions = max(1, base % 140)
        let detailViews = max(0, impressions / 5)
        let engagementTaps = max(0, detailViews / 3)
        let saves = max(0, engagementTaps / 3)
        let shares = max(0, engagementTaps / 4)

        return ListingAnalyticsSnapshot(
            impressions: impressions,
            detailViews: detailViews,
            engagementTaps: engagementTaps,
            saves: saves,
            shares: shares
        )
    }

    var conversionPercentText: String {
        guard impressions > 0 else { return "0%" }
        let rate = Double(detailViews) / Double(impressions)
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }
}
