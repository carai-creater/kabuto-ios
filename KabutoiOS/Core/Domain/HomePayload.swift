import Foundation

/// Shape of `GET /api/v1/home`. Signed-out users receive only the list
/// sections; signed-in users additionally receive the four "mine" fields.
struct HomePayload: Decodable, Sendable {
    let ok: Bool
    let isAuthenticated: Bool
    let recommended: [Agent]
    let hot: [Agent]
    let newArrivals: [Agent]

    let walletBalancePt: Int?
    let recentSessions: [RecentSessionLine]?
    let favorites: [FavoriteCard]?

    enum CodingKeys: String, CodingKey {
        case ok, recommended, hot, favorites
        case isAuthenticated = "is_authenticated"
        case newArrivals = "new_arrivals"
        case walletBalancePt = "wallet_balance_pt"
        case recentSessions = "recent_sessions"
    }
}

struct RecentSessionLine: Decodable, Sendable, Hashable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let iconEmoji: String
    let iconUrl: URL?
    let lastAt: Date

    enum CodingKeys: String, CodingKey {
        case slug, title
        case iconEmoji = "icon_emoji"
        case iconUrl = "icon_url"
        case lastAt = "last_at"
    }
}

struct FavoriteCard: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let iconEmoji: String
    let iconUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id, slug, title
        case iconEmoji = "icon_emoji"
        case iconUrl = "icon_url"
    }
}
