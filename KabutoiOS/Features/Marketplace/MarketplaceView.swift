import SwiftUI

struct MarketplaceView: View {
    var body: some View {
        ContentUnavailableView(
            "マーケットプレイス",
            systemImage: "sparkles",
            description: Text("Phase 3 で /api/v1/agents を接続します。")
        )
        .navigationTitle("エージェント")
    }
}

#Preview {
    NavigationStack { MarketplaceView() }
}
