import SwiftUI

/// CRUD UI for user MCP connections. Credentials live on the server
/// (encrypted at rest) — iOS never persists them locally.
struct McpConnectionsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var items: [McpConnection] = []
    @State private var errorMessage: String?
    @State private var isPresentingAdd = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("接続なし", systemImage: "link.badge.plus")
                } description: {
                    Text("外部サービスに接続するには右上の「追加」をタップしてください。")
                        .font(.footnote)
                }
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label.isEmpty ? item.serverKey : item.label)
                            .font(.headline)
                        Text(item.serverKey).font(.caption).foregroundStyle(.secondary)
                        Text(item.connectedAt, format: .dateTime.day().month().year())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("MCP 接続")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddMcpConnectionSheet { await reload() }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do {
            items = try await env.mcpRepository.list()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func delete(at offsets: IndexSet) {
        let keys = offsets.map { items[$0].serverKey }
        Task {
            for key in keys {
                try? await env.mcpRepository.delete(serverKey: key)
            }
            await reload()
        }
    }
}

private struct AddMcpConnectionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let onAdded: () async -> Void

    @State private var serverKey: String = ""
    @State private var label: String = ""
    @State private var credential: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server key") {
                    TextField("github / notion / slack ...", text: $serverKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("表示名") {
                    TextField("任意", text: $label)
                }
                Section("Credential") {
                    SecureField("API トークンなど", text: $credential)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("MCP 接続を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { save() }.disabled(isSaving || !valid)
                }
            }
        }
    }

    private var valid: Bool {
        !serverKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !credential.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await env.mcpRepository.upsert(
                    serverKey: serverKey.trimmingCharacters(in: .whitespaces),
                    label: label.trimmingCharacters(in: .whitespaces),
                    credential: credential.trimmingCharacters(in: .whitespaces)
                )
                await onAdded()
                dismiss()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }
}
