import Foundation
import StoreKit

/// Abstract surface the wallet feature depends on. Tests inject an
/// in-memory fake; production uses `LiveStoreKitService`.
///
/// All surfaces are `@MainActor` because StoreKit 2 Transaction
/// observation wants to be on the main actor in SwiftUI apps.
@MainActor
protocol StoreKitServicing: AnyObject {
    /// Loaded products keyed by productId. Empty until `loadProducts()`
    /// has resolved (or if the App Store Connect config is missing).
    var products: [String: StoreKitProductSummary] { get }

    /// Last error encountered during load or purchase, for UI surface.
    var lastError: String? { get }

    func loadProducts() async
    func purchase(productId: String) async throws -> StoreKitPurchaseResult

    /// Listen for transactions delivered by StoreKit at any time
    /// (deferred purchases, post-reinstall backfill, parental consent).
    /// Caller hands the transactions back to the server then calls
    /// `finish(transactionId:)`.
    func beginObservingTransactions(handler: @escaping @MainActor (StoreKitPendingTransaction) async -> Void)

    /// Call after the server has confirmed the transaction so StoreKit
    /// stops redelivering it.
    func finish(transactionId: String) async
}

/// Minimal projection of `Product`. Avoids exposing StoreKit types past
/// the service boundary so fakes don't need real `Product` instances.
struct StoreKitProductSummary: Sendable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let displayPrice: String
}

/// Pending transaction the server has yet to grant. Carries only the
/// fields we send to `/api/v1/wallet/iap/grant`.
struct StoreKitPendingTransaction: Sendable, Hashable {
    let productId: String
    let transactionId: String
    let signedJWS: String
}

/// Outcome of a user-initiated purchase call.
enum StoreKitPurchaseResult: Sendable {
    case unavailable
    case success(StoreKitPendingTransaction)
    case pending
    case userCancelled
}

enum StoreKitError: Error, CustomStringConvertible {
    case verificationFailed
    case unknown(String)
    var description: String {
        switch self {
        case .verificationFailed: return "トランザクションの検証に失敗しました"
        case .unknown(let msg): return msg
        }
    }
}

/// Real StoreKit 2 implementation. Gracefully no-ops when the App Store
/// Connect products aren't configured yet (dev / CI / pre-launch builds):
/// `products` stays empty and `purchase` returns `.unavailable`.
@MainActor
final class LiveStoreKitService: StoreKitServicing {
    private(set) var products: [String: StoreKitProductSummary] = [:]
    private(set) var lastError: String?

    private var loadedProducts: [String: Product] = [:]
    private var observerTask: Task<Void, Never>?

    func loadProducts() async {
        do {
            let result = try await Product.products(for: WalletPackages.productIds)
            loadedProducts = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
            products = Dictionary(
                uniqueKeysWithValues: result.map { product in
                    (product.id, StoreKitProductSummary(
                        id: product.id,
                        displayName: product.displayName,
                        displayPrice: product.displayPrice
                    ))
                }
            )
            lastError = nil
        } catch {
            // App Store Connect may not have the products configured yet
            // — this is fine, the UI will show "現在購入不可".
            products = [:]
            loadedProducts = [:]
            lastError = error.localizedDescription
        }
    }

    func purchase(productId: String) async throws -> StoreKitPurchaseResult {
        guard let product = loadedProducts[productId] else {
            return .unavailable
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            return .success(StoreKitPendingTransaction(
                productId: transaction.productID,
                transactionId: String(transaction.id),
                signedJWS: verification.jwsRepresentation
            ))
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .unavailable
        }
    }

    func beginObservingTransactions(
        handler: @escaping @MainActor (StoreKitPendingTransaction) async -> Void
    ) {
        observerTask?.cancel()
        observerTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            for await update in Transaction.updates {
                do {
                    let transaction = try Self.checkVerifiedStatic(update)
                    let pending = StoreKitPendingTransaction(
                        productId: transaction.productID,
                        transactionId: String(transaction.id),
                        signedJWS: update.jwsRepresentation
                    )
                    await handler(pending)
                } catch {
                    Log.app.error("unverified transaction: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    func finish(transactionId: String) async {
        guard let idInt = UInt64(transactionId) else { return }
        for await result in Transaction.unfinished {
            switch result {
            case .verified(let transaction):
                if transaction.id == idInt {
                    await transaction.finish()
                    return
                }
            case .unverified:
                continue
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreKitError.verificationFailed
        }
    }

    private static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreKitError.verificationFailed
        }
    }
}
