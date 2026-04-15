import Foundation

// MARK: - MCP connections

struct McpConnection: Decodable, Sendable, Identifiable, Hashable {
    var id: String { serverKey }
    let serverKey: String
    let label: String
    let connectedAt: Date

    enum CodingKeys: String, CodingKey {
        case label
        case serverKey = "server_key"
        case connectedAt = "connected_at"
    }
}

struct McpListResponse: Decodable, Sendable {
    let ok: Bool
    let items: [McpConnection]
}

struct McpUpsertBody: Encodable, Sendable {
    let serverKey: String
    let label: String
    let credential: String

    enum CodingKeys: String, CodingKey {
        case label, credential
        case serverKey = "server_key"
    }
}

// MARK: - Profile patch body

/// `PATCH /api/v1/me/profile` request body. All fields optional — only
/// the keys sent are updated (server-side zod skips `undefined`).
struct ProfilePatchBody: Encodable, Sendable {
    let name: String?
    let avatarUrl: String?
    let websiteUrl: String?
    let xUrl: String?
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case name, bio
        case avatarUrl = "avatar_url"
        case websiteUrl = "website_url"
        case xUrl = "x_url"
    }
}

// MARK: - Chat history save (A11)

struct ChatHistorySaveBody: Encodable, Sendable {
    let agentIdOrSlug: String
    let sessionId: String?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case messages
        case agentIdOrSlug = "agent_id_or_slug"
        case sessionId = "session_id"
    }

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }
}

struct ChatHistorySaveResponse: Decodable, Sendable {
    let ok: Bool
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case sessionId = "session_id"
    }
}
