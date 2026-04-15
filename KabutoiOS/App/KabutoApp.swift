import SwiftUI

@main
struct KabutoApp: App {
    @State private var environment: AppEnvironment

    init() {
        // Build the DI container once at launch. Fails fast if required
        // configuration is missing so we catch misconfiguration in CI/dev.
        do {
            let config = try AppConfig.loadFromBundle()
            self._environment = State(initialValue: AppEnvironment(config: config))
        } catch {
            fatalError("Failed to load AppConfig: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    await environment.auth.restoreSessionIfAvailable()
                }
        }
    }
}
