import SwiftUI
import UniformTypeIdentifiers

/// Phase 7 (A7 + A8) — editor that preloads the real server-side
/// instructions / capabilities / starters / knowledge docs on edit,
/// and supports inline knowledge file upload (picker → pre-signed URL
/// → PUT → register).
struct AgentEditorView: View {
    enum Mode: Hashable {
        case create
        case edit(CreatorAgent)
    }

    let mode: Mode

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var form = CreateAgentBody.blank()
    @State private var startersText: String = ""
    @State private var isSaving: Bool = false
    @State private var isLoadingDetail: Bool = false
    @State private var errorMessage: String?

    // Knowledge state (only used in edit mode).
    @State private var documents: [CreatorAgentDetail.Document] = []
    @State private var isPresentingFilePicker: Bool = false
    @State private var knowledgeBusy: Bool = false
    @State private var knowledgeMessage: String?

    var body: some View {
        Form {
            if isLoadingDetail {
                Section {
                    HStack { ProgressView(); Text("詳細を読み込み中…").foregroundStyle(.secondary) }
                }
            }

            Section("基本情報") {
                TextField("アイコン絵文字", text: $form.iconEmoji).font(.title)
                TextField("タイトル", text: $form.title)
                TextField("説明", text: $form.description, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                TextEditor(text: $form.instructions)
                    .frame(minHeight: 180)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("指示プロンプト")
            } footer: {
                if case .edit = mode, form.instructions.isEmpty {
                    Text("保存すると現在の指示が空で上書きされます。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TextEditor(text: $startersText)
                    .frame(minHeight: 80)
            } header: {
                Text("会話スターター")
            } footer: {
                Text("1 行に 1 つまで。最大 4 件。")
            }
            Section("料金") {
                HStack {
                    TextField("1 回あたりの pt", value: $form.pricePerUsePt, format: .number)
                        .keyboardType(.numberPad)
                    Text("pt").foregroundStyle(.secondary)
                }
            }

            if case .edit = mode {
                knowledgeSection
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "保存中..." : "保存").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || !isValid)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await applyMode() }
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText, .commaSeparatedText, .json],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFilePickerResult(result) }
        }
    }

    // MARK: - Knowledge section

    @ViewBuilder
    private var knowledgeSection: some View {
        Section {
            if documents.isEmpty && !knowledgeBusy {
                Text("ナレッジファイルは登録されていません").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(documents) { doc in
                HStack {
                    Image(systemName: icon(for: doc.mimeType)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title).font(.subheadline).lineLimit(1)
                        Text(doc.createdAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete(perform: deleteDocuments)
            Button {
                isPresentingFilePicker = true
            } label: {
                HStack {
                    if knowledgeBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle")
                    }
                    Text(knowledgeBusy ? "アップロード中…" : "ファイルを追加")
                }
            }
            .disabled(knowledgeBusy || documents.count >= 8)
            if let knowledgeMessage {
                Label(knowledgeMessage, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("ナレッジ")
        } footer: {
            Text("PDF / テキスト / Markdown / CSV / JSON。最大 8 件、1 ファイル 8MB まで。")
        }
    }

    private func icon(for mime: String) -> String {
        switch mime {
        case "application/pdf": return "doc.richtext"
        case "text/markdown": return "doc.text"
        case "application/json": return "curlybraces"
        case "text/csv": return "tablecells"
        default: return "doc"
        }
    }

    // MARK: - Derivations

    private var title: String {
        switch mode {
        case .create: return "新規作成"
        case .edit(let a): return a.title
        }
    }

    private var isValid: Bool {
        !form.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !form.description.trimmingCharacters(in: .whitespaces).isEmpty
            && !form.instructions.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Lifecycle

    private func applyMode() async {
        guard case .edit(let agent) = mode else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let detail = try await env.creatorRepository.fetchDetail(slug: agent.slug)
            form = detail.toCreateAgentBody()
            startersText = detail.conversationStarters
                .sorted(by: { $0.position < $1.position })
                .map(\.text)
                .joined(separator: "\n")
            documents = detail.knowledgeDocuments
        } catch {
            errorMessage = "詳細の取得に失敗しました: \(error)"
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let lines: [String] = startersText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        form.conversationStarters = Array(lines.prefix(4))
        do {
            switch mode {
            case .create:
                _ = try await env.creatorRepository.create(form)
            case .edit(let agent):
                try await env.creatorRepository.update(slug: agent.slug, body: form)
            }
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Knowledge

    private func handleFilePickerResult(_ result: Result<[URL], Error>) async {
        knowledgeMessage = nil
        guard case .edit(let agent) = mode else { return }
        switch result {
        case .failure(let err):
            knowledgeMessage = "ファイル選択に失敗: \(err.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            knowledgeBusy = true
            defer { knowledgeBusy = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let doc = try await env.knowledgeUploader.upload(
                    KnowledgeUploader.UploadInput(
                        slug: agent.slug,
                        filename: url.lastPathComponent,
                        mimeType: mimeType(for: url),
                        data: data
                    )
                )
                documents.append(.init(
                    id: doc.id,
                    title: doc.title,
                    mimeType: doc.mimeType,
                    storageKey: nil,
                    createdAt: doc.createdAt
                ))
                knowledgeMessage = "\(doc.title) をアップロードしました"
            } catch let err as KnowledgeUploader.UploadError {
                knowledgeMessage = err.description
            } catch {
                knowledgeMessage = String(describing: error)
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        if let uti = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return uti
        }
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "text/markdown"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private func deleteDocuments(at offsets: IndexSet) {
        guard case .edit(let agent) = mode else { return }
        let ids = offsets.map { documents[$0].id }
        Task {
            knowledgeBusy = true
            defer { knowledgeBusy = false }
            for id in ids {
                do {
                    try await env.knowledgeUploader.delete(slug: agent.slug, documentId: id)
                    documents.removeAll { $0.id == id }
                } catch {
                    knowledgeMessage = "削除に失敗: \(error)"
                }
            }
        }
    }
}
