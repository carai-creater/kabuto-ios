import XCTest
@testable import KabutoiOS

final class AppConfigTests: XCTestCase {
    func testLoadingFromBundleSucceedsWhenKeysArePresent() throws {
        let bundle = StubBundle(values: [
            "KabutoAPIBaseURL": "https://api.example.com",
            "KabutoSupabaseURL": "https://x.supabase.co",
            "KabutoSupabaseAnonKey": "anon-key",
        ])
        let config = try AppConfig.loadFromBundle(bundle)
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(config.supabaseAnonKey, "anon-key")
    }

    func testLoadingFailsWhenKeyMissing() {
        let bundle = StubBundle(values: [:])
        XCTAssertThrowsError(try AppConfig.loadFromBundle(bundle))
    }

    func testLoadingFailsOnInvalidURL() {
        let bundle = StubBundle(values: [
            "KabutoAPIBaseURL": "not a url",
            "KabutoSupabaseURL": "https://x.supabase.co",
            "KabutoSupabaseAnonKey": "anon-key",
        ])
        XCTAssertThrowsError(try AppConfig.loadFromBundle(bundle))
    }
}

private final class StubBundle: Bundle, @unchecked Sendable {
    private let values: [String: Any]
    init(values: [String: Any]) {
        self.values = values
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}
