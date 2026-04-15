import Foundation

/// Minimal surface ChatViewModel depends on. Makes the view model
/// testable via an in-memory fake without building a URLSession stack.
protocol ChatStreaming: Sendable {
    func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse
    func streamChat(
        messages: [ChatMessage],
        agentId: String?,
        modelId: String?,
        idempotencyKey: String
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
}

/// All `/api/v1/chat*` traffic. Streaming sends use the SSE client
/// directly because `APIClient` only does JSON request/response.
struct ChatRepository: Sendable, ChatStreaming {
    let baseURL: URL
    let sseClient: SSEClient
    let tokenProvider: @Sendable () async -> String?
    let api: APIClient

    // MARK: - History

    func history(agentId: String, limit: Int = 100) async throws -> ChatHistoryResponse {
        let endpoint = APIEndpoint<ChatHistoryResponse>(
            path: "api/v1/chat-history",
            method: .get,
            queryItems: [
                URLQueryItem(name: "agentId", value: agentId),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            requiresAuth: true
        )
        return try await api.send(endpoint)
    }

    // MARK: - Stream

    /// Body shape accepted by `/api/v1/chat`. Matches the Vercel AI SDK
    /// `UIMessage` shape the server passes to `convertToModelMessages`.
    struct RequestBody: Encodable, Sendable {
        let messages: [UIMessage]
        let modelId: String?
        let agentId: String?
        let idempotencyKey: String?

        enum CodingKeys: String, CodingKey {
            case messages, modelId, agentId, idempotencyKey
        }

        struct UIMessage: Encodable, Sendable {
            let id: String
            let role: String
            let parts: [Part]

            struct Part: Encodable, Sendable {
                let type: String
                let text: String
            }
        }
    }

    func streamChat(
        messages: [ChatMessage],
        agentId: String?,
        modelId: String?,
        idempotencyKey: String
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let body = RequestBody(
            messages: messages.map { msg in
                RequestBody.UIMessage(
                    id: msg.id,
                    role: msg.role.rawValue,
                    parts: [.init(type: "text", text: msg.content)]
                )
            },
            modelId: modelId,
            agentId: agentId,
            idempotencyKey: idempotencyKey
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(body)
        let token = await tokenProvider()
        return sseClient.stream(
            url: baseURL.appendingPathComponent("api/v1/chat"),
            body: encoded,
            bearerToken: token
        )
    }
}
