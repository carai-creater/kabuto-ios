import XCTest
@testable import KabutoiOS

@MainActor
final class ChatPersistenceTests: XCTestCase {

    /// Minimal reuse of the Phase 4 fake — we only need it to return a
    /// clean stream so we can observe the onFinishedPersist callback.
    final class FakeChatStreaming: ChatStreaming, @unchecked Sendable {
        func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse {
            ChatHistoryResponse(ok: true, sessionId: nil, messages: [])
        }
        func streamChat(
            messages: [ChatMessage],
            agentId: String?,
            modelId: String?,
            idempotencyKey: String
        ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.textStart(id: "a"))
                continuation.yield(.textDelta(id: "a", delta: "hi"))
                continuation.yield(.textEnd(id: "a"))
                continuation.yield(.finish)
                continuation.finish()
            }
        }
    }

    /// A11 — after a successful stream, the persistence hook receives
    /// the full message list (user + assistant) for save.
    func testOnFinishedPersistReceivesFullMessageList() async throws {
        let captured = UnsafeSendableBox<[ChatMessage]?>(value: nil)
        let vm = ChatViewModel(
            slug: "demo",
            agent: nil,
            repository: FakeChatStreaming(),
            onFinishedPersist: { messages in
                captured.value = messages
            }
        )

        vm.send(userText: "hello")

        // Wait for stream to finish + the fire-and-forget persist task.
        for _ in 0..<200 where captured.value == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let messages = try XCTUnwrap(captured.value, "persist hook should have fired")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "hello")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "hi")
        XCTAssertFalse(messages[1].isStreaming)
    }

    /// Failure path: the persist hook must NOT be called when the stream
    /// errors out — the assistant placeholder was never filled.
    func testOnFinishedPersistNotCalledOnFailure() async throws {
        struct Boom: Error {}
        final class BadStream: ChatStreaming, @unchecked Sendable {
            func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse {
                ChatHistoryResponse(ok: true, sessionId: nil, messages: [])
            }
            func streamChat(
                messages: [ChatMessage],
                agentId: String?,
                modelId: String?,
                idempotencyKey: String
            ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: Boom())
                }
            }
        }

        let captured = UnsafeSendableBox<[ChatMessage]?>(value: nil)
        let vm = ChatViewModel(
            slug: "demo",
            agent: nil,
            repository: BadStream(),
            onFinishedPersist: { messages in
                captured.value = messages
            }
        )

        vm.send(userText: "hello")

        // Give the failure path a moment to run.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(captured.value, "persist hook must not fire on stream failure")
    }
}
