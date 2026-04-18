import XCTest
@testable import KabutoiOS

@MainActor
final class ChatRestoreTests: XCTestCase {

    /// Canned history source — simulates a prior session persisted by an
    /// earlier app launch. loadHistory() must rehydrate both messages
    /// and the sessionId.
    final class StubStream: ChatStreaming, @unchecked Sendable {
        var canned: ChatHistoryResponse = .init(ok: true, sessionId: nil, messages: [])
        func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse {
            canned
        }
        func streamChat(
            messages: [ChatMessage], agentId: String?, modelId: String?, idempotencyKey: String
        ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { c in c.finish() }
        }
    }

    /// Fabricates an `AgentDetail` with the minimum fields ChatViewModel needs.
    private func makeAgent(id: String = "agent_x") -> AgentDetail {
        AgentDetail(
            id: id,
            slug: "slug",
            title: "t",
            description: "d",
            iconEmoji: "🤖",
            iconUrl: nil,
            pricePerUsePt: 0,
            usageCount: 0,
            ratingAvg: 0,
            reviewCount: 0,
            firstThreeFree: false,
            tags: [],
            createdAt: nil,
            systemPrompt: "",
            instructions: nil,
            defaultLlm: nil,
            creator: AgentCreator(name: nil, email: "c@example.com"),
            conversationStarters: [],
            knowledgeDocuments: []
        )
    }

    func testLoadHistoryRehydratesMessagesAndSessionId() async {
        let stub = StubStream()
        stub.canned = ChatHistoryResponse(
            ok: true,
            sessionId: "sess_restored",
            messages: [
                .init(id: "m1", role: "user", content: "前回のメッセージ"),
                .init(id: "m2", role: "assistant", content: "前回の返答"),
            ]
        )
        let vm = ChatViewModel(slug: "slug", agent: makeAgent(), repository: stub)

        await vm.loadHistory()

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].content, "前回のメッセージ")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.currentSessionId, "sess_restored")
        XCTAssertEqual(vm.status, .idle)
    }

    func testUpdateCurrentSessionIdIsPersistedForNextSave() async {
        let vm = ChatViewModel(slug: "slug", agent: makeAgent(), repository: StubStream())
        XCTAssertNil(vm.currentSessionId)
        vm.updateCurrentSessionId("sess_abc")
        XCTAssertEqual(vm.currentSessionId, "sess_abc")
        // Subsequent nil updates should NOT clear it (server didn't tell us
        // otherwise; we keep what we had).
        vm.updateCurrentSessionId(nil)
        XCTAssertEqual(vm.currentSessionId, "sess_abc")
    }

    func testLoadHistoryFailureLeavesCleanEmptyState() async {
        final class FailStream: ChatStreaming, @unchecked Sendable {
            struct Boom: Error {}
            func history(agentId: String, limit: Int) async throws -> ChatHistoryResponse {
                throw Boom()
            }
            func streamChat(
                messages: [ChatMessage], agentId: String?, modelId: String?, idempotencyKey: String
            ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
                AsyncThrowingStream { c in c.finish() }
            }
        }
        let vm = ChatViewModel(slug: "slug", agent: makeAgent(), repository: FailStream())
        await vm.loadHistory()
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.currentSessionId)
        XCTAssertEqual(vm.status, .idle, "failure is non-fatal and status should reset to idle")
    }
}
