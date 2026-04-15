import Foundation

/// Static catalog of point packages the iOS app can sell. The IDs here
/// must match:
///   - the records registered in App Store Connect
///   - `src/lib/wallet/iap-packages.ts` on the kabuto backend
///
/// Placeholder IDs are in use for Phase 5. To switch to real ones later,
/// update just this file + the matching kabuto constant.
struct WalletPackage: Sendable, Identifiable, Hashable {
    let productId: String
    let amountPt: Int
    /// Informational; the real price comes from StoreKit `Product.displayPrice`.
    let expectedYen: Int
    let label: String

    var id: String { productId }
}

enum WalletPackages {
    static let all: [WalletPackage] = [
        WalletPackage(productId: "pt_500",  amountPt: 500,  expectedYen: 500,  label: "500 pt"),
        WalletPackage(productId: "pt_1100", amountPt: 1100, expectedYen: 1000, label: "1,100 pt (+100)"),
        WalletPackage(productId: "pt_3500", amountPt: 3500, expectedYen: 3000, label: "3,500 pt (+500)"),
    ]

    static var productIds: [String] { all.map(\.productId) }

    static func lookup(_ productId: String) -> WalletPackage? {
        all.first(where: { $0.productId == productId })
    }
}
