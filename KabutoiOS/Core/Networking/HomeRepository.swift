import Foundation

struct HomeRepository: Sendable {
    let api: APIClient

    func fetch() async throws -> HomePayload {
        let endpoint = APIEndpoint<HomePayload>(
            path: "api/v1/home",
            method: .get,
            requiresAuth: false
        )
        return try await api.send(endpoint)
    }
}
