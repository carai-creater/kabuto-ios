import Foundation
import Observation
import Supabase

/// Owns the Supabase auth lifecycle and projects it onto a small, testable
/// state machine the SwiftUI layer can read from. Session changes are
/// mirrored into Keychain via `SessionStore` so the next cold launch can
/// restore without a network round-trip.
@Observable
@MainActor
final class AuthService {
    enum State: Sendable, Equatable {
        case unknown        // before restoreSessionIfAvailable() runs
        case signedOut
        case signedIn(userId: String, email: String?)
    }

    private(set) var state: State = .unknown
    private(set) var lastError: String?

    private let client: SupabaseClient
    private let sessionStore: SessionStore
    private var listenerTask: Task<Void, Never>?

    init(config: AppConfig, sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        self.client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseAnonKey
        )
    }

    // No explicit deinit — AuthService lives for the app lifetime. Cancelling
    // the listener from a non-isolated deinit would fight Swift 6 isolation
    // rules and offers no meaningful benefit at process exit.

    // MARK: - Lifecycle

    /// Called once at app launch. Tries Keychain first for an instant UI,
    /// then subscribes to auth state changes so we keep in sync with the SDK.
    func restoreSessionIfAvailable() async {
        if let persisted = await sessionStore.load(), persisted.expiresAt > .now {
            state = .signedIn(userId: persisted.userId, email: nil)
        } else {
            state = .signedOut
        }

        // Subscribe once. The SDK emits .initialSession, .signedIn, .signedOut,
        // .tokenRefreshed, etc. We translate those into our own State.
        if listenerTask == nil {
            let stream = client.auth.authStateChanges
            listenerTask = Task { [weak self] in
                for await (event, session) in stream {
                    await self?.handle(event: event, session: session)
                }
            }
        }

        // Kick the SDK into validating whatever it loaded from its own storage.
        _ = try? await client.auth.session
    }

    private func handle(event: AuthChangeEvent, session: Session?) async {
        Log.auth.debug("auth event \(String(describing: event), privacy: .public)")
        switch event {
        case .signedIn, .tokenRefreshed, .initialSession, .userUpdated:
            if let session {
                await persist(session)
                state = .signedIn(userId: session.user.id.uuidString, email: session.user.email)
            } else if case .initialSession = event {
                // No SDK session available at launch — keep whatever Keychain said.
                if case .unknown = state { state = .signedOut }
            }
        case .signedOut, .userDeleted:
            try? await sessionStore.clear()
            state = .signedOut
        case .passwordRecovery, .mfaChallengeVerified:
            break
        @unknown default:
            break
        }
    }

    private func persist(_ session: Session) async {
        let persisted = PersistedSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            userId: session.user.id.uuidString
        )
        do {
            try await sessionStore.save(persisted)
        } catch {
            Log.auth.error("failed to persist session: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Token provider (APIClient bearer)

    func currentAccessToken() async -> String? {
        // Prefer the SDK — it will auto-refresh if the token is about to expire.
        if let session = try? await client.auth.session {
            return session.accessToken
        }
        return await sessionStore.load()?.accessToken
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async throws {
        lastError = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            // state is driven by the listener, but set eagerly for snappy UI.
        } catch {
            lastError = humanize(error)
            throw error
        }
    }

    func signUp(email: String, password: String) async throws {
        lastError = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
        } catch {
            lastError = humanize(error)
            throw error
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            Log.auth.error("signOut failed: \(String(describing: error), privacy: .public)")
        }
        try? await sessionStore.clear()
        state = .signedOut
    }

    private func humanize(_ error: Error) -> String {
        // Supabase errors are detailed but noisy — show the localized description.
        error.localizedDescription
    }
}
