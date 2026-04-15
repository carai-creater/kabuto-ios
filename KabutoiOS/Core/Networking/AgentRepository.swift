import Foundation

/// All `/api/v1/agents*` traffic in one place. Reads are anonymous;
/// mutations throw `APIError.status` when Bearer is missing or rejected.
struct AgentRepository: Sendable {
    let api: APIClient

    // MARK: - Queries

    enum Sort: String, Sendable {
        case usage
        case new
        case rating
    }

    struct ListResponse: Decodable, Sendable {
        let ok: Bool
        let items: [Agent]
    }

    func list(query: String = "", tag: String = "", sort: Sort = .usage, limit: Int = 50) async throws -> [Agent] {
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        items.append(URLQueryItem(name: "limit", value: String(limit)))

        let endpoint = APIEndpoint<ListResponse>(
            path: "api/v1/agents",
            method: .get,
            queryItems: items,
            requiresAuth: false
        )
        return try await api.send(endpoint).items
    }

    struct DetailResponse: Decodable, Sendable {
        let ok: Bool
        let agent: AgentDetail
        let reviews: [Review]
        let isFavorited: Bool
        let viewerIsCreator: Bool

        enum CodingKeys: String, CodingKey {
            case ok, agent, reviews
            case isFavorited = "is_favorited"
            case viewerIsCreator = "viewer_is_creator"
        }
    }

    func detail(slug: String) async throws -> DetailResponse {
        let endpoint = APIEndpoint<DetailResponse>(
            path: "api/v1/agents/\(slug)",
            method: .get,
            requiresAuth: false
        )
        return try await api.send(endpoint)
    }

    // MARK: - Mutations (require auth)

    struct FavoriteResponse: Decodable, Sendable {
        let ok: Bool
        let favorited: Bool
    }

    func setFavorite(slug: String, favorited: Bool) async throws -> Bool {
        let endpoint = APIEndpoint<FavoriteResponse>(
            path: "api/v1/agents/\(slug)/favorite",
            method: favorited ? .post : .delete,
            requiresAuth: true
        )
        return try await api.send(endpoint).favorited
    }

    struct ReviewBody: Encodable, Sendable {
        let rating: Int
        let comment: String?
    }

    struct AckResponse: Decodable, Sendable {
        let ok: Bool
    }

    func submitReview(slug: String, rating: Int, comment: String?) async throws {
        let body = ReviewBody(
            rating: rating,
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let endpoint = APIEndpoint<AckResponse>(
            path: "api/v1/agents/\(slug)/reviews",
            method: .post,
            body: body,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
