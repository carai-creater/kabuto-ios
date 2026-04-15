import Foundation

/// Minimal surface WalletViewModel depends on. Tests provide an
/// in-memory fake so they don't need a URLSession stack.
protocol WalletReading: Sendable {
    func fetchWallet() async throws -> WalletSnapshot
    func fetchHistory(cursor: String?, limit: Int) async throws -> WalletHistoryPage
    func grantIAP(_ pending: StoreKitPendingTransaction) async throws -> IapGrantResponse
}

struct WalletRepository: Sendable, WalletReading {
    let api: APIClient

    func fetchWallet() async throws -> WalletSnapshot {
        try await api.send(APIEndpoint<WalletSnapshot>(
            path: "api/v1/wallet",
            method: .get,
            requiresAuth: true
        ))
    }

    func fetchHistory(cursor: String? = nil, limit: Int = 30) async throws -> WalletHistoryPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await api.send(APIEndpoint<WalletHistoryPage>(
            path: "api/v1/wallet/history",
            method: .get,
            queryItems: items,
            requiresAuth: true
        ))
    }

    struct GrantBody: Encodable, Sendable {
        let productId: String
        let transactionId: String
        let signedTransactionJws: String

        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case transactionId = "transaction_id"
            case signedTransactionJws = "signed_transaction_jws"
        }
    }

    func grantIAP(_ pending: StoreKitPendingTransaction) async throws -> IapGrantResponse {
        let body = GrantBody(
            productId: pending.productId,
            transactionId: pending.transactionId,
            signedTransactionJws: pending.signedJWS
        )
        return try await api.send(APIEndpoint<IapGrantResponse>(
            path: "api/v1/wallet/iap/grant",
            method: .post,
            body: body,
            requiresAuth: true
        ))
    }
}
