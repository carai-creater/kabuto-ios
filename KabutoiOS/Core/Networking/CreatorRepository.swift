import Foundation

/// All `/api/v1/creator/*` traffic.
struct CreatorRepository: Sendable {
    let api: APIClient

    func listMyAgents() async throws -> [CreatorAgent] {
        let endpoint = APIEndpoint<CreatorListResponse>(
            path: "api/v1/creator/agents",
            method: .get,
            requiresAuth: true
        )
        return try await api.send(endpoint).items
    }

    func create(_ body: CreateAgentBody) async throws -> CreatorCreateResponse {
        let endpoint = APIEndpoint<CreatorCreateResponse>(
            path: "api/v1/creator/agents",
            method: .post,
            body: body,
            requiresAuth: true
        )
        return try await api.send(endpoint)
    }

    func update(slug: String, body: CreateAgentBody) async throws {
        let endpoint = APIEndpoint<OkResponse>(
            path: "api/v1/creator/agents/\(slug)",
            method: .patch,
            body: body,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }

    func setPublish(slug: String, publish: Bool) async throws -> Bool {
        let endpoint = APIEndpoint<PublishResponse>(
            path: "api/v1/creator/agents/\(slug)",
            method: .post,
            body: PublishBody(publish: publish),
            requiresAuth: true
        )
        return try await api.send(endpoint).isPublished
    }
}
