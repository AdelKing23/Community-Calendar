import CoreGraphics
import Foundation

enum BusinessSubscriptionPlan: String, CaseIterable, Identifiable, Codable, Hashable {
    case localBusiness = "local_business"
    case growth = "growth"
    case sponsor = "sponsor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localBusiness: return "Local Member"
        case .growth: return "Growth Member"
        case .sponsor: return "Community Partner"
        }
    }

    var priceText: String {
        switch self {
        case .localBusiness: return "$19.99/month"
        case .growth: return "$49.99/month"
        case .sponsor: return "$149.99/month"
        }
    }

    var productID: String {
        switch self {
        case .localBusiness: return "communitycalendar.business.local.monthly"
        case .growth: return "communitycalendar.business.growth.monthly"
        case .sponsor: return "communitycalendar.business.sponsor.monthly"
        }
    }

    static func plan(forProductID productID: String) -> BusinessSubscriptionPlan? {
        allCases.first { $0.productID == productID }
    }

    var audience: String {
        switch self {
        case .localBusiness: return "New local publishers"
        case .growth: return "Regular local publishers"
        case .sponsor: return "High-activity community publishers"
        }
    }

    var activeListingLimit: Int {
        switch self {
        case .localBusiness: return 1
        case .growth: return 4
        case .sponsor: return 8
        }
    }

    var placementRank: Int {
        switch self {
        case .localBusiness: return 10
        case .growth: return 20
        case .sponsor: return 30
        }
    }

    var tagText: String {
        switch self {
        case .localBusiness: return "Verified Member"
        case .growth: return "Growth Member"
        case .sponsor: return "Community Partner"
        }
    }

    var inclusions: [String] {
        switch self {
        case .localBusiness:
            return [
                "Verified member page",
                "1 active listing or poll at a time",
                "Basic insights: views, taps, saves and shares",
                "Verified member badge",
                "Edit or remove your own listings and polls"
            ]
        case .growth:
            return [
                "Everything in Local Member",
                "Up to 4 active listings or polls",
                "Richer engagement analytics",
                "Member page with optional contact details",
                "Better audience insight reporting"
            ]
        case .sponsor:
            return [
                "Up to 8 active listings or polls",
                "Community Partner badge",
                "Priority member placement",
                "Best available insights package"
            ]
        }
    }
}

enum BusinessProfileStatus: String, Codable, Equatable {
    case pendingReview = "pending_review"
    case approved
    case rejected
    case suspended
    case archived

    var displayTitle: String {
        switch self {
        case .pendingReview: return "Pending review"
        case .approved: return "Approved"
        case .rejected: return "Needs changes"
        case .suspended: return "Suspended"
        case .archived: return "Archived"
        }
    }

    var canCompleteSubscription: Bool {
        self == .approved
    }
}

enum BusinessOrganisationType: String, CaseIterable, Identifiable, Codable, Hashable {
    case business
    case schoolECE = "school_ece"
    case sportsClub = "sports_club"
    case communityGroup = "community_group"
    case charityNonProfit = "charity_non_profit"
    case maraeCulturalOrganisation = "marae_cultural_organisation"
    case churchFaithCommunity = "church_faith_community"
    case market
    case hospitalityVenue = "hospitality_venue"
    case instructorActivityProvider = "instructor_activity_provider"
    case councilPublicService = "council_public_service"
    case otherOrganisation = "other_organisation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: return "Business"
        case .schoolECE: return "School/ECE"
        case .sportsClub: return "Sports club"
        case .communityGroup: return "Community group"
        case .charityNonProfit: return "Charity/non-profit"
        case .maraeCulturalOrganisation: return "Marae/cultural organisation"
        case .churchFaithCommunity: return "Church/faith community"
        case .market: return "Market"
        case .hospitalityVenue: return "Hospitality/venue"
        case .instructorActivityProvider: return "Instructor/activity provider"
        case .councilPublicService: return "Council/public service"
        case .otherOrganisation: return "Other organisation"
        }
    }
}

