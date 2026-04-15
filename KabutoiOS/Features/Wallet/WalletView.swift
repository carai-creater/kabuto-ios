import SwiftUI

struct WalletView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: WalletViewModel?

    var body: some View {
        Group {
            if case .signedOut = env.auth.state {
                ContentUnavailableView {
                    Label("サインインが必要です", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("残高表示と購入にはログインが必要です。")
                } actions: {
                    Button("ログイン") { env.requireAuth() }
                }
            } else if let vm {
                list(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("ウォレット")
        .task { await ensureViewModel() }
        .refreshable { await vm?.refresh() }
    }

    @ViewBuilder
    private func list(vm: WalletViewModel) -> some View {
        List {
            balanceSection(vm)
            productsSection(vm)
            if !vm.history.isEmpty {
                historySection(vm)
            }
            if case .failed(let message) = vm.status {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let m = vm.lastGrantMessage {
                Section {
                    Label(m, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func balanceSection(_ vm: WalletViewModel) -> some View {
        Section("残高") {
            HStack {
                Image(systemName: "yensign.circle.fill").foregroundStyle(.green).font(.title2)
                Text("\((vm.snapshot?.balancePt) ?? 0) pt")
                    .font(.title.monospacedDigit().bold())
                Spacer()
                if vm.status == .loading {
                    ProgressView()
                }
            }
        }
    }

    private func productsSection(_ vm: WalletViewModel) -> some View {
        Section("ポイントを購入") {
            if vm.storeKit.products.isEmpty {
                Label(
                    vm.storeKit.lastError ?? "現在購入不可（商品情報を取得できませんでした）",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            ForEach(WalletPackages.all) { package in
                let sk = vm.storeKit.products[package.productId]
                Button {
                    Task { await vm.buy(package) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.label).font(.headline)
                            Text(sk?.displayPrice ?? "¥\(package.expectedYen)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .purchasing(let productId) = vm.status, productId == package.productId {
                            ProgressView()
                        } else {
                            Image(systemName: "cart")
                        }
                    }
                }
                .disabled(sk == nil || isPurchasing(vm))
            }
        }
    }

    private func historySection(_ vm: WalletViewModel) -> some View {
        Section("履歴") {
            ForEach(vm.history) { entry in
                HistoryRow(entry: entry)
            }
            if vm.nextCursor != nil {
                Button("もっと見る") {
                    Task { await vm.loadMoreHistory() }
                }
                .font(.footnote)
            }
        }
    }

    private func isPurchasing(_ vm: WalletViewModel) -> Bool {
        if case .purchasing = vm.status { return true }
        return false
    }

    private func ensureViewModel() async {
        if vm == nil {
            vm = WalletViewModel(wallet: env.walletRepository, storeKit: env.storeKit)
            await vm?.onAppear()
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack {
            Image(systemName: entry.kind == "purchase" ? "plus.circle.fill" : "message.circle")
                .foregroundStyle(entry.kind == "purchase" ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.amountPt > 0 ? "+" : "")\(entry.amountPt) pt")
                .font(.callout.monospacedDigit())
                .foregroundStyle(entry.amountPt > 0 ? .green : .primary)
        }
    }

    private var label: String {
        switch entry.kind {
        case "purchase":
            return entry.source == "iap" ? "購入 (App Store)" : "購入 (Stripe)"
        case "usage":
            return "チャット利用"
        default:
            return entry.kind
        }
    }
}

#Preview {
    NavigationStack { WalletView() }
        .environment(AppEnvironment(config: .preview))
}
