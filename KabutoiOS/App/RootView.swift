import SwiftUI

/// Top-level navigation. Phase 3 change: anonymous browsing is allowed.
///   - `.unknown`  → splash while Keychain restore runs
///   - otherwise    → `MainTabs` (signed-in or anonymous)
/// Views that need auth call `env.requireAuth()`; the gate appears as a
/// modal sheet from here.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env
        Group {
            switch env.auth.state {
            case .unknown:
                ProgressView("読み込み中...")
                    .controlSize(.large)
            case .signedOut, .signedIn:
                MainTabs()
            }
        }
        .sheet(isPresented: $env.isPresentingAuthGate) {
            AuthView()
                .onChange(of: env.auth.state) { _, newValue in
                    if case .signedIn = newValue {
                        env.isPresentingAuthGate = false
                    }
                }
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("ホーム", systemImage: "house") }

            NavigationStack { MarketplaceView() }
                .tabItem { Label("エージェント", systemImage: "sparkles") }

            NavigationStack { WalletView() }
                .tabItem { Label("ウォレット", systemImage: "creditcard") }

            NavigationStack { ProfileView() }
                .tabItem { Label("プロフィール", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment(config: .preview))
}
