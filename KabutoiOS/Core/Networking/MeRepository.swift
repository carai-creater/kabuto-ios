import Foundation

/// Shape of `GET /api/v1/me` — matches the kabuto route's JSON payload.
struct MeResponse: Decodable, Sendable {
    let ok: Bool
    let user: Me?
}

struct Me: Decodable, Sendable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let avatarUrl: URL?
    let role: String
    let bio: String?
    let websiteUrl: URL?
    let xUrl: URL?
    let walletBalancePt: Int

    enum CodingKeys: String, CodingKey {
        case id, email, name, role, bio
        case avatarUrl = "avatar_url"
        case websiteUrl = "website_url"
        case xUrl = "x_url"
        case walletBalancePt = "wallet_balance_pt"
    }
}

/// Thin wrapper around APIClient for the `/me` endpoint. Each feature that
/// needs "who am I" depends on this so the URL lives in one place.
struct MeRepository: Sendable {
    let api: APIClient

    func fetch() async throws -> Me {
        let endpoint = APIEndpoint<MeResponse>(path: "api/v1/me", method: .get)
        let response = try await api.send(endpoint)
        guard let user = response.user else {
            throw APIError.invalidResponse
        }
        return user
    }
}
