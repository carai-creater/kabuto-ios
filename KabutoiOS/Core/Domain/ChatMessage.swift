import Foundation

/// In-memory chat message. The wire format only distinguishes `user` and
/// `assistant` for Phase 4 — reasoning, tool calls, files are deferred.
struct ChatMessage: Identifiable, Sendable, Hashable {
    let id: String
    var role: Role
    var content: String
    var isStreaming: Bool

    enum Role: String, Sendable, Hashable {
        case user, assistant, system
    }

    init(id: String = UUID().uuidString, role: Role, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

/// Shape of `GET /api/v1/chat-history` responses.
struct ChatHistoryResponse: Decodable, Sendable {
    let ok: Bool
    let sessionId: String?
    let messages: [HistoryMessage]

    enum CodingKeys: String, CodingKey {
        case ok, messages
        case sessionId = "session_id"
    }

    struct HistoryMessage: Decodable, Sendable {
        let id: String
        let role: String
        let content: String
    }
}
