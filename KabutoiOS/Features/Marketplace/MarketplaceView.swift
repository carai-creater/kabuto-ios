import SwiftUI

/// `/agents` mirror. Search, sort, tag chips, tap → `AgentDetailView`.
struct MarketplaceView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var query: String = ""
    @State private var sort: AgentRepository.Sort = .usage
    @State private var tag: String = ""
    @State private var agents: [Agent] = []
    @State private var state: LoadState = .idle

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        contents
            .navigationTitle("エージェント")
            .searchable(text: $query, prompt: "エージェント名・説明を検索")
            .onChange(of: query) { _, _ in debounceReload() }
            .onChange(of: sort) { _, _ in Task { await load() } }
            .onChange(of: tag) { _, _ in Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("並び替え", selection: $sort) {
                            Text("人気順").tag(AgentRepository.Sort.usage)
                            Text("新着順").tag(AgentRepository.Sort.new)
                            Text("評価順").tag(AgentRepository.Sort.rating)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var contents: some View {
        switch state {
        case .idle:
            ProgressView().controlSize(.large)
        case .loading where agents.isEmpty:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView {
                Label("読み込みに失敗", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).font(.footnote)
            } actions: {
                Button("再試行") { Task { await load() } }
            }
        case .loaded where agents.isEmpty:
            ContentUnavailableView.search(text: query)
        default:
            list
        }
    }

    private var list: some View {
        List(agents) { agent in
            NavigationLink(value: agent) {
                AgentRow(agent: agent)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Agent.self) { agent in
            AgentDetailView(slug: agent.slug, initialSummary: agent)
        }
    }

    // MARK: - Loading

    @State private var reloadTask: Task<Void, Never>?
    private func debounceReload() {
        reloadTask?.cancel()
        reloadTask = Task { [query] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await self.load(queryOverride: query)
        }
    }

    private func load(queryOverride: String? = nil) async {
        state = .loading
        do {
            let items = try await env.agentRepository.list(
                query: queryOverride ?? query,
                tag: tag,
                sort: sort
            )
            agents = items
            state = .loaded
        } catch {
            state = .failed(String(describing: error))
        }
    }
}

private struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(agent.iconEmoji)
                .font(.system(size: 36))
                .frame(width: 56, height: 56)
                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.title).font(.headline).lineLimit(1)
                Text(agent.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label(String(format: "%.1f", agent.ratingAvg), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Label("\(agent.reviewCount)", systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(agent.pricePerUsePt)) pt")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { MarketplaceView() }
        .environment(AppEnvironment(config: .preview))
}
