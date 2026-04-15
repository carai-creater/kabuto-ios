import Foundation

/// High-level semantic events surfaced from the Vercel AI SDK's
/// `toUIMessageStreamResponse()` SSE. Phase 4 only surfaces the text-delta
/// path; tool calls / reasoning / data parts are dropped silently.
enum ChatStreamEvent: Sendable, Equatable {
    /// A new assistant text part started. Parameter is the part `id` from
    /// the SDK, used to group deltas.
    case textStart(id: String)
    /// A token chunk appended to the current assistant text.
    case textDelta(id: String, delta: String)
    /// The current text part ended.
    case textEnd(id: String)
    /// The turn finished (before `[DONE]`).
    case finish
    /// Server emitted an error event.
    case error(String)
}

/// Errors specific to the SSE transport. HTTP-level failures surface as
/// `APIError.status` instead so existing catch sites keep working.
enum ChatStreamError: Error, CustomStringConvertible, Equatable {
    case notAuthorized
    case insufficientBalance(requiredPt: Int?, balancePt: Int?)
    case http(status: Int, body: String)
    case transport(String)

    var description: String {
        switch self {
        case .notAuthorized: return "認証が必要です"
        case .insufficientBalance(let req, let bal):
            return "残高が不足しています (必要: \(req ?? 0)pt / 現在: \(bal ?? 0)pt)"
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .transport(let message): return message
        }
    }
}

/// Parses the SDK's SSE byte stream into `ChatStreamEvent`s. Designed to
/// be fed one line at a time from `URLSession.AsyncBytes.lines`.
struct SSEDecoder {
    /// Turn a single SSE `data:` payload string into at most one event.
    /// Returns nil for events we intentionally ignore (start, start-step,
    /// finish-step, reasoning, tool invocations, data parts, etc.).
    /// Returns `.finish` on `[DONE]` sentinel.
    static func decode(dataLine: String) -> ChatStreamEvent? {
        let trimmed = dataLine.trimmingCharacters(in: .whitespaces)
        if trimmed == "[DONE]" { return .finish }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let type = obj["type"] as? String else { return nil }

        switch type {
        case "text-start":
            let id = (obj["id"] as? String) ?? ""
            return .textStart(id: id)
        case "text-delta":
            let id = (obj["id"] as? String) ?? ""
            // SDK v6 uses `delta`; some paths include `text`. Support both.
            let delta = (obj["delta"] as? String) ?? (obj["text"] as? String) ?? ""
            if delta.isEmpty { return nil }
            return .textDelta(id: id, delta: delta)
        case "text-end":
            let id = (obj["id"] as? String) ?? ""
            return .textEnd(id: id)
        case "finish":
            return .finish
        case "error":
            let message = (obj["errorText"] as? String)
                ?? (obj["error"] as? String)
                ?? "stream error"
            return .error(message)
        default:
            return nil
        }
    }
}

/// Drives a streaming request to the kabuto `/api/v1/chat` endpoint and
/// yields `ChatStreamEvent`s until the server sends `[DONE]` or the task
/// is cancelled.
struct SSEClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// POSTs `body` to `url` with the supplied bearer token, then returns
    /// an async stream of semantic events.
    func stream(
        url: URL,
        body: Data,
        bearerToken: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let bearerToken {
                        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = body

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatStreamError.transport("no HTTPURLResponse")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        // Drain whatever body fits to surface server-provided detail.
                        var raw = Data()
                        for try await byte in bytes {
                            raw.append(byte)
                            if raw.count > 4096 { break }
                        }
                        let text = String(data: raw, encoding: .utf8) ?? ""
                        switch http.statusCode {
                        case 401:
                            throw ChatStreamError.notAuthorized
                        case 402:
                            // Server shape: { error, code: "INSUFFICIENT_BALANCE", requiredPt, balancePt }
                            let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
                            throw ChatStreamError.insufficientBalance(
                                requiredPt: obj?["requiredPt"] as? Int,
                                balancePt: obj?["balancePt"] as? Int
                            )
                        default:
                            throw ChatStreamError.http(status: http.statusCode, body: text)
                        }
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst("data:".count))
                        if let event = SSEDecoder.decode(dataLine: payload) {
                            continuation.yield(event)
                            if case .finish = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
