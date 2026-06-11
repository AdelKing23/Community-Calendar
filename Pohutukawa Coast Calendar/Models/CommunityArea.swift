import Foundation

enum CommunityArea {
    static let appBrandName = "Community Calendar"
    static let defaultCountryName = "New Zealand"
    static let defaultRegionName = "Auckland"
    static let defaultCouncilName = "Auckland Council"
    static let defaultAreaName = "Pōhutukawa Coast"
    static let defaultLocalities = CoastTown.allCases.filter { $0 != .all }
}

enum LocationScopeKind: String, Hashable {
    case place = "Place"
    case community = "Community"
    case widerArea = "Wider Area"
    case region = "Region"
    case country = "Country"

    init?(databaseValue: String) {
        switch databaseValue {
        case "place": self = .place
        case "community": self = .community
        case "wider_area": self = .widerArea
        case "region": self = .region
        case "country": self = .country
        default: return nil
        }
    }

    var databaseValue: String {
        switch self {
        case .place: return "place"
        case .community: return "community"
        case .widerArea: return "wider_area"
        case .region: return "region"
        case .country: return "country"
        }
    }
}

struct LocationScope: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: LocationScopeKind
    let subtitle: String
    let townMatches: Set<CoastTown>
    let searchTerms: [String]
    let ladderIDs: [String]

    var displayTitle: String {
        name
    }

    var includesEverything: Bool {
        townMatches.isEmpty
    }

    func matches(_ event: LocalEvent) -> Bool {
        includesEverything || townMatches.contains(event.town)
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.locationSearchNormalized
        guard !normalizedQuery.isEmpty else { return true }

        return ([name, subtitle, kind.rawValue] + searchTerms)
            .map(\.locationSearchNormalized)
            .contains { $0.contains(normalizedQuery) }
    }

    var ladder: [LocationScope] {
        ladderIDs.compactMap { Self.scope(id: $0) }
    }

    var wideningOptions: [LocationScope] {
        Array(ladder.dropFirst())
    }

    var primaryTown: CoastTown? {
        switch id {
        case "omana": return .omana
        case "beachlands": return .beachlands
        case "maraetai": return .maraetai
        case "whitford": return .whitford
        case "clevedon": return .clevedon
        case "kawakawa-bay": return .kawakawaBay
        case "orere-point": return .orerePoint
        case "hunua": return .hunua
        case "ardmore": return .ardmore
        default: return townMatches.sorted { $0.rawValue < $1.rawValue }.first
        }
    }
}

struct LocationCatalog: Hashable {
    let scopes: [LocationScope]
    let linksByChildID: [String: [String]]
    let quickScopeIDs: [String]

    static let local = LocationCatalog(
        scopes: LocationScope.allScopes,
        linksByChildID: LocationScope.localLinksByChildID,
        quickScopeIDs: LocationScope.quickScopes.map(\.id)
    )

    var quickScopes: [LocationScope] {
        quickScopeIDs.compactMap(scope(id:))
    }

    var listingInputScopes: [LocationScope] {
        scopes.filter { $0.kind == .place }
    }

    func scope(id: String) -> LocationScope? {
        scopes.first { $0.id == id }
    }

    func defaultScope(for storedID: String) -> LocationScope {
        scope(id: storedID) ?? scope(id: LocationScope.defaultID) ?? scopes[0]
    }

    func ladder(for scopeID: String) -> [LocationScope] {
        var ladder: [LocationScope] = []
        var visitedIDs: Set<String> = []
        var currentID: String? = scopeID

        while let id = currentID,
              !visitedIDs.contains(id),
              let scope = scope(id: id) {
            ladder.append(scope)
            visitedIDs.insert(id)
            currentID = linksByChildID[id]?.first
        }

        return ladder
    }

    func displayLadder(selectedID: String, focusID: String) -> [LocationScope] {
        let selected = defaultScope(for: selectedID)
        let focused = defaultScope(for: focusID)
        let focusedLadder = ladder(for: focused.id)

        if focusedLadder.contains(where: { $0.id == selected.id }) {
            return focusedLadder
        }

        return ladder(for: selected.id)
    }

    func wideningOptions(selectedID: String, focusID: String) -> [LocationScope] {
        let selected = defaultScope(for: selectedID)
        let ladder = displayLadder(selectedID: selectedID, focusID: focusID)

        guard let selectedIndex = ladder.firstIndex(where: { $0.id == selected.id }) else {
            return Array(self.ladder(for: selected.id).dropFirst())
        }

        return Array(ladder.dropFirst(selectedIndex + 1))
    }
}

extension LocationScope {
    static let defaultID = "pohutukawa-coast"

