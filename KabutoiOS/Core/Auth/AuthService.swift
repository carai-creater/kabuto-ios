import Foundation
import Observation

/// Phase 1 placeholder for the Supabase-backed auth service.
///
/// Intentionally does NOT import supabase-swift yet — we don't want to bind
/// the public surface to a third-party type before Phase 2. The class exposes
/// the shape that later phases will implement:
///
///   - currentAccessToken() — pulled by APIClient to set the bearer header
///   - restoreSessionIfAvailable() — called once at launch
///   - signIn / signOut — driven by the Auth screens
///
/// Phase 2 will:
///   1. Add the Supabase Swift SDK as a package dependency
///   2. Back this service with `SupabaseClient.auth`
///   3. Mirror session changes into SessionStore / Keychain
@Observable
@MainActor
final class AuthService {
    enum State: Sendable {
        case unknown
        case signedOut
        case signedIn(userId: String)
    }

    private(set) var state: State = .unknown

    private let config: AppConfig
    private let sessionStore: SessionStore

    init(config: AppConfig, sessionStore: SessionStore) {
        self.config = config
        self.sessionStore = sessionStore
    }

    func restoreSessionIfAvailable() async {
        if let session = await sessionStore.load(), session.expiresAt > .now {
            state = .signedIn(userId: session.userId)
        } else {
            state = .signedOut
        }
    }

    func currentAccessToken() async -> String? {
        await sessionStore.load()?.accessToken
    }

    func signIn(email _: String, password _: String) async throws {
        // Wired up in Phase 2 via supabase-swift.
        throw AuthError.notImplemented
    }

    func signOut() async {
        try? await sessionStore.clear()
        state = .signedOut
    }
}

enum AuthError: Error, CustomStringConvertible {
    case notImplemented
    var description: String {
        switch self {
        case .notImplemented: return "Auth will be wired up in Phase 2 (Supabase Swift SDK)."
        }
    }
}
