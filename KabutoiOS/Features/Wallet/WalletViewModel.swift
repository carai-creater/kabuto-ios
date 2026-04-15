import Foundation
import Observation

/// Drives the Wallet screen: balance + history pagination + purchase flow.
/// Pure — no SwiftUI imports, so tests can exercise state transitions by
/// injecting an in-memory `StoreKitServicing` and a stubbed `WalletRepository`.
@Observable
@MainActor
final class WalletViewModel {
    enum Status: Equatable, Sendable {
        case idle
        case loading
        case purchasing(productId: String)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var snapshot: WalletSnapshot?
    private(set) var history: [HistoryEntry] = []
    private(set) var nextCursor: String?
    private(set) var storeKit: any StoreKitServicing
    private(set) var lastGrantMessage: String?

    private let wallet: any WalletReading

    init(wallet: any WalletReading, storeKit: any StoreKitServicing) {
        self.wallet = wallet
        self.storeKit = storeKit
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await loadProducts()
        await refresh()
        storeKit.beginObservingTransactions { [weak self] pending in
            await self?.handleObservedTransaction(pending)
        }
    }

    func loadProducts() async {
        await storeKit.loadProducts()
    }

    func refresh() async {
        status = .loading
        do {
            snapshot = try await wallet.fetchWallet()
            let page = try await wallet.fetchHistory(cursor: nil as String?, limit: 30)
            history = page.items
            nextCursor = page.nextCursor
            status = .idle
        } catch {
            status = .failed(String(describing: error))
        }
    }

    func loadMoreHistory() async {
        guard let cursor = nextCursor else { return }
        do {
            let page = try await wallet.fetchHistory(cursor: cursor, limit: 30)
            history.append(contentsOf: page.items)
            nextCursor = page.nextCursor
        } catch {
            // Non-fatal — keep existing page.
        }
    }

    // MARK: - Purchase

    func buy(_ package: WalletPackage) async {
        status = .purchasing(productId: package.productId)
        lastGrantMessage = nil
        do {
            let result = try await storeKit.purchase(productId: package.productId)
            switch result {
            case .unavailable:
                status = .failed("現在購入不可（商品が App Store Connect に登録されていません）")
            case .userCancelled:
                status = .idle
            case .pending:
                lastGrantMessage = "購入が保留中です（承認待ち）"
                status = .idle
            case .success(let pending):
                await grantToServer(pending)
            }
        } catch {
            status = .failed(String(describing: error))
        }
    }

    private func grantToServer(_ pending: StoreKitPendingTransaction) async {
        do {
            let response = try await wallet.grantIAP(pending)
            if response.alreadyGranted {
                lastGrantMessage = "既に付与済みです (\(response.balancePt) pt)"
            } else {
                lastGrantMessage = "\(response.amountPt) pt 付与しました (\(response.balancePt) pt)"
            }
            await storeKit.finish(transactionId: pending.transactionId)
            status = .idle
            // Refresh balance display.
            await refresh()
        } catch {
            // Leave the transaction unfinished — StoreKit will redeliver
            // on next launch via `beginObservingTransactions`, and the
            // server's idempotency check handles eventual retry.
            status = .failed("付与に失敗しました: \(error)")
        }
    }

    /// Called by the StoreKit `Transaction.updates` observer when a
    /// deferred / post-reinstall transaction arrives. Runs the same
    /// grant flow as a user-initiated purchase.
    func handleObservedTransaction(_ pending: StoreKitPendingTransaction) async {
        await grantToServer(pending)
    }
}
