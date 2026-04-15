import SwiftUI

/// Top-level navigation. Mirrors the kabuto web shell layout at a high level:
/// home / marketplace / wallet / profile. Individual features are skeletons in
/// Phase 1 — real data fetching lands in later phases.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

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
