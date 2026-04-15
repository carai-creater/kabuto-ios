import XCTest
@testable import KabutoiOS

@MainActor
final class WalletViewModelTests: XCTestCase {

    // MARK: - Fakes

    final class FakeWalletReading: WalletReading, @unchecked Sendable {
        var balancePt: Int = 0
        var grantCalls: [StoreKitPendingTransaction] = []
        var nextGrantResult: Result<IapGrantResponse, Error> = .success(
            IapGrantResponse(ok: true, alreadyGranted: false, amountPt: 0, balancePt: 0)
        )

        func fetchWallet() async throws -> WalletSnapshot {
            WalletSnapshot(
                ok: true,
                balancePt: balancePt,
                updatedAt: nil,
                recentPurchases: [],
                recentUsages: []
            )
        }

        func fetchHistory(cursor: String?, limit: Int) async throws -> WalletHistoryPage {
            WalletHistoryPage(ok: true, items: [], nextCursor: nil)
        }

        func grantIAP(_ pending: StoreKitPendingTransaction) async throws -> IapGrantResponse {
            grantCalls.append(pending)
            switch nextGrantResult {
            case .success(let resp): return resp
            case .failure(let err): throw err
            }
        }
    }

    final class FakeStoreKit: StoreKitServicing, @unchecked Sendable {
        var products: [String: StoreKitProductSummary] = [:]
        var lastError: String?
        var purchaseResult: StoreKitPurchaseResult = .unavailable
        var finishCalls: [String] = []
        var pendingTransactionToDeliver: StoreKitPendingTransaction?
        private var observerHandler: (@MainActor (StoreKitPendingTransaction) async -> Void)?

        func loadProducts() async {
            products = [
                "pt_500": StoreKitProductSummary(id: "pt_500", displayName: "500 pt", displayPrice: "¥500"),
                "pt_1100": StoreKitProductSummary(id: "pt_1100", displayName: "1,100 pt", displayPrice: "¥1,000"),
            ]
        }

        func purchase(productId: String) async throws -> StoreKitPurchaseResult {
            purchaseResult
        }

        func beginObservingTransactions(
            handler: @escaping @MainActor (StoreKitPendingTransaction) async -> Void
        ) {
            observerHandler = handler
        }

        /// Test helper: drive the observer manually.
        @MainActor
        func simulateObserverDelivery(_ pending: StoreKitPendingTransaction) async {
            await observerHandler?(pending)
        }

        func finish(transactionId: String) async {
            finishCalls.append(transactionId)
        }
    }

    // MARK: - Success path

    func testPurchaseSuccessGrantsOnServerAndFinishesTransaction() async throws {
        let wallet = FakeWalletReading()
        wallet.nextGrantResult = .success(
            IapGrantResponse(ok: true, alreadyGranted: false, amountPt: 500, balancePt: 500)
        )
        let sk = FakeStoreKit()
        sk.purchaseResult = .success(StoreKitPendingTransaction(
            productId: "pt_500",
            transactionId: "txn_success",
            signedJWS: "jws.stub.sig"
        ))

        let vm = WalletViewModel(wallet: wallet, storeKit: sk)
        let package = WalletPackages.lookup("pt_500")!
        await vm.buy(package)

        XCTAssertEqual(wallet.grantCalls.count, 1)
        XCTAssertEqual(wallet.grantCalls.first?.transactionId, "txn_success")
        XCTAssertEqual(sk.finishCalls, ["txn_success"])
        XCTAssertEqual(vm.status, .idle)
        XCTAssertEqual(vm.lastGrantMessage, "500 pt 付与しました (500 pt)")
    }

    // MARK: - Idempotency / already granted

    func testAlreadyGrantedSurfacesDistinctMessage() async throws {
        let wallet = FakeWalletReading()
        wallet.nextGrantResult = .success(
            IapGrantResponse(ok: true, alreadyGranted: true, amountPt: 1100, balancePt: 1100)
        )
        let sk = FakeStoreKit()
        sk.purchaseResult = .success(StoreKitPendingTransaction(
            productId: "pt_1100",
            transactionId: "txn_dup",
            signedJWS: "jws.stub.sig"
        ))

        let vm = WalletViewModel(wallet: wallet, storeKit: sk)
        let package = WalletPackages.lookup("pt_1100")!
        await vm.buy(package)

        XCTAssertEqual(wallet.grantCalls.count, 1)
        XCTAssertEqual(sk.finishCalls, ["txn_dup"])
        XCTAssertEqual(vm.lastGrantMessage, "既に付与済みです (1100 pt)")
        XCTAssertEqual(vm.status, .idle)
    }

    // MARK: - Server failure: do not finish so StoreKit redelivers

    func testGrantFailureLeavesTransactionUnfinished() async throws {
        struct Boom: Error {}
        let wallet = FakeWalletReading()
        wallet.nextGrantResult = .failure(Boom())
        let sk = FakeStoreKit()
        sk.purchaseResult = .success(StoreKitPendingTransaction(
            productId: "pt_500",
            transactionId: "txn_fail",
            signedJWS: "jws.stub.sig"
        ))

        let vm = WalletViewModel(wallet: wallet, storeKit: sk)
        let package = WalletPackages.lookup("pt_500")!
        await vm.buy(package)

        XCTAssertEqual(wallet.grantCalls.count, 1)
        // Important: we do NOT call finish() on failure so StoreKit
        // redelivers the transaction via Transaction.updates.
        XCTAssertTrue(sk.finishCalls.isEmpty, "finish should not be called on grant failure")
        if case .failed = vm.status { /* ok */ } else {
            XCTFail("expected .failed status, got \(vm.status)")
        }
    }

    // MARK: - Unavailable products (App Store Connect not configured)

    func testPurchaseFallsBackWhenProductsAreUnavailable() async throws {
        let wallet = FakeWalletReading()
        let sk = FakeStoreKit()
        sk.purchaseResult = .unavailable

        let vm = WalletViewModel(wallet: wallet, storeKit: sk)
        let package = WalletPackages.lookup("pt_500")!
        await vm.buy(package)

        XCTAssertTrue(wallet.grantCalls.isEmpty)
        if case .failed(let message) = vm.status {
            XCTAssertTrue(message.contains("現在購入不可"))
        } else {
            XCTFail("expected .failed status with unavailable hint")
        }
    }

    // MARK: - Observer-driven backfill

    func testObservedTransactionGetsGranted() async throws {
        let wallet = FakeWalletReading()
        wallet.nextGrantResult = .success(
            IapGrantResponse(ok: true, alreadyGranted: false, amountPt: 3500, balancePt: 3500)
        )
        let sk = FakeStoreKit()
        let vm = WalletViewModel(wallet: wallet, storeKit: sk)

        // Simulate a deferred/post-reinstall delivery.
        let delivered = StoreKitPendingTransaction(
            productId: "pt_3500",
            transactionId: "txn_observed",
            signedJWS: "jws.stub.sig"
        )
        await vm.handleObservedTransaction(delivered)

        XCTAssertEqual(wallet.grantCalls.count, 1)
        XCTAssertEqual(wallet.grantCalls.first?.transactionId, "txn_observed")
        XCTAssertEqual(sk.finishCalls, ["txn_observed"])
    }
}
