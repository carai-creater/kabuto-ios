import SwiftUI

struct WalletView: View {
    var body: some View {
        ContentUnavailableView(
            "ウォレット",
            systemImage: "creditcard",
            description: Text("Phase 5 で残高・履歴・StoreKit 購入を実装します。")
        )
        .navigationTitle("ウォレット")
    }
}

#Preview {
    NavigationStack { WalletView() }
}
