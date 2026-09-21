import SwiftUI

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed = false
    @State private var drag: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let card: CGFloat = 168
                let range = max(geo.size.height - card, 1)
                let progress = min(1, max(0, (collapsed ? 1 : 0) + drag / range))

                VStack(spacing: 12 * progress) {
                    HomeHero(portfolio: portfolio, collapse: progress)
                        .frame(height: geo.size.height - range * progress)
                        .clipShape(RoundedRectangle(cornerRadius: 28 * progress, style: .continuous))
                        .padding(.horizontal, 16 * progress)
                        .shadow(color: .black.opacity(0.35 * progress), radius: 20 * progress, y: 8 * progress)
                        .gesture(collapseDrag(range: range))
                        .onTapGesture { if collapsed { snap(false) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(collapsed ? "輕點回到全螢幕" : "向上滑動查看資產")
                        .accessibilityAction { snap(!collapsed) }

                    AssetListView(showsChrome: collapsed)
                        .frame(height: range * progress)
                        .opacity(progress)
                        .allowsHitTesting(progress > 0.85)
                }
            }
            .ignoresSafeArea(edges: collapsed ? [] : [.top, .bottom])
            .background(Color(red: 0.03, green: 0.05, blue: 0.10).ignoresSafeArea())
            .toolbarBackground(collapsed ? .automatic : .hidden, for: .navigationBar)
        }
    }

    private func collapseDrag(range: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let raw = (collapsed ? range : 0) - value.translation.height
                drag = min(range, max(0, raw)) - (collapsed ? range : 0)
            }
            .onEnded { value in
                let projected = (collapsed ? range : 0) - value.predictedEndTranslation.height
                snap(projected > range * 0.35)
            }
    }

    private func snap(_ toCollapsed: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.88)) {
            collapsed = toCollapsed
            drag = 0
        }
    }
}

private struct HomeHero: View {
    let portfolio: Portfolio
    var collapse: CGFloat

    var body: some View {
        ZStack {
            GlowBackground(orbs: GlowOrb.orbs(for: portfolio))

            VStack(spacing: 14) {
                Spacer()
                Text(portfolio.statusTitle)
                    .font(.title3.weight(.semibold))
                    .tracking(6)
                Text(portfolio.allocationStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48 - 24 * collapse)
                Spacer()
                Image(systemName: "chevron.compact.up")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - collapse)
                    .padding(.bottom, 8)
                    .safeAreaPadding(.bottom)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
