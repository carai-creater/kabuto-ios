import SwiftUI

/// 1-5 star rating + optional comment, POSTs to
/// `/api/v1/agents/:slug/reviews`. Caller is responsible for refreshing.
struct ReviewSheet: View {
    let slug: String
    let onSubmitted: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int = 5
    @State private var comment: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("評価") {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                rating = i
                            } label: {
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .foregroundStyle(.orange)
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("コメント (任意)") {
                    TextEditor(text: $comment)
                        .frame(minHeight: 120)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("レビューを書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") { submit() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await env.agentRepository.submitReview(
                    slug: slug,
                    rating: rating,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onSubmitted()
                dismiss()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }
}
