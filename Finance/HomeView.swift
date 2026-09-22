import SwiftUI

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// -1 assets, 0 home, 1 savings
    @State private var panel: CGFloat = 0
    @State private var drag: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let card: CGFloat = 168
                let range = max(geo.size.height - card, 1)
                let position = min(1, max(-1, panel + drag / range))
                let reveal = abs(position)

                VStack(spacing: 12 * reveal) {
                    if position < 0 {
                        AssetListView(showsChrome: position < -0.5)
                            .frame(height: range * -position)
                            .opacity(-position)
                            .allowsHitTesting(position < -0.85)
                    }

                    HomeHero(portfolio: portfolio, position: position)
                        .frame(height: geo.size.height - range * reveal)
                        .clipShape(RoundedRectangle(cornerRadius: 28 * reveal, style: .continuous))
                        .padding(.horizontal, 16 * reveal)
                        .shadow(color: .black.opacity(0.35 * reveal), radius: 20 * reveal, y: 8 * reveal)
                        .gesture(panelDrag(range: range))
                        .onTapGesture { if panel != 0 { snap(0) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(hint(position))
                        .accessibilityAction(named: "儲蓄目標") { snap(1) }
                        .accessibilityAction(named: "資產") { snap(-1) }
                        .accessibilityAction(named: "回到全螢幕") { snap(0) }
                        .accessibilityLabel(heroLabel(position))

                    if position > 0 {
                        SavingsTunerView()
                            .frame(height: range * position)
                            .opacity(position)
                            .allowsHitTesting(position > 0.85)
                    }
                }
            }
            .ignoresSafeArea(edges: abs(panel + drag) < 0.05 ? [.top, .bottom] : [])
            .background(Color(red: 0.03, green: 0.05, blue: 0.10).ignoresSafeArea())
            .toolbarBackground(panel < -0.5 ? .automatic : .hidden, for: .navigationBar)
            .toolbar(panel < -0.5 ? .visible : .hidden, for: .navigationBar)
        }
    }

    private func hint(_ position: CGFloat) -> String {
        if position > 0.5 { return "輕點回到全螢幕" }
        if position < -0.5 { return "輕點回到全螢幕" }
        return "上滑查看儲蓄目標，下滑查看資產"
    }

    private func panelDrag(range: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let next = min(1, max(-1, panel - value.translation.height / range))
                drag = next - panel
            }
            .onEnded { value in
                let projected = panel - value.predictedEndTranslation.height / range
                if projected > 0.35 { snap(1) }
                else if projected < -0.35 { snap(-1) }
                else { snap(0) }
            }
    }

    private func snap(_ to: CGFloat) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.88)) {
            panel = to
            drag = 0
        }
    }

    private func heroLabel(_ position: CGFloat) -> String {
        if position > 0.5 {
            let outlook = portfolio.outlook
                ?? SavingsMath.outlook(plan: .prototype, presentValue: portfolio.allocableTotal)
            return "距離目標 \(outlook.yearsText) 年，\(outlook.detailText)"
        }
        return "\(portfolio.statusTitle)。\(portfolio.allocationStatus)"
    }
}

private struct HomeHero: View {
    let portfolio: Portfolio
    var position: CGFloat

    private var reveal: CGFloat { abs(position) }
    private var toSavings: CGFloat { max(position, 0) }

    var body: some View {
        ZStack {
            GlowBackground(orbs: GlowOrb.orbs(for: portfolio))

            VStack(spacing: 14) {
                Image(systemName: "chevron.compact.down")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - reveal)
                    .padding(.top, 8)
                    .safeAreaPadding(.top)
                    .accessibilityHidden(true)
                Spacer()
                ZStack {
                    statusCopy.opacity(1 - toSavings)
                    yearsCopy.opacity(toSavings)
                }
                Spacer()
                Image(systemName: "chevron.compact.up")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - reveal)
                    .padding(.bottom, 8)
                    .safeAreaPadding(.bottom)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if toSavings > 0 {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.08))
                        Rectangle()
                            .fill(.white.opacity(0.85))
                            .frame(width: bar.size.width * outlook.progress)
                    }
                }
                .frame(height: 3)
                .opacity(toSavings)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var outlook: SavingsOutlook {
        SavingsMath.outlook(
            plan: portfolio.savings ?? .prototype,
            presentValue: portfolio.allocableTotal
        )
    }

    private var statusCopy: some View {
        VStack(spacing: 14) {
            Text(portfolio.statusTitle)
                .font(.title3.weight(.semibold))
                .tracking(6)
            Text(portfolio.allocationStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48 - 24 * reveal)
        }
    }

    private var yearsCopy: some View {
        VStack(spacing: 6) {
            Text("距離目標")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(outlook.yearsText)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text("年")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(outlook.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

#Preview("平衡") {
    HomeView()
        .environment(Portfolio(
            items: [
                AssetItem(name: "全球股票 ETF", kind: .original, amount: 1_000_000),
                AssetItem(name: "2x 槓桿 ETF", kind: .leverage, amount: 600_000),
                AssetItem(name: "活存", kind: .cash, amount: 400_000),
            ],
            savings: SavingsPlan(annualCost: 1_440_000, annualRatePercent: 7, monthlyContribution: 13_500)
        ))
}

#Preview("偏離") {
    HomeView()
        .environment(Portfolio(items: [
            AssetItem(name: "活存", kind: .cash, amount: 2_000_000),
        ]))
}
