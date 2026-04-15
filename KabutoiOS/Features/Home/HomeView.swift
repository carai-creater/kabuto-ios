import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var me: Me?
    @State private var meError: String?
    @State private var isLoading: Bool = false

    var body: some View {
        List {
            Section("アカウント") {
                if let me {
                    LabeledContent("Name", value: me.name ?? me.email)
                    LabeledContent("Email", value: me.email)
                    LabeledContent("Role", value: me.role)
                    LabeledContent("Wallet", value: "\(me.walletBalancePt) pt")
                } else if isLoading {
                    ProgressView("取得中...")
                } else if let meError {
                    Label(meError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                } else {
                    Text("サインインしていません")
                        .foregroundStyle(.secondary)
                }
            }

            Section("次フェーズで実装") {
                Text("おすすめエージェント / 最近の会話 / ウォレット残高カード")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kabuto")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if case .signedOut = env.auth.state { return }
        isLoading = true
        defer { isLoading = false }
        do {
            me = try await env.meRepository.fetch()
            meError = nil
        } catch {
            meError = String(describing: error)
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment(config: .preview))
}