enum MembershipContactEmailValidator {
    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isUsable(_ email: String) -> Bool {
        let value = normalized(email)
        guard !value.isEmpty,
              !value.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return false
        }

        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let local = parts.first,
              let domain = parts.last,
              !local.isEmpty,
              !domain.isEmpty,
              !local.hasPrefix("."),
              !local.hasSuffix("."),
              domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".") else {
            return false
        }

        return domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
    }
}

struct MembershipApplicationValidationTrace: Equatable {
    let rawAccountEmail: String?
    let trimmedAccountEmail: String?
    let accountEmailAccepted: Bool?
    let rawContactEmail: String
    let trimmedContactEmail: String
    let contactEmailAccepted: Bool
    let hasMemberName: Bool
    let organisationType: BusinessOrganisationType?
    var hasOrganisationType: Bool { organisationType != nil }
    let websiteAccepted: Bool
    let blockingFields: Set<String>

    var formIsValid: Bool {
        blockingFields.isEmpty
    }

    var payloadContactEmail: String {
        trimmedContactEmail
    }

    var payloadOrganisationType: String? {
        organisationType?.rawValue
    }

    static func evaluate(
        accountEmail: String?,
        draft: BusinessProfileDraft,
        websiteAccepted: Bool
    ) -> MembershipApplicationValidationTrace {
        var blockingFields = Set<String>()
        let trimmedAccountEmail = accountEmail.map(MembershipContactEmailValidator.normalized)
        let accountEmailAccepted = trimmedAccountEmail.map(MembershipContactEmailValidator.isUsable)
        let trimmedContactEmail = MembershipContactEmailValidator.normalized(draft.email)
        let contactEmailAccepted = MembershipContactEmailValidator.isUsable(trimmedContactEmail)
        let hasMemberName = !draft.trimmedName.isEmpty

        if accountEmail != nil, accountEmailAccepted != true {
            blockingFields.insert("accountEmail")
        }
        if !hasMemberName {
            blockingFields.insert("memberName")
        }
        if draft.organisationType == nil {
            blockingFields.insert("organisationType")
        }
        if !contactEmailAccepted {
            blockingFields.insert("contactEmail")
        }
        let hasContactName = !draft.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasContactName {
            blockingFields.insert("contactName")
        }
        // Website is optional — only block if user entered a partial/invalid value
        if !websiteAccepted {
            let raw = draft.website.trimmingCharacters(in: .whitespacesAndNewlines)
            let looksEmpty = raw.isEmpty || raw == "https://" || raw == "https://www." || raw == "http://"
            if !looksEmpty {
                blockingFields.insert("website")
            }
        }

        return MembershipApplicationValidationTrace(
            rawAccountEmail: accountEmail,
            trimmedAccountEmail: trimmedAccountEmail,
            accountEmailAccepted: accountEmailAccepted,
            rawContactEmail: draft.email,
            trimmedContactEmail: trimmedContactEmail,
            contactEmailAccepted: contactEmailAccepted,
            hasMemberName: hasMemberName,
            organisationType: draft.organisationType,
            websiteAccepted: websiteAccepted,
            blockingFields: blockingFields
        )
    }
}

enum FoundingSponsorPackage: String, CaseIterable, Identifiable, Codable, Hashable {
    case supporter = "supporter"
    case area = "area"
    case major = "major"
    case launchPartner = "launch_partner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supporter: return "Supporter sponsor"
        case .area: return "Area sponsor"
        case .major: return "Major founding sponsor"
        case .launchPartner: return "Launch partner"
        }
    }

    var priceText: String {
        switch self {
        case .supporter: return "$250"
        case .area: return "$500"
        case .major: return "$1,000"
        case .launchPartner: return "$1,500"
        }
    }
}

