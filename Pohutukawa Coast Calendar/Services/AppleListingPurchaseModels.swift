import Foundation

enum AppleListingPurchaseError: LocalizedError, Equatable {
    case unsupportedProductID(String)
    case missingStoreKitProductID(ListingTier)

    var errorDescription: String? {
        switch self {
        case .unsupportedProductID(let productID):
            return "Unsupported Apple product id: \(productID)"
        case .missingStoreKitProductID(let tier):
            return "\(tier.title) does not have an App Store product."
        }
    }
}

enum AppleListingPurchaseProduct: String, CaseIterable, Identifiable {
    case commercialStandard = "communitycalendar.commercial.standard"
    case boostStandard = "communitycalendar.boost.standard"
    case boostInsights = "communitycalendar.boost.insights"

    var id: String { rawValue }

    init(productID: String) throws {
        guard let product = Self(rawValue: productID) else {
            throw AppleListingPurchaseError.unsupportedProductID(productID)
        }
        self = product
    }

    var listingTier: ListingTier {
        switch self {
        case .commercialStandard:
            return .commercialStandard
        case .boostStandard:
            return .boost
        case .boostInsights:
            return .boostInsights
        }
    }

    var createsPromotion: Bool {
        switch self {
        case .commercialStandard:
            return false
        case .boostStandard, .boostInsights:
            return true
        }
    }

    var promotionPlacement: ListingPromotionPlacement? {
        switch self {
        case .commercialStandard:
            return nil
        case .boostStandard:
            return .topTen
        case .boostInsights:
            return .priorityFirst
        }
    }

    var includesPaidInsights: Bool {
        self == .boostInsights
    }
}

struct AppleListingPurchaseIntent: Codable, Equatable {
    let eventID: UUID
    let productID: String
    let appAccountToken: UUID
    let requestedStartsAt: Date?
    let requestedEndsAt: Date?

    init(
        eventID: UUID,
        tier: ListingTier,
        userID: UUID,
        requestedStartsAt: Date? = nil,
        requestedEndsAt: Date? = nil
    ) throws {
        guard let productID = tier.storeKitProductID else {
            throw AppleListingPurchaseError.missingStoreKitProductID(tier)
        }
        self.eventID = eventID
        self.productID = productID
        self.appAccountToken = userID
        self.requestedStartsAt = requestedStartsAt
        self.requestedEndsAt = requestedEndsAt
    }
}

struct StoreKitVerifiedTransactionEvidence: Codable, Equatable {
    let transactionID: String
    let originalTransactionID: String?
    let productID: String
    let signedTransactionJWS: String?
    let appAccountToken: UUID?
}

enum AppleListingPurchaseBackendStatus: String, Codable, Equatable {
    case activated
    case alreadyProcessed = "already_processed"
    case rejected
}

struct AppleListingPurchaseBackendResult: Codable, Equatable {
    let status: AppleListingPurchaseBackendStatus
    let appleIAPTransactionID: UUID?
    let eventPaymentRecordID: UUID?
    let eventPromotionID: UUID?
    let startsAt: Date?
    let endsAt: Date?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case appleIAPTransactionID = "apple_iap_transaction_id"
        case eventPaymentRecordID = "event_payment_record_id"
        case eventPromotionID = "event_promotion_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case message
    }
}

enum StoreKitPurchaseOutcome: Equatable {
    case verified
    case userCancelled
    case pendingApproval
    case unverified
}

enum AppleTransactionFinishPolicy {
    nonisolated static func shouldCallBackend(for outcome: StoreKitPurchaseOutcome) -> Bool {
        if case .verified = outcome {
            return true
        }
        return false
    }

    nonisolated static func shouldFinish(after backendStatus: AppleListingPurchaseBackendStatus) -> Bool {
        backendStatus == .activated || backendStatus == .alreadyProcessed
    }
}

struct AppleTransactionBinding: Equatable {
    let transactionID: String
    let purchaserUserID: UUID
    let eventID: UUID
    let productID: String
}

enum AppleTransactionReplayDecision: Equatable {
    case alreadyProcessed
    case rejectedRebind
}

enum AppleTransactionReplayPolicy {
    nonisolated static func decision(
        existing: AppleTransactionBinding,
        incoming: AppleTransactionBinding
    ) -> AppleTransactionReplayDecision {
        guard existing.transactionID == incoming.transactionID,
              existing.purchaserUserID == incoming.purchaserUserID,
              existing.eventID == incoming.eventID,
              existing.productID == incoming.productID else {
            return .rejectedRebind
        }

        return .alreadyProcessed
    }
}

protocol PendingApplePurchaseIntentStoring {
    func save(_ intent: AppleListingPurchaseIntent)
    func intent(for evidence: StoreKitVerifiedTransactionEvidence) -> AppleListingPurchaseIntent?
    func removeIntent(for evidence: StoreKitVerifiedTransactionEvidence)
}

final class UserDefaultsApplePurchaseIntentStore: PendingApplePurchaseIntentStoring {
    private let defaults: UserDefaults
    private let key = "community_calendar_pending_apple_purchase_intents"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ intent: AppleListingPurchaseIntent) {
        var intents = loadIntents()
        intents[intent.productID] = intent
        persist(intents)
    }

    func intent(for evidence: StoreKitVerifiedTransactionEvidence) -> AppleListingPurchaseIntent? {
        loadIntents()[evidence.productID]
    }

    func removeIntent(for evidence: StoreKitVerifiedTransactionEvidence) {
        var intents = loadIntents()
        intents.removeValue(forKey: evidence.productID)
        persist(intents)
    }

    private func loadIntents() -> [String: AppleListingPurchaseIntent] {
        guard let data = defaults.data(forKey: key),
              let intents = try? decoder.decode([String: AppleListingPurchaseIntent].self, from: data) else {
            return [:]
        }
        return intents
    }

    private func persist(_ intents: [String: AppleListingPurchaseIntent]) {
        if intents.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? encoder.encode(intents) else { return }
        defaults.set(data, forKey: key)
    }
}

protocol AppleListingPurchaseProcessing {
    func processVerifiedPurchase(
        evidence: StoreKitVerifiedTransactionEvidence,
        intent: AppleListingPurchaseIntent,
        accessToken: String
    ) async throws -> AppleListingPurchaseBackendResult
}

struct SupabaseAppleListingPurchaseService: AppleListingPurchaseProcessing {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func processVerifiedPurchase(
        evidence: StoreKitVerifiedTransactionEvidence,
        intent: AppleListingPurchaseIntent,
        accessToken: String
    ) async throws -> AppleListingPurchaseBackendResult {
        guard let url = SupabaseConfiguration.functionsURL?
            .appendingPathComponent("verify-apple-listing-purchase") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            AppleListingPurchaseVerificationRequest(
                eventID: intent.eventID,
                transactionID: evidence.transactionID,
                productID: evidence.productID,
                signedTransactionJWS: evidence.signedTransactionJWS,
                requestedStartsAt: intent.requestedStartsAt,
                requestedEndsAt: intent.requestedEndsAt
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        return try decoder.decode(AppleListingPurchaseBackendResult.self, from: data)
    }
}

private struct AppleListingPurchaseVerificationRequest: Encodable {
    let eventID: UUID
    let transactionID: String
    let productID: String
    let signedTransactionJWS: String?
    let requestedStartsAt: Date?
    let requestedEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case transactionID = "transaction_id"
        case productID = "product_id"
        case signedTransactionJWS = "signed_transaction_jws"
        case requestedStartsAt = "requested_starts_at"
        case requestedEndsAt = "requested_ends_at"
    }
}
