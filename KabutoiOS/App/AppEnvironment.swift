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

    init(config: AppConfig) {
        self.config = config
        let session = SessionStore(keychain: KeychainStorage(service: "com.carai.kabutoios.session"))
        self.auth = AuthService(config: config, sessionStore: session)
        self.apiClient = APIClient(
            baseURL: config.apiBaseURL,
            tokenProvider: { [auth] in await auth.currentAccessToken() }
        )
        self.meRepository = MeRepository(api: self.apiClient)
    }
}
