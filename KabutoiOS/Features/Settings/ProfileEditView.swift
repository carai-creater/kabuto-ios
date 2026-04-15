import SwiftUI

/// Edit the subset of profile fields exposed by
/// `PATCH /api/v1/me/profile`: name, bio, websiteUrl, xUrl.
struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var websiteUrl: String = ""
    @State private var xUrl: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("表示名") {
                TextField("例: 山田 太郎", text: $name)
            }
            Section("自己紹介") {
                TextEditor(text: $bio).frame(minHeight: 100)
            }
            Section("リンク") {
                TextField("Website URL", text: $websiteUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("X (Twitter) URL", text: $xUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "保存中..." : "保存")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("プロフィール編集")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrent() }
    }

    private func loadCurrent() async {
        guard let me = try? await env.meRepository.fetch() else { return }
        name = me.name ?? ""
        bio = me.bio ?? ""
        websiteUrl = me.websiteUrl?.absoluteString ?? ""
        xUrl = me.xUrl?.absoluteString ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let body = ProfilePatchBody(
            name: name,
            avatarUrl: nil,
            websiteUrl: websiteUrl,
            xUrl: xUrl,
            bio: bio
        )
        do {
            try await env.profileRepository.patch(body)
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
