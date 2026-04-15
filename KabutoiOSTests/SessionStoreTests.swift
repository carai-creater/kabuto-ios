import XCTest
@testable import KabutoiOS

final class SessionStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() async throws {
        let store = SessionStore(keychain: InMemoryKeychain())
        let session = PersistedSession(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            userId: "u-1"
        )
        try await store.save(session)

        let loaded = await store.load()
        XCTAssertEqual(loaded?.accessToken, "at")
        XCTAssertEqual(loaded?.refreshToken, "rt")
        XCTAssertEqual(loaded?.userId, "u-1")
    }

    func testLoadReturnsNilWhenEmpty() async {
        let store = SessionStore(keychain: InMemoryKeychain())
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    func testClearRemovesPersistedSession() async throws {
        let store = SessionStore(keychain: InMemoryKeychain())
        try await store.save(
            PersistedSession(
                accessToken: "at",
                refreshToken: "rt",
                expiresAt: .distantFuture,
                userId: "u-1"
            )
        )
        try await store.clear()
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }
}
