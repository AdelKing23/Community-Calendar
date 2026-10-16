import Foundation
import Combine
import StoreKit

enum StoreKitPaymentState: Equatable {
    case idle
    case loadingProducts
    case ready(productCount: Int)
    case productsUnavailable
    case purchasing
    case purchased(productID: String)
    case activating
    case activated(productID: String)
    case awaitingBackendRetry(productID: String)
    case pending
    case cancelled
    case failed(String)
}

enum StoreKitPurchaseError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction
    case subscriptionNotCurrent

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "This subscription option is temporarily unavailable. Please try again shortly."
        case .unverifiedTransaction:
            return "The App Store transaction could not be verified."
        case .subscriptionNotCurrent:
            return "The App Store returned a subscription that is no longer current. Renew it in Apple Subscriptions, or clear this Sandbox account's purchase history before testing again."
        }
    }
}

struct BusinessStoreKitProductSummary: Identifiable, Hashable {
    let id: String
    let plan: BusinessSubscriptionPlan
    let displayName: String
    let displayPrice: String
    let description: String
}

@MainActor
final class StoreKitPurchaseService: ObservableObject {
    static let productIDs = Set(BusinessSubscriptionPlan.allCases.map(\.productID))

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var state: StoreKitPaymentState = .idle

    private var transactionUpdatesTask: Task<Void, Never>?

    private struct VerifiedStoreKitTransaction {
        let transaction: Transaction
        let signedJWS: String
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var businessProductSummaries: [BusinessStoreKitProductSummary] {
        products.compactMap { product in
            guard let plan = BusinessSubscriptionPlan.plan(forProductID: product.id) else { return nil }

            return BusinessStoreKitProductSummary(
                id: product.id,
                plan: plan,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                description: product.description
            )
        }
        .sorted { $0.plan.placementRank < $1.plan.placementRank }
    }

    func businessProductSummary(for plan: BusinessSubscriptionPlan) -> BusinessStoreKitProductSummary? {
        businessProductSummaries.first { $0.plan == plan }
    }

