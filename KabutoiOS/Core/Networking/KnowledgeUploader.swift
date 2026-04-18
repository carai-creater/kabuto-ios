import Foundation

/// Phase 7 (A8) — three-step knowledge upload via pre-signed URL.
///
///   1. `requestUploadURL(...)`   — server issues a short-lived signed URL
///   2. `uploadBytes(...)`        — iOS PUTs the file bytes directly to Supabase
///   3. `register(...)`           — server creates the KnowledgeDocument row
///
/// Each network hop has bounded retries (2 attempts by default). Errors
/// are surfaced as typed `UploadError` so the UI can tell size/mime
/// rejection apart from transient network failures.
struct KnowledgeUploader: Sendable {
    let api: APIClient
    let urlSession: URLSession

    init(api: APIClient, urlSession: URLSession = .shared) {
        self.api = api
        self.urlSession = urlSession
    }

    enum UploadError: Error, CustomStringConvertible, Equatable {
        case unsupportedMime
        case tooLarge(maxBytes: Int)
        case fileLimitReached(maxFiles: Int)
        case storageNotConfigured
        case signedURLFailed
        case uploadFailed(status: Int)
        case registerFailed(String)
        case transport(String)

        var description: String {
            switch self {
            case .unsupportedMime:
                return "この形式のファイルはアップロードできません (PDF / テキスト / Markdown / CSV / JSON のみ対応)"
            case .tooLarge(let max):
                return "ファイルが大きすぎます (最大 \(max / 1024 / 1024)MB)"
            case .fileLimitReached(let max):
                return "ナレッジファイルは最大 \(max) 件までです"
            case .storageNotConfigured:
                return "サーバのストレージ設定が未完了です。管理者に連絡してください"
            case .signedURLFailed:
                return "アップロード URL の発行に失敗しました"
            case .uploadFailed(let status):
                return "アップロードに失敗しました (HTTP \(status))"
            case .registerFailed(let reason):
                return "登録に失敗しました: \(reason)"
            case .transport(let msg):
                return "通信エラー: \(msg)"
            }
        }
    }

    struct UploadInput: Sendable {
        let slug: String
        let filename: String
        let mimeType: String
        let data: Data
    }

    /// End-to-end upload. Returns the registered document.
    func upload(_ input: UploadInput) async throws -> KnowledgeRegisterResponse.DocumentRow {
        let presigned = try await requestUploadURL(
            slug: input.slug,
            filename: input.filename,
            mimeType: input.mimeType,
            size: input.data.count
        )
        try await uploadBytes(
            to: presigned.signedUrl,
            data: input.data,
            mimeType: input.mimeType
        )
        let registered = try await register(
            slug: input.slug,
            storageKey: presigned.storageKey,
            title: input.filename,
            mimeType: input.mimeType
        )
        return registered.document
    }

    // MARK: - Step 1

    func requestUploadURL(
        slug: String,
        filename: String,
        mimeType: String,
        size: Int
    ) async throws -> KnowledgeUploadURLResponse {
        let body = KnowledgeUploadURLBody(
            filename: filename,
            mimeType: mimeType,
            sizeBytes: size
        )
        let endpoint = APIEndpoint<KnowledgeUploadURLResponse>(
            path: "api/v1/creator/agents/\(slug)/knowledge/upload-url",
            method: .post,
            body: body,
            requiresAuth: true
        )
        do {
            return try await api.send(endpoint)
        } catch let apiError as APIError {
            if case .status(_, let body) = apiError {
                let text = String(data: body, encoding: .utf8) ?? ""
                if text.contains("unsupported_mime") { throw UploadError.unsupportedMime }
                if text.contains("size_out_of_range") { throw UploadError.tooLarge(maxBytes: 8 * 1024 * 1024) }
                if text.contains("file_limit_reached") { throw UploadError.fileLimitReached(maxFiles: 8) }
                if text.contains("storage_not_configured") { throw UploadError.storageNotConfigured }
            }
            throw UploadError.signedURLFailed
        } catch {
            throw UploadError.transport(String(describing: error))
        }
    }

    // MARK: - Step 2

    /// Uploads directly to the Supabase-issued signed URL. 2 retries on
    /// transient failures.
    func uploadBytes(to url: URL, data: Data, mimeType: String) async throws {
        var lastStatus = 0
        for attempt in 1...2 {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            do {
                let (_, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw UploadError.transport("no HTTPURLResponse")
                }
                if (200..<300).contains(http.statusCode) {
                    return
                }
                lastStatus = http.statusCode
                // 5xx retry; 4xx bail.
                if http.statusCode < 500 || attempt == 2 {
                    throw UploadError.uploadFailed(status: http.statusCode)
                }
            } catch let uploadErr as UploadError {
                throw uploadErr
            } catch {
                if attempt == 2 {
                    throw UploadError.transport(String(describing: error))
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(500_000_000) * UInt64(attempt))
        }
        throw UploadError.uploadFailed(status: lastStatus)
    }

    // MARK: - Step 3

    func register(
        slug: String,
        storageKey: String,
        title: String,
        mimeType: String
    ) async throws -> KnowledgeRegisterResponse {
        let body = KnowledgeRegisterBody(
            storageKey: storageKey,
            title: title,
            mimeType: mimeType
        )
        let endpoint = APIEndpoint<KnowledgeRegisterResponse>(
            path: "api/v1/creator/agents/\(slug)/knowledge/register",
            method: .post,
            body: body,
            requiresAuth: true
        )
        do {
            return try await api.send(endpoint)
        } catch {
            throw UploadError.registerFailed(String(describing: error))
        }
    }

    // MARK: - Delete

    func delete(slug: String, documentId: String) async throws {
        let endpoint = APIEndpoint<OkResponse>(
            path: "api/v1/creator/agents/\(slug)/knowledge/\(documentId)",
            method: .delete,
            requiresAuth: true
        )
        _ = try await api.send(endpoint)
    }
}
