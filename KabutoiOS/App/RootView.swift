import SwiftUI

/// Top-level navigation. Gated on auth state:
///   - `.unknown`  → splash (while we try to restore from Keychain)
///   - `.signedOut` → AuthView (login / signup)
///   - `.signedIn`  → the real TabView
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch env.auth.state {
        case .unknown:
            ProgressView("読み込み中...")
                .controlSize(.large)
        case .signedOut:
            AuthView()
        case .signedIn:
            MainTabs()
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
