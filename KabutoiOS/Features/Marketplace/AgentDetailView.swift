import SwiftUI

/// Mirror of `/agents/[slug]` (minus the chat panel — that lands in Phase 4).
struct AgentDetailView: View {
    let slug: String
    let initialSummary: Agent?

    @Environment(AppEnvironment.self) private var env

    @State private var detail: AgentDetail?
    @State private var reviews: [Review] = []
    @State private var isFavorited: Bool = false
    @State private var viewerIsCreator: Bool = false
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var isPresentingReviewSheet: Bool = false

    var body: some View {
        List {
            hero
            description
            starters
            reviewsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail?.title ?? initialSummary?.title ?? "エージェント")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { favoriteButton }
        .task { await load() }
        .refreshable { await load() }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .sheet(isPresented: $isPresentingReviewSheet) {
            if let detail {
                ReviewSheet(slug: detail.slug, onSubmitted: {
                    Task { await load() }
                })
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var hero: some View {
        if let a = detail?.summary ?? initialSummary {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(a.iconEmoji).font(.system(size: 48))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.title3.bold())
                            if let name = detail?.creator.name ?? detail?.creator.email {
                                Text("by \(name)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    HStack(spacing: 16) {
                        Label(String(format: "%.1f", a.ratingAvg), systemImage: "star.fill")
                            .foregroundStyle(.orange)
                        Label("\(a.reviewCount) レビュー", systemImage: "text.bubble")
                            .foregroundStyle(.secondary)
                        Label("\(Int(a.pricePerUsePt)) pt/回", systemImage: "yensign.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    if !a.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(a.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1), in: .capsule)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var description: some View {
        if let detail {
            Section("説明") {
                Text(detail.description)
            }
        }
    }

    @ViewBuilder
    private var starters: some View {
        if let starters = detail?.conversationStarters, !starters.isEmpty {
            Section("会話を始める") {
                ForEach(starters) { s in
                    Text(s.text)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewsSection: some View {
        if let detail {
            Section("レビュー (\(detail.reviewCount))") {
                if reviews.isEmpty {
                    Text("まだレビューはありません").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(reviews) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(repeating: "★", count: r.rating) + String(repeating: "☆", count: 5 - r.rating))
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Spacer()
                            Text(r.user.name ?? "匿名").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let comment = r.comment, !comment.isEmpty {
                            Text(comment).font(.footnote)
                        }
                    }
                }
                if !viewerIsCreator {
                    Button {
                        if env.requireAuth() {
                            isPresentingReviewSheet = true
                        }
                    } label: {
                        Label("レビューを書く", systemImage: "square.and.pencil")
                    }
                }
            }
        }
    }

    private var favoriteButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorited ? .red : .primary)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await env.agentRepository.detail(slug: slug)
            detail = response.agent
            reviews = response.reviews
            isFavorited = response.isFavorited
            viewerIsCreator = response.viewerIsCreator
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private func toggleFavorite() async {
        guard env.requireAuth() else { return }
        let next = !isFavorited
        // Optimistic toggle.
        isFavorited = next
        do {
            let confirmed = try await env.agentRepository.setFavorite(slug: slug, favorited: next)
            isFavorited = confirmed
        } catch {
            isFavorited = !next
        }
    }
}

#Preview {
    NavigationStack {
        AgentDetailView(slug: "demo", initialSummary: nil)
    }
    .environment(AppEnvironment(config: .preview))
}
