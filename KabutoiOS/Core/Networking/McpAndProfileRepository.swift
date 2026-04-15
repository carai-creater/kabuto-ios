import Foundation

struct ProfileRepository: Sendable {
    let api: APIClient

    func patch(_ body: ProfilePatchBody) async throws {
        let endpoint = APIEndpoint<OkResponse>(
            path: "api/v1/me/profile",
            method: .patch,
            body: body,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }
}

struct McpRepository: Sendable {
    let api: APIClient

    func list() async throws -> [McpConnection] {
        let endpoint = APIEndpoint<McpListResponse>(
            path: "api/v1/mcp/connections",
            method: .get,
            requiresAuth: true
        )
        return try await api.send(endpoint).items
    }

    func upsert(serverKey: String, label: String, credential: String) async throws {
        let body = McpUpsertBody(serverKey: serverKey, label: label, credential: credential)
        let endpoint = APIEndpoint<OkResponse>(
            path: "api/v1/mcp/connections",
            method: .post,
            body: body,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }

    func delete(serverKey: String) async throws {
        let endpoint = APIEndpoint<OkResponse>(
            path: "api/v1/mcp/connections/\(serverKey)",
            method: .delete,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }
}

/// A11: iOS turns get persisted via this after each stream finishes.
struct ChatHistoryRepository: Sendable {
    let api: APIClient

    func save(agentIdOrSlug: String, sessionId: String?, messages: [ChatMessage]) async throws -> String? {
        let body = ChatHistorySaveBody(
            agentIdOrSlug: agentIdOrSlug,
            sessionId: sessionId,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        )
        let endpoint = APIEndpoint<ChatHistorySaveResponse>(
            path: "api/v1/chat-history/save",
            method: .post,
            body: body,
            requiresAuth: true
        )
        return try await api.send(endpoint).sessionId
    }
}
