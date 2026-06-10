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
    case pending
    case cancelled
    case failed(String)
}

enum StoreKitPurchaseError: LocalizedError {
    case missingProductID
    case productUnavailable
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .missingProductID:
            return "This listing option does not have an App Store product."
        case .productUnavailable:
            return "This purchase option is not available yet."
        case .unverifiedTransaction:
            return "The App Store transaction could not be verified."
        }
    }
}

struct StoreKitProductSummary: Identifiable, Hashable {
    let id: String
    let tier: ListingTier
    let displayName: String
    let displayPrice: String
    let description: String
}

@MainActor
final class StoreKitPurchaseService: ObservableObject {
    static let productIDs = Set(ListingTier.allCases.compactMap(\.storeKitProductID))

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var state: StoreKitPaymentState = .idle

    private var transactionUpdatesTask: Task<Void, Never>?

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var productSummaries: [StoreKitProductSummary] {
        products.compactMap { product in
            guard let tier = ListingTier.tier(forStoreKitProductID: product.id) else { return nil }

            return StoreKitProductSummary(
                id: product.id,
                tier: tier,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                description: product.description
            )
        }
        .sorted { $0.tier.sortRank < $1.tier.sortRank }
    }

    func startTransactionListener() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try verifiedTransaction(from: result)
                    purchasedProductIDs.insert(transaction.productID)
                    await transaction.finish()
                } catch {
                    state = .failed("A purchase update could not be verified.")
                }
            }
        }
    }

    func stopTransactionListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }

    func loadProducts() async {
        guard !Self.productIDs.isEmpty else {
            products = []
            state = .productsUnavailable
            return
        }

        state = .loadingProducts

        do {
            let loadedProducts = try await Product.products(for: Array(Self.productIDs))
            products = loadedProducts.sorted { lhs, rhs in
                let lhsRank = ListingTier.tier(forStoreKitProductID: lhs.id)?.sortRank ?? Int.max
                let rhsRank = ListingTier.tier(forStoreKitProductID: rhs.id)?.sortRank ?? Int.max
                return lhsRank < rhsRank
            }
            await refreshCurrentEntitlements()
            state = products.isEmpty ? .productsUnavailable : .ready(productCount: products.count)
        } catch {
            state = .failed("App Store purchase options could not be loaded.")
        }
    }

    @discardableResult
    func purchase(_ tier: ListingTier) async throws -> Transaction? {
        guard let productID = tier.storeKitProductID else {
            throw StoreKitPurchaseError.missingProductID
        }

        if products.isEmpty {
            await loadProducts()
        }

        guard let product = products.first(where: { $0.id == productID }) else {
            state = .productsUnavailable
            throw StoreKitPurchaseError.productUnavailable
        }

        state = .purchasing

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
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

    func refreshCurrentEntitlements() async {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                activeProductIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeProductIDs
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw StoreKitPurchaseError.unverifiedTransaction
        }
    }
}

extension ListingTier {
    static func tier(forStoreKitProductID productID: String) -> ListingTier? {
        allCases.first { $0.storeKitProductID == productID }
    }
}