struct BusinessProfileDraft: Equatable {
    var name = ""
    var organisationType: BusinessOrganisationType?
    var contactName = ""
    var email = ""
    var phone = ""
    var address = ""
    var website = ""
    var about = ""
    var areaScopeID = LocationScope.defaultID
    var selectedPlan: BusinessSubscriptionPlan = .localBusiness
    var heroImageURL = ""
    var avatarImageURL = ""
    var heroImagePositionX = 50.0
    var heroImagePositionY = 50.0
    var avatarImagePositionX = 50.0
    var avatarImagePositionY = 50.0
    var notes = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasMinimumRequiredFields: Bool {
        !trimmedName.isEmpty
            && organisationType != nil
            && MembershipContactEmailValidator.isUsable(trimmedEmail)
            && !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct BusinessProfileRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let ownerUserID: UUID
    let businessName: String
    let organisationTypeID: String?
    let contactName: String?
    let contactEmail: String
    let phone: String?
    let address: String?
    let website: String?
    let about: String?
    let areaScopeID: String
    let status: String
    let selectedPlanID: String?
    let heroImageURL: String?
    let avatarImageURL: String?
    let heroImagePositionX: Double
    let heroImagePositionY: Double
    let avatarImagePositionX: Double
    let avatarImagePositionY: Double
    let approvedAt: Date?
    let rejectedAt: Date?
    let rejectionReason: String?
    let suspendedAt: Date?
    let suspensionReason: String?
    let supportNote: String?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case businessName = "business_name"
        case organisationTypeID = "organisation_type"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case phone
        case address
        case website
        case about
        case areaScopeID = "area_scope_id"
        case status
        case selectedPlanID = "selected_plan_id"
        case heroImageURL = "hero_image_url"
        case avatarImageURL = "avatar_image_url"
        case heroImagePositionX = "hero_image_position_x"
        case heroImagePositionY = "hero_image_position_y"
        case avatarImagePositionX = "avatar_image_position_x"
        case avatarImagePositionY = "avatar_image_position_y"
        case approvedAt = "approved_at"
        case rejectedAt = "rejected_at"
        case rejectionReason = "rejection_reason"
        case suspendedAt = "suspended_at"
        case suspensionReason = "suspension_reason"
        case supportNote = "support_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var memberStatus: BusinessProfileStatus {
        BusinessProfileStatus(rawValue: status) ?? .pendingReview
    }

    var selectedPlan: BusinessSubscriptionPlan {
        selectedPlanID.flatMap(BusinessSubscriptionPlan.init(rawValue:)) ?? .localBusiness
    }

    var organisationType: BusinessOrganisationType? {
        organisationTypeID.flatMap(BusinessOrganisationType.init(rawValue:))
    }

    var isApproved: Bool {
        memberStatus == .approved
    }

