import SwiftUI

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio

    var body: some View {
        NavigationStack {
            ZStack {
                GlowBackground(orbs: GlowOrb.orbs(for: portfolio))

                VStack(spacing: 14) {
                    Text(portfolio.statusTitle)
                        .font(.title3.weight(.semibold))
                        .tracking(6)
                    Text(portfolio.allocationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .accessibilityElement(children: .combine)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("資產") { AssetListView() }
                }
            }
        }
    }
}

#Preview("平衡") {
    HomeView()
        .environment(Portfolio(items: [
            AssetItem(name: "全球股票 ETF", kind: .original, amount: 1_000_000),
            AssetItem(name: "2x 槓桿 ETF", kind: .leverage, amount: 600_000),
            AssetItem(name: "活存", kind: .cash, amount: 400_000),
        ]))
}

#Preview("偏離") {
    HomeView()
        .environment(Portfolio(items: [
            AssetItem(name: "活存", kind: .cash, amount: 2_000_000),
        ]))
}
