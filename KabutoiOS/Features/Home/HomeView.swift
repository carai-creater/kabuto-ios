import SwiftUI

/// Mirror of the web `/dashboard` (signed-in) and `/` (anonymous)
/// home experience, collapsed into a single SwiftUI screen driven by
/// `GET /api/v1/home`.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var payload: HomePayload?
    @State private var error: String?
    @State private var isLoading: Bool = false

    var body: some View {
        List {
            if let payload {
                if payload.isAuthenticated, let balance = payload.walletBalancePt {
                    walletSection(balance: balance)
                }
                if let recent = payload.recentSessions, !recent.isEmpty {
                    recentSection(recent)
                }
                section("おすすめ", agents: payload.recommended)
                section("人気", agents: payload.hot)
                section("新着", agents: payload.newArrivals)
                if let favs = payload.favorites, !favs.isEmpty {
                    favoritesSection(favs)
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label("読み込みに失敗", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error).font(.footnote)
                } actions: {
                    Button("再試行") { Task { await load() } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Kabuto")
        .refreshable { await load() }
        .task { await load() }
        .navigationDestination(for: Agent.self) { agent in
            AgentDetailView(slug: agent.slug, initialSummary: agent)
        }
        .navigationDestination(for: String.self) { slug in
            AgentDetailView(slug: slug, initialSummary: nil)
        }
    }

    // MARK: - Sections

    private func walletSection(balance: Int) -> some View {
        Section {
            HStack {
                Image(systemName: "yensign.circle.fill").foregroundStyle(.green)
                Text("ウォレット残高")
                Spacer()
                Text("\(balance) pt").bold().monospacedDigit()
            }
        }
    }

    private func recentSection(_ lines: [RecentSessionLine]) -> some View {
        Section("最近の会話") {
            ForEach(lines) { line in
                NavigationLink(value: line.slug) {
                    HStack(spacing: 10) {
                        Text(line.iconEmoji).font(.title3)
                        Text(line.title).lineLimit(1)
                    }
                }
            }
        }
    }

    private func section(_ title: String, agents: [Agent]) -> some View {
        Group {
            if agents.isEmpty {
                EmptyView()
            } else {
                Section(title) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(agents) { agent in
                                NavigationLink(value: agent) {
                                    AgentCard(agent: agent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func favoritesSection(_ favs: [FavoriteCard]) -> some View {
        Section("お気に入り") {
            ForEach(favs) { f in
                NavigationLink(value: f.slug) {
                    HStack(spacing: 10) {
                        Text(f.iconEmoji).font(.title3)
                        Text(f.title).lineLimit(1)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            payload = try await env.homeRepository.fetch()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct AgentCard: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(agent.iconEmoji).font(.system(size: 32))
            Text(agent.title).font(.subheadline.bold()).lineLimit(1)
            Text(agent.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(.orange)
                Text(String(format: "%.1f", agent.ratingAvg))
                Text("·")
                Text("\(Int(agent.pricePerUsePt))pt")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 180, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment(config: .preview))
}
