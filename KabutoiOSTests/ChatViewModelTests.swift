import XCTest
@testable import KabutoiOS

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Fakes

    /// Programmable fake. Records calls and returns a scripted sequence of
    /// events (or an error) for `streamChat`.
    final class FakeChatStreaming: ChatStreaming, @unchecked Sendable {
        var historyCalls: Int = 0
        var streamCalls: Int = 0
        var script: Result<[ChatStreamEvent], Error> = .success([])

        func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse {
            historyCalls += 1
            return ChatHistoryResponse(ok: true, sessionId: nil, messages: [])
        }

        func streamChat(
            messages: [ChatMessage],
            agentId: String?,
            modelId: String?,
            idempotencyKey: String
        ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
            streamCalls += 1
            let script = self.script
            return AsyncThrowingStream { continuation in
                switch script {
                case .success(let events):
                    for e in events { continuation.yield(e) }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Happy path

    func testSendAppendsUserAndStreamsAssistantDeltas() async throws {
        let fake = FakeChatStreaming()
        fake.script = .success([
            .textStart(id: "a"),
            .textDelta(id: "a", delta: "Hel"),
            .textDelta(id: "a", delta: "lo"),
            .textDelta(id: "a", delta: "!"),
            .textEnd(id: "a"),
            .finish,
        ])
        let vm = ChatViewModel(slug: "demo", agent: nil, repository: fake)
        vm.send(userText: "こんにちは")

        // Drain main-actor queued tasks by polling status.
        try await waitUntil { vm.status == .idle }

        XCTAssertEqual(fake.streamCalls, 1)
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "こんにちは")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].content, "Hello!")
        XCTAssertFalse(vm.messages[1].isStreaming)
    }

    // MARK: - Error paths

    func testUnauthorizedErrorSurfacesAsUnauthorizedStatus() async throws {
        let fake = FakeChatStreaming()
        fake.script = .failure(ChatStreamError.notAuthorized)
        let vm = ChatViewModel(slug: "demo", agent: nil, repository: fake)
        vm.send(userText: "hi")

        try await waitUntil { vm.status == .unauthorized }
        // Empty placeholder is removed; the user message remains.
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.role, .user)
    }

    func testHttpErrorSurfacesAsFailedStatus() async throws {
        let fake = FakeChatStreaming()
        fake.script = .failure(ChatStreamError.http(status: 500, body: "boom"))
        let vm = ChatViewModel(slug: "demo", agent: nil, repository: fake)
        vm.send(userText: "hi")

        try await waitUntil {
            if case .failed = vm.status { return true }
            return false
        }
    }

    // MARK: - Cancel

    func testCancelStopsStreamingAndClearsPlaceholder() async throws {
        // A stream that never finishes — we'll cancel it mid-flight.
        final class NeverStream: ChatStreaming, @unchecked Sendable {
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
                    continuation.yield(.textDelta(id: "a", delta: "partial"))
                    // Never call continuation.finish().
                }
            }
        }
        let vm = ChatViewModel(slug: "demo", agent: nil, repository: NeverStream())
        vm.send(userText: "hi")

        try await waitUntil { vm.messages.last?.content.contains("partial") == true }
        XCTAssertEqual(vm.status, .sending)

        vm.cancel()
        XCTAssertEqual(vm.status, .idle)
        XCTAssertFalse(vm.messages.last?.isStreaming ?? true)
    }

    // MARK: - Helpers

    /// Spin for up to 2 seconds waiting for a predicate. Lets async work on
    /// the main actor drain without needing combine/expectations.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("predicate never became true within \(timeout)s")
    }
}
