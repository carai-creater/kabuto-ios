import Foundation

/// `GET /api/v1/creator/agents` list row. Includes drafts AND published
/// (unlike `Agent` from the public marketplace endpoints).
struct CreatorAgent: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let iconEmoji: String
    let isPublished: Bool
    let pricePerUsePt: Double
    let usageCount: Int
    let ratingAvg: Double
    let reviewCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description
        case iconEmoji = "icon_emoji"
        case isPublished = "is_published"
        case pricePerUsePt = "price_per_use_pt"
        case usageCount = "usage_count"
        case ratingAvg = "rating_avg"
        case reviewCount = "review_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// JSON body for `POST /api/v1/creator/agents` and
/// `PATCH /api/v1/creator/agents/:slug`. Matches the server's
/// `createAgentPayloadSchema` (camelCase — server zod schema uses
/// camelCase keys, NOT snake_case, so we match the existing server
/// contract directly).
struct CreateAgentBody: Codable, Sendable {
    var title: String
    var description: String
    var instructions: String
    var iconEmoji: String
    var conversationStarters: [String]
    var pricePerUsePt: Int
    var defaultLlm: String
    var useRecommendedModel: Bool
    var capabilities: Capabilities
    var actions: Actions
    var mcp: Mcp
    var mcpServices: [String]

    struct Capabilities: Codable, Sendable {
        var webSearch: Bool = false
        var canvas: Bool = false
        var imageGeneration: Bool = false
        var codeInterpreter: Bool = false
    }

    struct Actions: Codable, Sendable {
        var authType: String = "none"
        var openApiSchema: String = ""
        var privacyPolicyUrl: String = ""
    }

    struct Mcp: Codable, Sendable {
        var enabled: Bool = false
        var serverKey: String = ""
        var endpointUrl: String = ""
        var instruction: String = ""
    }

    /// A minimal, sensible default body iOS creators start from in the
    /// editor. Only the first six fields are exposed in Phase 6 UI.
    static func blank() -> CreateAgentBody {
        CreateAgentBody(
            title: "",
            description: "",
            instructions: "",
            iconEmoji: "🤖",
            conversationStarters: [],
            pricePerUsePt: 10,
            defaultLlm: "gpt-4o",
            useRecommendedModel: true,
            capabilities: Capabilities(),
            actions: Actions(),
            mcp: Mcp(),
            mcpServices: []
        )
    }
}

/// Response envelopes

struct CreatorListResponse: Decodable, Sendable {
    let ok: Bool
    let items: [CreatorAgent]
}

struct CreatorCreateResponse: Decodable, Sendable {
    let ok: Bool
    let id: String
    let slug: String
}

struct OkResponse: Decodable, Sendable {
    let ok: Bool
}

struct PublishResponse: Decodable, Sendable {
    let ok: Bool
    let isPublished: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case isPublished = "is_published"
    }
}

struct PublishBody: Encodable, Sendable {
    let publish: Bool
}
