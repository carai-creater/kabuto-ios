import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section("Phase 1 – 基盤のみ") {
                LabeledContent("API Base URL", value: env.config.apiBaseURL.absoluteString)
                LabeledContent("Supabase URL", value: env.config.supabaseURL.absoluteString)
                LabeledContent("Auth state", value: describe(env.auth.state))
            }
            Section("次フェーズで実装") {
                Text("マーケットプレイス表示、おすすめエージェント、最近の会話、ウォレット残高カード")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kabuto")
    }

    private func describe(_ state: AuthService.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .signedOut: return "signed out"
        case .signedIn(let id): return "signed in (\(id))"
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment(config: .preview))
}
