import Foundation

/// Summary card shape returned by `/api/v1/agents` and nested inside
/// `/api/v1/home`. Field names follow the kabuto `snake_case` contract.
struct Agent: Identifiable, Decodable, Sendable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let iconEmoji: String
    let iconUrl: URL?
    let pricePerUsePt: Double
    let usageCount: Int
    let ratingAvg: Double
    let reviewCount: Int
    let firstThreeFree: Bool
    let tags: [String]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, tags
        case iconEmoji = "icon_emoji"
        case iconUrl = "icon_url"
        case pricePerUsePt = "price_per_use_pt"
        case usageCount = "usage_count"
        case ratingAvg = "rating_avg"
        case reviewCount = "review_count"
        case firstThreeFree = "first_three_free"
        case createdAt = "created_at"
    }
}

struct ConversationStarter: Decodable, Sendable, Hashable, Identifiable {
    var id: Int { position }
    let position: Int
    let text: String
}

struct KnowledgeDocument: Decodable, Sendable, Hashable, Identifiable {
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

struct AgentCreator: Decodable, Sendable, Hashable {
    let name: String?
    let email: String
}

/// Detail card — `Agent` fields plus the server prompt / starters / creator.
struct AgentDetail: Decodable, Sendable, Identifiable, Hashable {
    // Summary fields (flat — the server returns them at the top level)
    let id: String
    let slug: String
    let title: String
    let description: String
    let iconEmoji: String
    let iconUrl: URL?
    let pricePerUsePt: Double
    let usageCount: Int
    let ratingAvg: Double
    let reviewCount: Int
    let firstThreeFree: Bool
    let tags: [String]
    let createdAt: Date?

    // Detail extras
    let systemPrompt: String
    let instructions: String?
    let defaultLlm: String?
    let creator: AgentCreator
    let conversationStarters: [ConversationStarter]
    let knowledgeDocuments: [KnowledgeDocument]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, tags, creator
        case iconEmoji = "icon_emoji"
        case iconUrl = "icon_url"
        case pricePerUsePt = "price_per_use_pt"
        case usageCount = "usage_count"
        case ratingAvg = "rating_avg"
        case reviewCount = "review_count"
        case firstThreeFree = "first_three_free"
        case createdAt = "created_at"
        case systemPrompt = "system_prompt"
        case instructions
        case defaultLlm = "default_llm"
        case conversationStarters = "conversation_starters"
        case knowledgeDocuments = "knowledge_documents"
    }

    /// Lossy projection back to the summary shape — handy for passing the
    /// already-loaded detail into views that take an `Agent`.
    var summary: Agent {
        Agent(
            id: id,
            slug: slug,
            title: title,
            description: description,
            iconEmoji: iconEmoji,
            iconUrl: iconUrl,
            pricePerUsePt: pricePerUsePt,
            usageCount: usageCount,
            ratingAvg: ratingAvg,
            reviewCount: reviewCount,
            firstThreeFree: firstThreeFree,
            tags: tags,
            createdAt: createdAt
        )
    }
}

struct Review: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let rating: Int
    let comment: String?
    let createdAt: Date
    let user: ReviewUser

    enum CodingKeys: String, CodingKey {
        case id, rating, comment, user
        case createdAt = "created_at"
    }
}

struct ReviewUser: Decodable, Sendable, Hashable {
    let id: String
    let name: String?
}
