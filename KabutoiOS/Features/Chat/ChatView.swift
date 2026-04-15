import SwiftUI

/// The chat screen, reachable from `AgentDetailView`. Mirrors the
/// `/agents/[slug]` right-hand chat panel from kabuto web.
struct ChatView: View {
    let slug: String
    let agent: AgentDetail?

    @Environment(AppEnvironment.self) private var env
    @State private var vm: ChatViewModel?
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            composer
        }
        .navigationTitle(agent?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ensureViewModel() }
        .toolbar {
            if vm?.status == .sending {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("中断") { vm?.cancel() }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let agent, let vm, vm.messages.isEmpty {
                        startersView(agent: agent)
                    }
                    ForEach(vm?.messages ?? []) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if case .failed(let text) = vm?.status {
                        Label(text, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .onChange(of: vm?.messages.last?.content) { _, _ in
                if let last = vm?.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func startersView(agent: AgentDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("会話を始める").font(.caption).foregroundStyle(.secondary)
            ForEach(agent.conversationStarters) { starter in
                Button {
                    sendStarter(starter.text)
                } label: {
                    HStack {
                        Text(starter.text)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("メッセージを入力", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .padding(10)
                    .background(Color.accentColor, in: .circle)
                    .foregroundStyle(.white)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm?.status == .sending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func ensureViewModel() async {
        if vm == nil {
            vm = ChatViewModel(slug: slug, agent: agent, repository: env.chatRepository)
        }
        if case .signedIn = env.auth.state {
            await vm?.loadHistory()
        }
    }

    private func submit() {
        let text = input
        input = ""
        if env.requireAuth() {
            vm?.send(userText: text)
        }
        if vm?.status == .unauthorized {
            env.requireAuth()
        }
    }

    private func sendStarter(_ text: String) {
        if env.requireAuth() {
            vm?.send(userText: text)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                    .font(.body)
                    .padding(12)
                    .background(bubbleBackground, in: .rect(cornerRadius: 14))
                    .foregroundStyle(bubbleForeground)
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? Color.accentColor : Color.secondary.opacity(0.12)
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }
}

#Preview {
    NavigationStack { ChatView(slug: "demo", agent: nil) }
        .environment(AppEnvironment(config: .preview))
}