    static let allScopes: [LocationScope] = [
        LocationScope(
            id: "omana",
            name: "Omana",
            kind: .place,
            subtitle: "Specific pocket between Beachlands and Maraetai",
            townMatches: [.omana],
            searchTerms: ["omana beach", "omana regional park", "beachlands", "maraetai"],
            ladderIDs: ["omana", "beachlands", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "beachlands",
            name: "Beachlands",
            kind: .place,
            subtitle: "Most local Beachlands listings",
            townMatches: [.beachlands],
            searchTerms: ["beac", "pine harbour", "te puru", "sunkist bay", "pohutukawa coast"],
            ladderIDs: ["beachlands", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "maraetai",
            name: "Maraetai",
            kind: .place,
            subtitle: "Maraetai village, beach and nearby venues",
            townMatches: [.maraetai],
            searchTerms: ["maraetai beach", "maraetai coast", "pohutukawa coast"],
            ladderIDs: ["maraetai", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "whitford",
            name: "Whitford",
            kind: .place,
            subtitle: "Whitford village and rural surrounds",
            townMatches: [.whitford],
            searchTerms: ["whitford village", "whitford hall", "franklin"],
            ladderIDs: ["whitford", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "clevedon",
            name: "Clevedon",
            kind: .place,
            subtitle: "Clevedon village, markets and rural events",
            townMatches: [.clevedon],
            searchTerms: ["clevedon markets", "clevedon showgrounds", "franklin"],
            ladderIDs: ["clevedon", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "kawakawa-bay",
            name: "Kawakawa Bay",
            kind: .place,
            subtitle: "Eastern coast listings near the bay",
            townMatches: [.kawakawaBay],
            searchTerms: ["kawakawa", "kaiaua road", "orere point", "franklin"],
            ladderIDs: ["kawakawa-bay", "pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "orere-point",
            name: "Orere Point",
            kind: .place,
            subtitle: "Specific listings around Orere Point",
            townMatches: [.orerePoint],
            searchTerms: ["orere", "orere point beach", "kawakawa bay", "firth of thames"],
            ladderIDs: ["orere-point", "kawakawa-bay", "pohutukawa-coast", "franklin", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "hunua",
            name: "Hunua",
            kind: .place,
            subtitle: "Hunua village and ranges-side events",
            townMatches: [.hunua],
            searchTerms: ["hunua ranges", "hunua village", "franklin"],
            ladderIDs: ["hunua", "franklin", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "ardmore",
            name: "Ardmore",
            kind: .place,
            subtitle: "Ardmore and nearby Franklin listings",
            townMatches: [.ardmore],
            searchTerms: ["ardmore airport", "papakura", "franklin"],
            ladderIDs: ["ardmore", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "pohutukawa-coast",
            name: "Pōhutukawa Coast",
            kind: .community,
            subtitle: "Beachlands, Maraetai, Omana, Whitford, Clevedon and nearby coast",
            townMatches: [.beachlands, .omana, .maraetai, .whitford, .clevedon, .kawakawaBay, .orerePoint],
            searchTerms: ["pohutukawa", "coast", "beachlands", "maraetai", "whitford", "clevedon", "omana"],
            ladderIDs: ["pohutukawa-coast", "franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "franklin",
            name: "Franklin",
            kind: .widerArea,
            subtitle: "Widen to Franklin-side communities",
            townMatches: [.beachlands, .omana, .maraetai, .whitford, .clevedon, .kawakawaBay, .orerePoint, .hunua, .ardmore],
            searchTerms: ["franklin", "waiuku", "pukekohe", "clevedon", "ardmore", "hunua"],
            ladderIDs: ["franklin", "east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "east-auckland",
            name: "East Auckland",
            kind: .widerArea,
            subtitle: "Widen toward nearby eastern communities",
            townMatches: [.beachlands, .omana, .maraetai, .whitford, .clevedon, .kawakawaBay, .orerePoint, .hunua, .ardmore],
            searchTerms: ["east auckland", "howick", "botany", "pakuranga", "dannemora", "flat bush"],
            ladderIDs: ["east-auckland", "auckland", "new-zealand"]
        ),
        LocationScope(
            id: "auckland",
            name: "Auckland",
            kind: .region,
            subtitle: "All active Auckland-area listings in this app",
            townMatches: [.beachlands, .omana, .maraetai, .whitford, .clevedon, .kawakawaBay, .orerePoint, .hunua, .ardmore],
            searchTerms: ["auckland", "tāmaki makaurau", "tamaki makaurau"],
            ladderIDs: ["auckland", "new-zealand"]
        ),
        LocationScope(
            id: "new-zealand",
            name: "New Zealand",
            kind: .country,
            subtitle: "Everything currently listed",
            townMatches: [],
            searchTerms: ["nz", "aotearoa", "new zealand"],
            ladderIDs: ["new-zealand"]
        )
    ]

    static let quickScopes: [LocationScope] = [
        scope(id: defaultID),
        scope(id: "beachlands"),
        scope(id: "maraetai"),
        scope(id: "omana"),
        scope(id: "clevedon"),
        scope(id: "whitford")
    ].compactMap { $0 }

    static let listingInputScopes: [LocationScope] = allScopes.filter { $0.kind == .place }

    static let localLinksByChildID: [String: [String]] = {
        var links: [String: [String]] = [:]

        for scope in allScopes {
            guard let parentID = scope.ladderIDs.dropFirst().first else { continue }
            links[scope.id] = [parentID]
        }

        return links
    }()

    static func scope(id: String) -> LocationScope? {
        allScopes.first { $0.id == id }
    }

    static func defaultScope(for storedID: String) -> LocationScope {
        scope(id: storedID) ?? scope(id: defaultID) ?? allScopes[0]
    }

    static func displayLadder(selectedID: String, focusID: String) -> [LocationScope] {
        let selected = defaultScope(for: selectedID)
        let focused = defaultScope(for: focusID)
        let focusedLadder = focused.ladder

        if focusedLadder.contains(where: { $0.id == selected.id }) {
            return focusedLadder
        }

        return selected.ladder
    }

    static func primaryScope(for town: CoastTown) -> LocationScope {
        switch town {
        case .all:
            return defaultScope(for: defaultID)
        case .omana:
            return defaultScope(for: "omana")
        case .beachlands:
            return defaultScope(for: "beachlands")
        case .maraetai:
            return defaultScope(for: "maraetai")
        case .whitford:
            return defaultScope(for: "whitford")
        case .clevedon:
            return defaultScope(for: "clevedon")
        case .kawakawaBay:
            return defaultScope(for: "kawakawa-bay")
        case .orerePoint:
            return defaultScope(for: "orere-point")
        case .hunua:
            return defaultScope(for: "hunua")
        case .ardmore:
            return defaultScope(for: "ardmore")
        }
    }
}

private extension String {
    var locationSearchNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
