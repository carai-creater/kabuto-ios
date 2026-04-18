import Foundation

/// Full detail of the signed-in user's own agent, as returned by
/// `GET /api/v1/creator/agents/:slug`. Phase 7 (A7) — gives iOS the
/// real instructions / capabilities / starters / mcp config so the
/// editor can preload them instead of starting blank.
struct CreatorAgentDetail: Decodable, Sendable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let iconEmoji: String
    let iconUrl: URL?
    /// Server maps DB `systemPrompt` → API `instructions` so iOS posts
    /// back unchanged on save.
    let instructions: String
    let legacyInstructions: String?
    let defaultLlm: String?
    let useRecommendedModel: Bool
    let pricePerUsePt: Double
    let isPublished: Bool
    let tags: [String]
    let conversationStarters: [Starter]
    let knowledgeDocuments: [Document]
    let capabilities: CreateAgentBody.Capabilities
    let actions: CreateAgentBody.Actions
    let mcp: CreateAgentBody.Mcp
    let mcpServices: [String]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, tags, actions, mcp, capabilities
        case iconEmoji = "icon_emoji"
        case iconUrl = "icon_url"
        case instructions
        case legacyInstructions = "legacy_instructions"
        case defaultLlm = "default_llm"
        case useRecommendedModel = "use_recommended_model"
        case pricePerUsePt = "price_per_use_pt"
        case isPublished = "is_published"
        case conversationStarters = "conversation_starters"
        case knowledgeDocuments = "knowledge_documents"
        case mcpServices = "mcp_services"
    }

    struct Starter: Decodable, Sendable, Hashable, Identifiable {
        var id: Int { position }
        let position: Int
        let text: String
    }

    struct Document: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let mimeType: String
        let storageKey: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title
            case mimeType = "mime_type"
            case storageKey = "storage_key"
            case createdAt = "created_at"
        }
    }

    /// Project this detail into the form body used for save. Fields not
    /// carried in the detail keep the caller's defaults.
    func toCreateAgentBody() -> CreateAgentBody {
        CreateAgentBody(
            title: title,
            description: description,
            instructions: instructions,
            iconEmoji: iconEmoji,
            conversationStarters: conversationStarters
                .sorted(by: { $0.position < $1.position })
                .map(\.text),
            pricePerUsePt: Int(pricePerUsePt),
            defaultLlm: defaultLlm ?? "gpt-4o",
            useRecommendedModel: useRecommendedModel,
            capabilities: capabilities,
            actions: actions,
            mcp: mcp,
            mcpServices: mcpServices
        )
    }
}

/// Envelopes for the knowledge upload flow.

struct CreatorDetailResponse: Decodable, Sendable {
    let ok: Bool
    let agent: CreatorAgentDetail
}

struct KnowledgeUploadURLBody: Encodable, Sendable {
    let filename: String
    let mimeType: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
    }
}

struct KnowledgeUploadURLResponse: Decodable, Sendable {
    let ok: Bool
    let signedUrl: URL
    let token: String
    let storageKey: String
    let expiresInSeconds: Int
    let maxBytes: Int

    enum CodingKeys: String, CodingKey {
        case ok, token
        case signedUrl = "signed_url"
        case storageKey = "storage_key"
        case expiresInSeconds = "expires_in_seconds"
        case maxBytes = "max_bytes"
    }
}

struct KnowledgeRegisterBody: Encodable, Sendable {
    let storageKey: String
    let title: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case title
        case storageKey = "storage_key"
        case mimeType = "mime_type"
    }
}

struct KnowledgeRegisterResponse: Decodable, Sendable {
    let ok: Bool
    let document: DocumentRow

    struct DocumentRow: Decodable, Sendable {
        let id: String
        let title: String
        let mimeType: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title
            case mimeType = "mime_type"
            case createdAt = "created_at"
        }
    }
}
