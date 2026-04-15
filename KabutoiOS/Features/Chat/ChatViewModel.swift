import Foundation
import Observation

/// Drives a single agent chat. Owns the message log, streaming task, and
/// surfaced error state. Pure — no UI imports, so tests can exercise it
/// by feeding a stubbed `ChatRepository` and reading state transitions.
@Observable
@MainActor
final class ChatViewModel {
    enum Status: Equatable, Sendable {
        case idle
        case loadingHistory
        case sending
        case failed(String)
        /// Authorization failure — distinguishable so the view can
        /// trigger `AppEnvironment.requireAuth()`.
        case unauthorized
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var status: Status = .idle
    let agent: AgentDetail?
    let slug: String

    private let repository: any ChatStreaming
    private var activeTask: Task<Void, Never>?

    init(slug: String, agent: AgentDetail?, repository: any ChatStreaming) {
        self.slug = slug
        self.agent = agent
        self.repository = repository
    }

    // MARK: - History

    func loadHistory() async {
        guard let agent else { return }
        status = .loadingHistory
        do {
            let response = try await repository.history(agentId: agent.id, limit: 100)
            messages = response.messages.compactMap { m in
                guard let role = ChatMessage.Role(rawValue: m.role) else { return nil }
                return ChatMessage(id: m.id, role: role, content: m.content)
            }
            status = .idle
        } catch {
            // History load failure is non-fatal — start fresh.
            messages = []
            status = .idle
        }
    }

    // MARK: - Send

    func send(userText text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancel()

        let userMessage = ChatMessage(role: .user, content: trimmed)
        var assistant = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(userMessage)
        messages.append(assistant)
        status = .sending

        let idempotencyKey = UUID().uuidString
        let snapshot = messages.dropLast() // don't send the empty placeholder

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.repository.streamChat(
                    messages: Array(snapshot),
                    agentId: self.agent?.id,
                    modelId: nil,
                    idempotencyKey: idempotencyKey
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    self.apply(event, to: &assistant)
                }
                if !Task.isCancelled {
                    self.finalize(assistant: &assistant)
                }
            } catch {
                self.fail(with: error, placeholderId: assistant.id)
            }
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        if case .sending = status {
            // Mark any trailing streaming placeholder as complete so the
            // UI doesn't show a blinking cursor forever.
            if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                messages[idx].isStreaming = false
            }
            status = .idle
        }
    }

    // MARK: - Internals

    private func apply(_ event: ChatStreamEvent, to assistant: inout ChatMessage) {
        switch event {
        case .textStart:
            break
        case .textDelta(_, let delta):
            if let idx = messages.lastIndex(where: { $0.id == assistant.id }) {
                messages[idx].content.append(delta)
                assistant.content.append(delta)
            }
        case .textEnd:
            break
        case .finish:
            break
        case .error(let message):
            status = .failed(message)
        }
    }

    private func finalize(assistant: inout ChatMessage) {
        if let idx = messages.lastIndex(where: { $0.id == assistant.id }) {
            messages[idx].isStreaming = false
        }
        if case .failed = status { return }
        status = .idle
    }

    private func fail(with error: Error, placeholderId: String) {
        if let idx = messages.lastIndex(where: { $0.id == placeholderId }) {
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty {
                messages.remove(at: idx)
            }
        }
        if let chatError = error as? ChatStreamError {
            switch chatError {
            case .notAuthorized:
                status = .unauthorized
            default:
                status = .failed(chatError.description)
            }
        } else {
            status = .failed(String(describing: error))
        }
    }
}
