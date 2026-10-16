import Foundation

struct StoreKitVerifiedTransactionEvidence: Codable, Equatable {
    let transactionID: String
    let originalTransactionID: String?
    let productID: String
    let signedTransactionJWS: String?
    let appAccountToken: UUID?
}

struct AppleBusinessSubscriptionIntent: Codable, Equatable {
    let businessProfileID: UUID
    let productID: String
    let appAccountToken: UUID

    init(businessProfileID: UUID, plan: BusinessSubscriptionPlan, userID: UUID) {
        self.businessProfileID = businessProfileID
        self.productID = plan.productID
        self.appAccountToken = userID
    }
}

enum AppleBusinessSubscriptionBackendStatus: String, Codable, Equatable {
    case activated
    case alreadyProcessed = "already_processed"
    case rejected
}

struct AppleBusinessSubscriptionBackendResult: Codable, Equatable {
    let status: AppleBusinessSubscriptionBackendStatus
    let businessSubscriptionID: UUID?
    let currentPeriodEnd: Date?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case businessSubscriptionID = "business_subscription_id"
        case currentPeriodEnd = "current_period_end"
        case message
    }

    var grantsCurrentAccess: Bool {
        guard status == .activated || status == .alreadyProcessed else { return false }
        guard let currentPeriodEnd else { return false }
        return currentPeriodEnd >= Date()
    }
}

protocol AppleBusinessSubscriptionProcessing {
    func processVerifiedSubscription(
        evidence: StoreKitVerifiedTransactionEvidence,
        intent: AppleBusinessSubscriptionIntent,
        accessToken: String
    ) async throws -> AppleBusinessSubscriptionBackendResult
}

struct SupabaseAppleBusinessSubscriptionService: AppleBusinessSubscriptionProcessing {
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

    func processVerifiedSubscription(
        evidence: StoreKitVerifiedTransactionEvidence,
        intent: AppleBusinessSubscriptionIntent,
        accessToken: String
    ) async throws -> AppleBusinessSubscriptionBackendResult {
        guard let url = SupabaseConfiguration.functionsURL?
            .appendingPathComponent("verify-apple-business-subscription") else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            AppleBusinessSubscriptionVerificationRequest(
                businessProfileID: intent.businessProfileID,
                transactionID: evidence.transactionID,
                productID: evidence.productID,
                signedTransactionJWS: evidence.signedTransactionJWS
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        let responseBody = String(data: data, encoding: .utf8)
#if DEBUG
        print("[AppleBusinessSubscription] verify status=\(httpResponse.statusCode) body=\(responseBody ?? "<empty>")")
#endif
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, responseBody)
        }

        return try decoder.decode(AppleBusinessSubscriptionBackendResult.self, from: data)
    }
}

private struct AppleBusinessSubscriptionVerificationRequest: Encodable {
    let businessProfileID: UUID
    let transactionID: String
    let productID: String
    let signedTransactionJWS: String?

    enum CodingKeys: String, CodingKey {
        case businessProfileID = "business_profile_id"
        case transactionID = "transaction_id"
        case productID = "product_id"
        case signedTransactionJWS = "signed_transaction_jws"
    }
}
