import Foundation

/// `GET /api/v1/wallet` payload.
struct WalletSnapshot: Decodable, Sendable {
    let ok: Bool
    let balancePt: Int
    let updatedAt: Date?
    let recentPurchases: [PurchaseRow]
    let recentUsages: [UsageRow]

    enum CodingKeys: String, CodingKey {
        case ok
        case balancePt = "balance_pt"
        case updatedAt = "updated_at"
        case recentPurchases = "recent_purchases"
        case recentUsages = "recent_usages"
    }

    struct PurchaseRow: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let amountPt: Int
        let amountYen: Int
        let source: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, source
            case amountPt = "amount_pt"
            case amountYen = "amount_yen"
            case createdAt = "created_at"
        }
    }

    struct UsageRow: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let agentId: String?
        let amountPt: Int
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case agentId = "agent_id"
            case amountPt = "amount_pt"
            case createdAt = "created_at"
        }
    }
}

/// `GET /api/v1/wallet/history` payload.
struct WalletHistoryPage: Decodable, Sendable {
    let ok: Bool
    let items: [HistoryEntry]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case ok, items
        case nextCursor = "next_cursor"
    }
}

struct HistoryEntry: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let kind: String // "purchase" | "usage"
    let amountPt: Int
    let amountYen: Int?
    let source: String?
    let agentId: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, source
        case amountPt = "amount_pt"
        case amountYen = "amount_yen"
        case agentId = "agent_id"
        case createdAt = "created_at"
    }
}

/// `POST /api/v1/wallet/iap/grant` response.
struct IapGrantResponse: Decodable, Sendable {
    let ok: Bool
    let alreadyGranted: Bool
    let amountPt: Int
    let balancePt: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case alreadyGranted = "already_granted"
        case amountPt = "amount_pt"
        case balancePt = "balance_pt"
    }
}
