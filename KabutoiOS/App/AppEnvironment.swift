import Foundation
import Observation

/// Root dependency container. Features access services through this object
/// rather than constructing singletons, so tests can inject fakes.
@Observable
@MainActor
final class AppEnvironment {
    let config: AppConfig
    let apiClient: APIClient
    let auth: AuthService
    let meRepository: MeRepository
    let agentRepository: AgentRepository
    let homeRepository: HomeRepository
    let chatRepository: ChatRepository
    let walletRepository: WalletRepository
    let storeKit: any StoreKitServicing

    /// Set by features when the user attempts a write while anonymous.
    /// `RootView` observes this and presents the login sheet.
    var isPresentingAuthGate: Bool = false

    init(config: AppConfig) {
        self.config = config
        let session = SessionStore(keychain: KeychainStorage(service: "com.carai.kabutoios.session"))
        self.auth = AuthService(config: config, sessionStore: session)
        self.apiClient = APIClient(
            baseURL: config.apiBaseURL,
            tokenProvider: { [auth] in await auth.currentAccessToken() }
        )
        self.meRepository = MeRepository(api: self.apiClient)
        self.agentRepository = AgentRepository(api: self.apiClient)
        self.homeRepository = HomeRepository(api: self.apiClient)
        self.chatRepository = ChatRepository(
            baseURL: config.apiBaseURL,
            sseClient: SSEClient(),
            tokenProvider: { [auth] in await auth.currentAccessToken() },
            api: self.apiClient
        )
        self.walletRepository = WalletRepository(api: self.apiClient)
        self.storeKit = LiveStoreKitService()
    }

    /// Call from anywhere to trigger the login sheet. Returns `true` if the
    /// user is already signed in (caller can proceed immediately).
    @discardableResult
    func requireAuth() -> Bool {
        if case .signedIn = auth.state { return true }
        isPresentingAuthGate = true
        return false
    }
}
