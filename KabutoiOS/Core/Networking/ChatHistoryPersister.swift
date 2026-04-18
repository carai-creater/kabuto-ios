import Foundation
import os

/// Retry + logging wrapper around `ChatHistoryRepository.save`.
/// Phase 6.1: A11 hardening — the old fire-and-forget
/// `try? await historyRepo.save(...)` gave no retries and silently
/// swallowed failures, which meant a single flaky network call would
/// lose a user's turn permanently.
///
/// Policy:
///   - Up to 3 attempts
///   - Exponential backoff: 500ms, 1500ms (jittered ±20%)
///   - Each attempt logged with attempt number + outcome via OSLog so
///     field failures show up in Console.app + crash reports
///   - Non-retryable failures (400-class) stop immediately
///   - Success on any attempt returns the persisted session id
struct ChatHistoryPersister: Sendable {
    let repository: ChatHistoryRepository

    enum Outcome: Sendable {
        case success(sessionId: String?)
        case failed(reason: String)
    }

    /// Best-effort save with retries. Never throws; caller can ignore
    /// return value (view model already does).
    @discardableResult
    func saveWithRetry(
        agentIdOrSlug: String,
        sessionId: String?,
        messages: [ChatMessage],
        maxAttempts: Int = 3
    ) async -> Outcome {
        let messageCount = messages.count
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let persistedSessionId = try await repository.save(
                    agentIdOrSlug: agentIdOrSlug,
                    sessionId: sessionId,
                    messages: messages
                )
                Log.net.info(
                    "chat-history save ok agent=\(agentIdOrSlug, privacy: .public) attempt=\(attempt) messages=\(messageCount) session=\(persistedSessionId ?? "-", privacy: .public)"
                )
                return .success(sessionId: persistedSessionId)
            } catch {
                lastError = error
                let retryable = isRetryable(error)
                Log.net.warning(
                    "chat-history save failed agent=\(agentIdOrSlug, privacy: .public) attempt=\(attempt)/\(maxAttempts) retryable=\(retryable) err=\(String(describing: error), privacy: .public)"
                )
                if !retryable { break }
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: backoffNanos(attempt: attempt))
                }
            }
        }

        let reason = lastError.map { String(describing: $0) } ?? "unknown"
        Log.net.error(
            "chat-history save exhausted agent=\(agentIdOrSlug, privacy: .public) reason=\(reason, privacy: .public)"
        )
        return .failed(reason: reason)
    }

    /// 400-class HTTP errors (invalid body, not found, etc.) won't fix
    /// themselves by retrying. Transport errors and 5xx are retryable.
    private func isRetryable(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .status(let code, _):
                return code >= 500
            case .transport, .invalidResponse:
                return true
            case .decoding, .invalidURL:
                return false
            }
        }
        return true
    }

    /// 500ms, 1500ms with ±20% jitter.
    private func backoffNanos(attempt: Int) -> UInt64 {
        let base: Double = attempt == 1 ? 0.5 : 1.5
        let jitter = Double.random(in: 0.8...1.2)
        return UInt64(base * jitter * 1_000_000_000)
    }
}
