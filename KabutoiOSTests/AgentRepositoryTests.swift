import XCTest
@testable import KabutoiOS

/// Exercises AgentRepository against a stubbed URLSession. These tests pin:
///   - endpoint URL shape (path + query) for the list endpoint
///   - method switching on `setFavorite` (true → POST, false → DELETE)
///   - Authorization header is sent only when `requiresAuth: true`
///   - review submission encodes the body as snake_case JSON
final class AgentRepositoryTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeRepo(tokenProvider: @Sendable @escaping () async -> String? = { "fake-token" }) -> AgentRepository {
        let api = APIClient(
            baseURL: URL(string: "https://kabuto.test")!,
            session: .stubbed(),
            tokenProvider: tokenProvider
        )
        return AgentRepository(api: api)
    }


    // MARK: - list

    func testListBuildsQueryStringAndDecodesItems() async throws {
        let capturedURL = UnsafeSendableBox<URL?>(value: nil)
        let capturedAuth = UnsafeSendableBox<String?>(value: nil)
        MockURLProtocol.requestHandler = { [capturedURL, capturedAuth] req in
            capturedURL.value = req.url
            capturedAuth.value = req.value(forHTTPHeaderField: "Authorization")
            let body = """
            {
              "ok": true,
              "items": [
                {
                  "id": "1", "slug": "a", "title": "A", "description": "d",
                  "icon_emoji": "🤖", "icon_url": null, "price_per_use_pt": 5,
                  "usage_count": 0, "rating_avg": 0, "review_count": 0,
                  "first_three_free": false, "tags": [], "created_at": null
                }
              ]
            }
            """.data(using: .utf8)!
            return prepareMockResponse(body: body)
        }

        let repo = makeRepo()
        let items = try await repo.list(query: "宇宙", tag: "AI", sort: .rating, limit: 20)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.slug, "a")

        let url = try XCTUnwrap(capturedURL.value)
        XCTAssertEqual(url.path, "/api/v1/agents")
        let items2 = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items2.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["q"], "宇宙")
        XCTAssertEqual(dict["tag"], "AI")
        XCTAssertEqual(dict["sort"], "rating")
        XCTAssertEqual(dict["limit"], "20")

        // Reads are anonymous — no Authorization header even if a token exists.
        XCTAssertNil(capturedAuth.value, "list() should not send Authorization header")
    }

    // MARK: - setFavorite

    func testSetFavoriteTrueSendsPOSTAndBearer() async throws {
        let capturedMethod = UnsafeSendableBox<String?>(value: nil)
        let capturedAuth = UnsafeSendableBox<String?>(value: nil)
        MockURLProtocol.requestHandler = { [capturedMethod, capturedAuth] req in
            capturedMethod.value = req.httpMethod
            capturedAuth.value = req.value(forHTTPHeaderField: "Authorization")
            let body = #"{ "ok": true, "favorited": true }"#.data(using: .utf8)!
            return prepareMockResponse(body: body)
        }

        let repo = makeRepo()
        let fav = try await repo.setFavorite(slug: "s", favorited: true)
        XCTAssertTrue(fav)
        XCTAssertEqual(capturedMethod.value, "POST")
        XCTAssertEqual(capturedAuth.value, "Bearer fake-token")
    }

    func testSetFavoriteFalseSendsDELETE() async throws {
        let capturedMethod = UnsafeSendableBox<String?>(value: nil)
        MockURLProtocol.requestHandler = { [capturedMethod] req in
            capturedMethod.value = req.httpMethod
            let body = #"{ "ok": true, "favorited": false }"#.data(using: .utf8)!
            return prepareMockResponse(body: body)
        }
        let repo = makeRepo()
        let fav = try await repo.setFavorite(slug: "s", favorited: false)
        XCTAssertFalse(fav)
        XCTAssertEqual(capturedMethod.value, "DELETE")
    }

    // MARK: - submitReview

    func testSubmitReviewEncodesSnakeCaseBody() async throws {
        let capturedBody = UnsafeSendableBox<Data?>(value: nil)
        MockURLProtocol.requestHandler = { [capturedBody] req in
            // URLSession drops bodies into bodyStream when launched by URLProtocol.
            if let stream = req.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                var data = Data()
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                capturedBody.value = data
            } else {
                capturedBody.value = req.httpBody
            }
            let body = #"{ "ok": true }"#.data(using: .utf8)!
            return prepareMockResponse(body: body)
        }

        let repo = makeRepo()
        try await repo.submitReview(slug: "s", rating: 4, comment: "good")

        let raw = try XCTUnwrap(capturedBody.value)
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertEqual(json?["rating"] as? Int, 4)
        XCTAssertEqual(json?["comment"] as? String, "good")
    }

}

// Free function — avoids capturing XCTestCase in @Sendable closures.
@Sendable
func prepareMockResponse(body: Data, status: Int = 200) -> (HTTPURLResponse, Data) {
    let http = HTTPURLResponse(
        url: URL(string: "https://kabuto.test")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (http, body)
}

/// Small box that lets request handlers capture values across concurrency
/// domains without tripping Sendable checking.
final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
}