    var hasCompletedHomepage: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !(about ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PublicBusinessProfileRecord: Identifiable, Decodable, Equatable {
    let id: UUID
    let publicSlug: String
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
    let publishedAt: Date?
    let publicContactRevision: UUID
    let publicContactConfirmedRevision: UUID?
    let publicContactConfirmedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case publicSlug = "public_slug"
        case displayName = "display_name"
        case areaScopeID = "area_scope_id"
        case bio
        case publicContactName = "public_contact_name"
        case publicContactEmail = "public_contact_email"
        case publicPhone = "public_phone"
        case publicLocationText = "public_location_text"
        case publicAddress = "public_address"
        case publicWebsite = "public_website"
        case avatarImagePath = "avatar_image_path"
        case heroImagePath = "hero_image_path"
        case avatarImagePositionX = "avatar_image_position_x"
        case avatarImagePositionY = "avatar_image_position_y"
        case heroImagePositionX = "hero_image_position_x"
        case heroImagePositionY = "hero_image_position_y"
        case publishedAt = "published_at"
        case publicContactRevision = "public_contact_revision"
        case publicContactConfirmedRevision = "public_contact_confirmed_revision"
        case publicContactConfirmedAt = "public_contact_confirmed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicSlug = try container.decode(String.self, forKey: .publicSlug)
        displayName = try container.decode(String.self, forKey: .displayName)
        areaScopeID = try container.decode(String.self, forKey: .areaScopeID)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        publicContactName = try container.decodeIfPresent(String.self, forKey: .publicContactName)
        publicContactEmail = try container.decodeIfPresent(String.self, forKey: .publicContactEmail)
        publicPhone = try container.decodeIfPresent(String.self, forKey: .publicPhone)
        publicLocationText = try container.decodeIfPresent(String.self, forKey: .publicLocationText)
        publicAddress = try container.decodeIfPresent(String.self, forKey: .publicAddress)
        publicWebsite = try container.decodeIfPresent(String.self, forKey: .publicWebsite)
        avatarImagePath = try container.decodeIfPresent(String.self, forKey: .avatarImagePath)
        heroImagePath = try container.decodeIfPresent(String.self, forKey: .heroImagePath)
        avatarImagePositionX = try container.decodeIfPresent(Double.self, forKey: .avatarImagePositionX) ?? 50
        avatarImagePositionY = try container.decodeIfPresent(Double.self, forKey: .avatarImagePositionY) ?? 50
        heroImagePositionX = try container.decodeIfPresent(Double.self, forKey: .heroImagePositionX) ?? 50
        heroImagePositionY = try container.decodeIfPresent(Double.self, forKey: .heroImagePositionY) ?? 50
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        publicContactRevision = try container.decode(UUID.self, forKey: .publicContactRevision)
        publicContactConfirmedRevision = try container.decodeIfPresent(UUID.self, forKey: .publicContactConfirmedRevision)
        publicContactConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .publicContactConfirmedAt)
    }

    var isCurrentPublicContactConfirmed: Bool {
        publicContactConfirmedRevision == publicContactRevision
    }
}

struct PublicMemberProfileDraft: Equatable {
    var displayName = ""
    var areaScopeID = ""
    var bio = ""
    var publicContactName = ""
    var publicContactEmail = ""
    var publicPhone = ""
    var publicLocationText = ""
    var publicAddress = ""
    var publicWebsite = ""
    var avatarImagePath: String?
    var heroImagePath: String?
    var avatarImagePositionX = 50.0
    var avatarImagePositionY = 50.0
    var heroImagePositionX = 50.0
    var heroImagePositionY = 50.0

    init() {}

    init(profile: PublicBusinessProfileRecord) {
        displayName = profile.displayName
        areaScopeID = profile.areaScopeID
        bio = profile.bio ?? ""
        publicContactName = profile.publicContactName ?? ""
        publicContactEmail = profile.publicContactEmail ?? ""
        publicPhone = profile.publicPhone ?? ""
        publicLocationText = profile.publicLocationText ?? ""
        publicAddress = profile.publicAddress ?? ""
        publicWebsite = profile.publicWebsite ?? ""
        avatarImagePath = profile.avatarImagePath
        heroImagePath = profile.heroImagePath
        avatarImagePositionX = profile.avatarImagePositionX
        avatarImagePositionY = profile.avatarImagePositionY
        heroImagePositionX = profile.heroImagePositionX
        heroImagePositionY = profile.heroImagePositionY
    }
}

enum MemberProfileImageCrop {
    static func offset(in size: CGSize, isCircular: Bool, positionX: Double, positionY: Double) -> CGSize {
        let maxX = size.width * (isCircular ? 0.09 : 0.12)
        let maxY = size.height * (isCircular ? 0.09 : 0.12)
        return CGSize(
            width: maxX * CGFloat((50 - positionX) / 50),
            height: maxY * CGFloat((50 - positionY) / 50)
        )
    }
}

