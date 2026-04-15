import Foundation

/// Persists the currently active Supabase session envelope to the Keychain.
/// In Phase 2 this will become the source of truth that AuthService mirrors
/// from the Supabase Swift SDK. Phase 1 only needs the load/save contract.
struct PersistedSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
}

actor SessionStore {
    private let keychain: KeychainStorage
    private let key = "supabase.session"
    private var cached: PersistedSession?

    init(keychain: KeychainStorage) {
        self.keychain = keychain
    }

    func load() -> PersistedSession? {
        if let cached { return cached }
        do {
            guard let data = try keychain.get(key) else { return nil }
            let session = try JSONDecoder().decode(PersistedSession.self, from: data)
            cached = session
            return session
        } catch {
            return nil
        }
    }

    func save(_ session: PersistedSession) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.set(data, for: key)
        cached = session
    }

    func clear() throws {
        try keychain.delete(key)
        cached = nil
    }
}
