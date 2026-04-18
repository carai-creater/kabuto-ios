import XCTest
@testable import KabutoiOS

/// A11 hardening — verifies:
///  - successful first attempt returns the session id
///  - retryable failure (5xx / transport) retries up to the cap
///  - non-retryable failure (4xx) bails out immediately
///  - exhausted retries return .failed with the last error reason
final class ChatHistoryPersisterTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makePersister() -> ChatHistoryPersister {
        let api = APIClient(
            baseURL: URL(string: "https://kabuto.test")!,
            session: .stubbed(),
            tokenProvider: { "fake-token" }
        )
        return ChatHistoryPersister(repository: ChatHistoryRepository(api: api))
    }

    private func messages() -> [ChatMessage] {
        [
            ChatMessage(role: .user, content: "hi"),
            ChatMessage(role: .assistant, content: "hello"),
        ]
    }

    func testSuccessFirstAttempt() async {
        let callCount = UnsafeSendableBox<Int>(value: 0)
        MockURLProtocol.requestHandler = { [callCount] _ in
            callCount.value += 1
            return prepareMockResponse(body: Data(#"{"ok":true,"session_id":"sess_abc"}"#.utf8))
        }
        let outcome = await makePersister().saveWithRetry(
            agentIdOrSlug: "agent_x",
            sessionId: nil,
            messages: messages()
        )
        if case .success(let sid) = outcome {
            XCTAssertEqual(sid, "sess_abc")
        } else {
            XCTFail("expected .success")
        }
        XCTAssertEqual(callCount.value, 1)
    }

    func testRetriesOn500ThenSucceeds() async {
        let callCount = UnsafeSendableBox<Int>(value: 0)
        MockURLProtocol.requestHandler = { [callCount] _ in
            callCount.value += 1
            if callCount.value < 3 {
                return prepareMockResponse(body: Data(#"{"ok":false}"#.utf8), status: 500)
            }
            return prepareMockResponse(body: Data(#"{"ok":true,"session_id":"sess_ok"}"#.utf8))
        }
        let outcome = await makePersister().saveWithRetry(
            agentIdOrSlug: "agent_x",
            sessionId: nil,
            messages: messages()
        )
        if case .success(let sid) = outcome {
            XCTAssertEqual(sid, "sess_ok")
        } else {
            XCTFail("expected .success after retries")
        }
        XCTAssertEqual(callCount.value, 3, "should have retried twice before succeeding")
    }

    func testBailsOut400() async {
        let callCount = UnsafeSendableBox<Int>(value: 0)
        MockURLProtocol.requestHandler = { [callCount] _ in
            callCount.value += 1
            return prepareMockResponse(
                body: Data(#"{"ok":false,"error":"invalid_body"}"#.utf8),
                status: 400
            )
        }
        let outcome = await makePersister().saveWithRetry(
            agentIdOrSlug: "agent_x",
            sessionId: nil,
            messages: messages(),
            maxAttempts: 3
        )
        if case .failed = outcome {
            // ok
        } else {
            XCTFail("expected .failed for 400")
        }
        XCTAssertEqual(callCount.value, 1, "400 must not be retried")
    }

    func testExhaustsRetries() async {
        let callCount = UnsafeSendableBox<Int>(value: 0)
        MockURLProtocol.requestHandler = { [callCount] _ in
            callCount.value += 1
            return prepareMockResponse(body: Data(#"{"ok":false}"#.utf8), status: 503)
        }
        let outcome = await makePersister().saveWithRetry(
            agentIdOrSlug: "agent_x",
            sessionId: nil,
            messages: messages(),
            maxAttempts: 2
        )
        if case .failed = outcome {
            // ok
        } else {
            XCTFail("expected .failed after exhausting retries")
        }
        XCTAssertEqual(callCount.value, 2)
    }

    /// Restore path: after a save populates session_id, the next call
    /// should reuse that id (verified via request body inspection).
    func testSessionIdPassedThroughOnRetry() async {
        let capturedBodies = UnsafeSendableBox<[Data]>(value: [])
        MockURLProtocol.requestHandler = { [capturedBodies] req in
            if let stream = req.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buf = [UInt8](repeating: 0, count: 8192)
                var data = Data()
                while stream.hasBytesAvailable {
                    let n = stream.read(&buf, maxLength: buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                }
                capturedBodies.value.append(data)
            } else if let body = req.httpBody {
                capturedBodies.value.append(body)
            }
            return prepareMockResponse(body: Data(#"{"ok":true,"session_id":"sess_1"}"#.utf8))
        }

        let persister = makePersister()
        _ = await persister.saveWithRetry(
            agentIdOrSlug: "agent_x",
            sessionId: "sess_1",
            messages: messages()
        )

        XCTAssertEqual(capturedBodies.value.count, 1)
        let json = try? JSONSerialization.jsonObject(with: capturedBodies.value[0]) as? [String: Any]
        XCTAssertEqual(json?["session_id"] as? String, "sess_1")
        XCTAssertEqual(json?["agent_id_or_slug"] as? String, "agent_x")
    }
}
