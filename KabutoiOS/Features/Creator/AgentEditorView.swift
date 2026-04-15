import SwiftUI

/// Minimal Phase 6 editor — exposes only the fields a creator must set
/// to get an agent published. Capabilities / tools / knowledge upload /
/// tag editing land in Phase 7+. The server accepts the full
/// `CreateAgentBody`; unexposed fields keep their defaults.
struct AgentEditorView: View {
    enum Mode: Hashable {
        case create
        case edit(CreatorAgent)
    }

    let mode: Mode

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var form = CreateAgentBody.blank()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var startersText: String = ""

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("アイコン絵文字", text: $form.iconEmoji)
                    .font(.title)
                TextField("タイトル", text: $form.title)
                TextField("説明", text: $form.description, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("指示プロンプト (Instructions)") {
                TextEditor(text: $form.instructions)
                    .frame(minHeight: 180)
                    .font(.system(.body, design: .monospaced))
            }
            Section("会話スターター") {
                TextEditor(text: $startersText)
                    .frame(minHeight: 80)
                Text("1 行に 1 つまで。最大 4 件。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Section("料金") {
                HStack {
                    TextField("1 回あたりの pt",
                              value: $form.pricePerUsePt,
                              format: .number)
                        .keyboardType(.numberPad)
                    Text("pt").foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "保存中..." : "保存")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || !isValid)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { applyMode() }
    }

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

    private func applyMode() {
        guard case .edit(let agent) = mode else { return }
        // Phase 6 doesn't fetch the full detail (which has instructions
        // and toolConfig) — PATCH requires a full body, so pre-fill what
        // we have from the list summary and ask the creator to re-type
        // any long-form fields they want to change. Documented in
        // migration-gaps #A17.
        form = CreateAgentBody(
            title: agent.title,
            description: agent.description,
            instructions: form.instructions,
            iconEmoji: agent.iconEmoji,
            conversationStarters: [],
            pricePerUsePt: Int(agent.pricePerUsePt),
            defaultLlm: form.defaultLlm,
            useRecommendedModel: form.useRecommendedModel,
            capabilities: form.capabilities,
            actions: form.actions,
            mcp: form.mcp,
            mcpServices: form.mcpServices
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let allLines: [String] = startersText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let starters = Array(allLines.prefix(4))
        form = CreateAgentBody(
            title: form.title,
            description: form.description,
            instructions: form.instructions,
            iconEmoji: form.iconEmoji,
            conversationStarters: starters,
            pricePerUsePt: form.pricePerUsePt,
            defaultLlm: form.defaultLlm,
            useRecommendedModel: form.useRecommendedModel,
            capabilities: form.capabilities,
            actions: form.actions,
            mcp: form.mcp,
            mcpServices: form.mcpServices
        )
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
}
