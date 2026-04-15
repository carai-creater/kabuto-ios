import SwiftUI

/// Lists the signed-in user's own agents (draft + published). Tap to
/// edit, swipe to publish/unpublish. Reachable from ProfileView.
struct CreatorDashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var agents: [CreatorAgent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if agents.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("まだ作成したエージェントがありません", systemImage: "sparkles")
                } description: {
                    Text("右上の「新規作成」から最初のエージェントを作りましょう。")
                        .font(.footnote)
                }
            } else {
                ForEach(agents) { agent in
                    NavigationLink(value: agent) {
                        row(agent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await togglePublish(agent) }
                        } label: {
                            Label(
                                agent.isPublished ? "非公開" : "公開",
                                systemImage: agent.isPublished ? "eye.slash" : "eye"
                            )
                        }
                        .tint(agent.isPublished ? .orange : .green)
                    }
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("クリエイター")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AgentEditorView(mode: .create)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: CreatorAgent.self) { agent in
            AgentEditorView(mode: .edit(agent))
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ agent: CreatorAgent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(agent.iconEmoji).font(.largeTitle)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(agent.title).font(.headline).lineLimit(1)
                    if !agent.isPublished {
                        Text("DRAFT")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                }
                Text(agent.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(Int(agent.pricePerUsePt)) pt", systemImage: "yensign.circle")
                    Label("\(agent.usageCount)", systemImage: "play.circle")
                    Label(String(format: "%.1f", agent.ratingAvg), systemImage: "star")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            agents = try await env.creatorRepository.listMyAgents()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func togglePublish(_ agent: CreatorAgent) async {
        do {
            _ = try await env.creatorRepository.setPublish(slug: agent.slug, publish: !agent.isPublished)
            await load()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

#Preview {
    NavigationStack { CreatorDashboardView() }
        .environment(AppEnvironment(config: .preview))
}