struct MemberNoticeRecord: Identifiable, Decodable, Equatable {
    let id: UUID
    let businessProfileID: UUID
    let ownerUserID: UUID
    let title: String
    let summary: String?
    let body: String?
    let templateStyle: String
    let status: String
    let heroImageURL: String?
    let publishedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case businessProfileID = "business_profile_id"
        case ownerUserID = "owner_user_id"
        case title
        case summary
        case body
        case templateStyle = "template_style"
        case status
        case heroImageURL = "hero_image_url"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BusinessSubscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let businessProfileID: UUID
    let ownerUserID: UUID
    let planID: String
    let productID: String
    let appleOriginalTransactionID: String?
    let status: String
    let activeListingLimit: Int
    let placementRank: Int
    let currentPeriodStart: Date?
    let currentPeriodEnd: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case businessProfileID = "business_profile_id"
        case ownerUserID = "owner_user_id"
        case planID = "plan_id"
        case productID = "product_id"
        case appleOriginalTransactionID = "apple_original_transaction_id"
        case status
        case activeListingLimit = "active_listing_limit"
        case placementRank = "placement_rank"
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd = "current_period_end"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var plan: BusinessSubscriptionPlan? {
        BusinessSubscriptionPlan(rawValue: planID)
    }

    var isCurrentlyActive: Bool {
        guard status == "active" || status == "trialing" || status == "grace_period" else { return false }
        guard let currentPeriodEnd else { return false }
        return currentPeriodEnd >= Date()
    }

    var isPaidThroughActive: Bool {
        if isCurrentlyActive { return true }
        guard status == "cancelled", let currentPeriodEnd else { return false }
        return currentPeriodEnd >= Date()
    }
}

struct FoundingSponsorRequestRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let businessProfileID: UUID
    let ownerUserID: UUID
    let packageID: String
    let status: String
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case businessProfileID = "business_profile_id"
        case ownerUserID = "owner_user_id"
        case packageID = "package_id"
        case status
        case notes
        case createdAt = "created_at"
    }
}

struct BusinessAccountState: Equatable {
    var profile: BusinessProfileRecord?
    var subscriptions: [BusinessSubscriptionRecord]
    var sponsorRequests: [FoundingSponsorRequestRecord]

    var activeSubscription: BusinessSubscriptionRecord? {
        subscriptions
            .filter(\.isPaidThroughActive)
            .sorted {
                if $0.isCurrentlyActive != $1.isCurrentlyActive {
                    return $0.isCurrentlyActive
                }
                return ($0.currentPeriodEnd ?? .distantFuture) > ($1.currentPeriodEnd ?? .distantFuture)
            }
            .first
    }

    var subscriptionNeedingBackendAttention: BusinessSubscriptionRecord? {
        subscriptions
            .filter { ($0.status == "active" || $0.status == "trialing" || $0.status == "grace_period") && $0.currentPeriodEnd == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    var canCompleteSubscription: Bool {
        profile?.memberStatus.canCompleteSubscription == true
    }

    /// Support has approved this Organisation.
    var isOrganisationApproved: Bool {
        profile?.isApproved == true
    }

    /// Organisation has an active subscription entitlement.
    var hasActiveOrganisationSubscription: Bool {
        activeSubscription != nil
    }

    /// May open Create and submit listings/polls (approved Organisation + active subscription).
    /// Product law 2026-08-27: no pending create without paid plan.
    var canSubmitAsOrganisation: Bool {
        isOrganisationApproved && hasActiveOrganisationSubscription
    }

    /// May release listings/polls to the public board (same gate as submit under current product law).
    var canReleaseToBoard: Bool {
        isOrganisationApproved && hasActiveOrganisationSubscription
    }

    /// Legacy name: means release-to-board, not "can open Create".
    var canPublishListings: Bool { canReleaseToBoard }

    /// Deprecated alias — prefer canSubmitAsOrganisation / canReleaseToBoard.
    var hasPublishingAccess: Bool { canReleaseToBoard }

    static let empty = BusinessAccountState(profile: nil, subscriptions: [], sponsorRequests: [])
}
