import SwiftUI

/// Sign-in / sign-up entry point. Mirrors the `/login` & `/signup` routes
/// in kabuto web: one form, toggle between modes. No third-party OAuth
/// providers yet — Phase 2 targets email+password parity.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "ログイン"
        case signUp = "新規登録"
        var id: Self { self }
    }

    @Environment(AppEnvironment.self) private var env

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("モード", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("メールアドレス") {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("パスワード") {
                    SecureField("8文字以上", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                }

                if let localError {
                    Section {
                        Label(localError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            if isSubmitting { ProgressView() }
                            Text(mode.rawValue).bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!isFormValid || isSubmitting)
                }

                #if DEBUG
                Section("デバッグ") {
                    Button("デモ用の値を入れる") {
                        email = "demo@kabuto.local"
                        password = "demo-password"
                    }
                    .font(.footnote)
                }
                #endif
            }
            .navigationTitle("Kabuto")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var isFormValid: Bool {
        email.contains("@") && password.count >= 8
    }

    private func submit() {
        localError = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .signIn:
                    try await env.auth.signIn(email: email, password: password)
                case .signUp:
                    try await env.auth.signUp(email: email, password: password)
                }
            } catch {
                localError = env.auth.lastError ?? String(describing: error)
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AppEnvironment(config: .preview))
}
