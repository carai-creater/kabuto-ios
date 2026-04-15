import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section("セッション") {
                Text(describe(env.auth.state))
            }
            Section {
                Button("サインアウト", role: .destructive) {
                    Task { await env.auth.signOut() }
                }
                .disabled(!isSignedIn(env.auth.state))
            }
            Section("ビルド情報") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
            }
        }
        .navigationTitle("プロフィール")
    }

    private func describe(_ state: AuthService.State) -> String {
        switch state {
        case .unknown: return "確認中..."
        case .signedOut: return "サインインしていません"
        case .signedIn(let userId, _): return "サインイン中: \(userId)"
        }
    }

    private func isSignedIn(_ state: AuthService.State) -> Bool {
        if case .signedIn = state { return true }
        return false
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(AppEnvironment(config: .preview))
}