    func startTransactionListener() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                do {
                    guard let self else { return }
                    let verified = try self.verifiedTransaction(from: result)
                    let transaction = verified.transaction
                    guard Self.productIDs.contains(transaction.productID) else {
                        await transaction.finish()
                        continue
                    }
                    try await self.requireCurrentSubscription(transaction)
                    self.purchasedProductIDs.insert(transaction.productID)
                    self.state = .awaitingBackendRetry(productID: transaction.productID)
                } catch {
                    self?.setFailure("A purchase update could not be verified.")
                }
            }
        }
    }

    func stopTransactionListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }

    func resetAccountPresentationState() {
        purchasedProductIDs = []
        state = .idle
    }

    func loadProducts() async {
        guard !Self.productIDs.isEmpty else {
            products = []
            state = .productsUnavailable
            return
        }

        if !products.isEmpty {
            await refreshCurrentEntitlements()
            state = .ready(productCount: products.count)
            return
        }

        state = .loadingProducts

#if DEBUG
        print("[StoreKit] Requesting products: \(Self.productIDs.sorted())")
#endif

        do {
            let loadedProducts = try await Product.products(for: Array(Self.productIDs))
#if DEBUG
            let returnedIDs = loadedProducts.map(\.id).sorted()
            let missingIDs = Self.productIDs.subtracting(returnedIDs).sorted()
            print("[StoreKit] Returned products: \(returnedIDs)")
            if !missingIDs.isEmpty {
                print("[StoreKit] Missing products: \(missingIDs)")
            }
#endif
            products = loadedProducts.sorted { lhs, rhs in
                let lhsRank = Self.productSortRank(for: lhs.id)
                let rhsRank = Self.productSortRank(for: rhs.id)
                return lhsRank < rhsRank
            }
            await refreshCurrentEntitlements()
            state = products.isEmpty ? .productsUnavailable : .ready(productCount: products.count)
        } catch {
#if DEBUG
            print("[StoreKit] Product request failed: \(String(reflecting: error))")
#endif
            state = .failed("App Store subscription options could not be loaded.")
        }
    }

    @discardableResult
    func purchaseBusinessSubscription(_ plan: BusinessSubscriptionPlan) async throws -> Transaction? {
        if products.isEmpty {
            await loadProducts()
        }

        guard let product = products.first(where: { $0.id == plan.productID }) else {
            state = .productsUnavailable
            throw StoreKitPurchaseError.productUnavailable
        }

        state = .purchasing

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let verified = try verifiedTransaction(from: verification)
            let transaction = verified.transaction
            try await requireCurrentSubscription(transaction)
            purchasedProductIDs.insert(transaction.productID)
            state = .purchased(productID: transaction.productID)
            return transaction
        case .userCancelled:
            state = .cancelled
            return nil
        case .pending:
            state = .pending
            return nil
        @unknown default:
            state = .failed("The purchase could not be completed.")
            return nil
        }
    }

    @discardableResult
    func purchaseBusinessSubscription(
        _ plan: BusinessSubscriptionPlan,
        intent: AppleBusinessSubscriptionIntent,
        accessToken: String,
        processor: AppleBusinessSubscriptionProcessing
    ) async throws -> AppleBusinessSubscriptionBackendResult? {
        if products.isEmpty {
            await loadProducts()
        }

        guard intent.productID == plan.productID,
              let product = products.first(where: { $0.id == plan.productID }) else {
            state = .productsUnavailable
            throw StoreKitPurchaseError.productUnavailable
        }

        state = .purchasing

        let result = try await product.purchase(options: [.appAccountToken(intent.appAccountToken)])

        switch result {
        case .success(let verification):
            let verified = try verifiedTransaction(from: verification)
            try await requireCurrentSubscription(verified.transaction)
            return try await activateVerifiedSubscription(
                verified,
                intent: intent,
                accessToken: accessToken,
                processor: processor
            )
        case .userCancelled:
            state = .cancelled
            return nil
        case .pending:
            state = .pending
            return nil
        @unknown default:
            state = .failed("The purchase could not be completed.")
            return nil
        }
    }

    @discardableResult
    func activateExistingBusinessSubscription(
        _ plan: BusinessSubscriptionPlan,
        intent: AppleBusinessSubscriptionIntent,
        accessToken: String,
        processor: AppleBusinessSubscriptionProcessing
    ) async throws -> AppleBusinessSubscriptionBackendResult? {
        guard intent.productID == plan.productID else {
            state = .productsUnavailable
            throw StoreKitPurchaseError.productUnavailable
        }

        guard let verified = await currentVerifiedTransaction(for: plan.productID) else {
            purchasedProductIDs.remove(plan.productID)
            state = .productsUnavailable
            return nil
        }

        try await requireCurrentSubscription(verified.transaction)

        return try await activateVerifiedSubscription(
            verified,
            intent: intent,
            accessToken: accessToken,
            processor: processor
        )
    }

    func refreshCurrentEntitlements() async {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                activeProductIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeProductIDs
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> VerifiedStoreKitTransaction {
        switch result {
        case .verified(let transaction):
            return VerifiedStoreKitTransaction(
                transaction: transaction,
                signedJWS: result.jwsRepresentation
            )
        case .unverified:
            throw StoreKitPurchaseError.unverifiedTransaction
        }
    }

    private func evidence(from verified: VerifiedStoreKitTransaction) -> StoreKitVerifiedTransactionEvidence {
        let transaction = verified.transaction
        return StoreKitVerifiedTransactionEvidence(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            signedTransactionJWS: verified.signedJWS,
            appAccountToken: transaction.appAccountToken
        )
    }

    private func currentVerifiedTransaction(for productID: String) async -> VerifiedStoreKitTransaction? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID else { continue }
            return VerifiedStoreKitTransaction(
                transaction: transaction,
                signedJWS: result.jwsRepresentation
            )
        }

        return nil
    }

    private func activateVerifiedSubscription(
        _ verified: VerifiedStoreKitTransaction,
        intent: AppleBusinessSubscriptionIntent,
        accessToken: String,
        processor: AppleBusinessSubscriptionProcessing
    ) async throws -> AppleBusinessSubscriptionBackendResult {
        let transaction = verified.transaction
        try await requireCurrentSubscription(transaction)
        state = .activating
        let backendResult = try await processor.processVerifiedSubscription(
            evidence: evidence(from: verified),
            intent: intent,
            accessToken: accessToken
        )
        if backendResult.grantsCurrentAccess {
            await transaction.finish()
            purchasedProductIDs.insert(transaction.productID)
            state = .activated(productID: transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
            state = .awaitingBackendRetry(productID: transaction.productID)
        }
        return backendResult
    }

    private func requireCurrentSubscription(_ transaction: Transaction) async throws {
        if transaction.revocationDate != nil {
            await transaction.finish()
            purchasedProductIDs.remove(transaction.productID)
            state = .failed(StoreKitPurchaseError.subscriptionNotCurrent.localizedDescription)
            throw StoreKitPurchaseError.subscriptionNotCurrent
        }

        if let expirationDate = transaction.expirationDate,
           expirationDate <= Date() {
            await transaction.finish()
            purchasedProductIDs.remove(transaction.productID)
            state = .failed(StoreKitPurchaseError.subscriptionNotCurrent.localizedDescription)
            throw StoreKitPurchaseError.subscriptionNotCurrent
        }
    }

    private func setFailure(_ message: String) {
        state = .failed(message)
    }

    private static func productSortRank(for productID: String) -> Int {
        if let plan = BusinessSubscriptionPlan.plan(forProductID: productID) {
            return plan.placementRank
        }
        return Int.max
    }
}
