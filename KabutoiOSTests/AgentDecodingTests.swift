import XCTest
@testable import KabutoiOS

/// Fixture-based decoding tests for the `/api/v1/*` JSON contract.
/// These lock in the snake_case shape so a breaking change on the kabuto
/// side surfaces immediately in CI.
final class AgentDecodingTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testAgentSummaryDecodes() throws {
        let json = """
        {
          "id": "agt_abc",
          "slug": "friendly-helper",
          "title": "フレンドリー助手",
          "description": "困ったときに何でも聞ける",
          "icon_emoji": "🤖",
          "icon_url": null,
          "price_per_use_pt": 10.0,
          "usage_count": 123,
          "rating_avg": 4.5,
          "review_count": 7,
          "first_three_free": true,
          "tags": ["人気", "初心者向け"],
          "created_at": "2026-04-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let a = try decoder().decode(Agent.self, from: json)
        XCTAssertEqual(a.id, "agt_abc")
        XCTAssertEqual(a.slug, "friendly-helper")
        XCTAssertEqual(a.title, "フレンドリー助手")
        XCTAssertEqual(a.iconEmoji, "🤖")
        XCTAssertNil(a.iconUrl)
        XCTAssertEqual(a.pricePerUsePt, 10.0)
        XCTAssertEqual(a.usageCount, 123)
        XCTAssertEqual(a.ratingAvg, 4.5, accuracy: 1e-9)
        XCTAssertEqual(a.reviewCount, 7)
        XCTAssertTrue(a.firstThreeFree)
        XCTAssertEqual(a.tags, ["人気", "初心者向け"])
        XCTAssertNotNil(a.createdAt)
    }

    func testAgentDetailDecodesWithNestedFields() throws {
        let json = """
        {
          "id": "agt_abc",
          "slug": "s",
          "title": "t",
          "description": "d",
          "icon_emoji": "🧠",
          "icon_url": null,
          "price_per_use_pt": 5,
          "usage_count": 0,
          "rating_avg": 0,
          "review_count": 0,
          "first_three_free": false,
          "tags": [],
          "created_at": null,
          "system_prompt": "You are helpful.",
          "instructions": null,
          "default_llm": "gpt-4o",
          "creator": { "name": "Alice", "email": "a@example.com" },
          "conversation_starters": [
            { "position": 0, "text": "こんにちは" },
            { "position": 1, "text": "始め方を教えて" }
          ],
          "knowledge_documents": []
        }
        """.data(using: .utf8)!

        let d = try decoder().decode(AgentDetail.self, from: json)
        XCTAssertEqual(d.systemPrompt, "You are helpful.")
        XCTAssertEqual(d.defaultLlm, "gpt-4o")
        XCTAssertEqual(d.creator.name, "Alice")
        XCTAssertEqual(d.conversationStarters.count, 2)
        XCTAssertEqual(d.conversationStarters.first?.text, "こんにちは")
        XCTAssertNil(d.createdAt)
    }

    func testHomePayloadAnonymousDecodes() throws {
        let json = """
        {
          "ok": true,
          "is_authenticated": false,
          "recommended": [],
          "hot": [],
          "new_arrivals": []
        }
        """.data(using: .utf8)!
        let h = try decoder().decode(HomePayload.self, from: json)
        XCTAssertTrue(h.ok)
        XCTAssertFalse(h.isAuthenticated)
        XCTAssertNil(h.walletBalancePt)
        XCTAssertNil(h.recentSessions)
        XCTAssertNil(h.favorites)
    }

    func testHomePayloadAuthedDecodes() throws {
        let json = """
        {
          "ok": true,
          "is_authenticated": true,
          "recommended": [],
          "hot": [],
          "new_arrivals": [],
          "wallet_balance_pt": 1500,
          "recent_sessions": [
            {
              "slug": "s1",
              "title": "Session A",
              "icon_emoji": "💬",
              "icon_url": null,
              "last_at": "2026-04-10T09:00:00Z"
            }
          ],
          "favorites": [
            {
              "id": "agt_x",
              "slug": "fav",
              "title": "Favorite One",
              "icon_emoji": "⭐",
              "icon_url": null
            }
          ]
        }
        """.data(using: .utf8)!
        let h = try decoder().decode(HomePayload.self, from: json)
        XCTAssertTrue(h.isAuthenticated)
        XCTAssertEqual(h.walletBalancePt, 1500)
        XCTAssertEqual(h.recentSessions?.count, 1)
        XCTAssertEqual(h.recentSessions?.first?.slug, "s1")
        XCTAssertEqual(h.favorites?.count, 1)
    }
}
