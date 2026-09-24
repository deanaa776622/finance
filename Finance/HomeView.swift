import SwiftUI

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hideAmounts") private var hideAmounts = false
    /// -1 assets, 0 home, 1 savings
    @State private var panel: CGFloat = 0
    @State private var drag: CGFloat = 0
    @State private var safeTop: CGFloat = 0
    @State private var safeBottom: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let card: CGFloat = 168
                let range = max(geo.size.height - card, 1)
                let position = min(1, max(-1, panel + drag))
                let reveal = abs(position)
                let corner = 28 * reveal
                let drop = max(-position, 0)
                let topLift = safeTop * max(position, 0)
                let bottomLift = safeBottom * drop
                let assetTop = (safeTop + (panel < -0.5 ? 44 : 0)) * drop
                let savingsProgress = SavingsMath.outlook(
                    plan: portfolio.savings ?? .prototype,
                    presentValue: portfolio.allocableTotal
                ).progress

                VStack(spacing: 12 * reveal) {
                    if position < 0 {
                        AssetListView(showsChrome: panel < -0.5)
                            .ignoresSafeArea(edges: panel < -0.5 ? .bottom : [.top, .bottom])
                            .frame(height: max(0, range * -position - bottomLift - 12 * drop - assetTop))
                            .opacity(-position)
                            .scrollDisabled(panel > -0.95)
                            .allowsHitTesting(panel < -0.85)
                    }

                    HomeHero(portfolio: portfolio, position: position, settled: panel)
                        .frame(height: geo.size.height - range * reveal)
                        .overlay {
                            if position > 0 {
                                GeometryReader { bar in
                                    VStack(spacing: 0) {
                                        Spacer(minLength: 0)
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(.white.opacity(0.05))
                                            if savingsProgress > 0 {
                                                UnevenRoundedRectangle(
                                                    topLeadingRadius: 0,
                                                    bottomLeadingRadius: 0,
                                                    bottomTrailingRadius: 2,
                                                    topTrailingRadius: 2
                                                )
                                                .fill(LinearGradient(
                                                    colors: [.white.opacity(0.3), .white],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ))
                                                .frame(width: bar.size.width * savingsProgress)
                                                .shadow(color: .white.opacity(0.7), radius: 8)
                                            }
                                        }
                                        .frame(height: 3)
                                    }
                                }
                                .opacity(position)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .padding(.horizontal, 16 * reveal)
                        .shadow(color: .black.opacity(0.35 * reveal), radius: 20 * reveal, y: 8 * reveal)
                        .onTapGesture { if panel != 0 { snap(0) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(hint(panel))
                        .accessibilityAction(named: "儲蓄目標") { snap(1) }
                        .accessibilityAction(named: "資產") { snap(-1) }
                        .accessibilityAction(named: "回到全螢幕") { snap(0) }
                        .accessibilityLabel(heroLabel(panel))

                    if position > 0 {
                        SavingsTunerView()
                            .ignoresSafeArea(edges: .top)
                            .frame(height: max(0, range * position - topLift))
                            .opacity(position)
                            .allowsHitTesting(position > 0.85)
                    }
                }
                .padding(.top, topLift + assetTop)
                .padding(.bottom, bottomLift)
                .contentShape(Rectangle())
                .gesture(panelDrag(range: range))
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.top } action: { safeTop = $0 }
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.bottom } action: { safeBottom = $0 }
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(panel < -0.5 ? .automatic : .hidden, for: .navigationBar)
            .toolbar(panel < -0.5 ? .visible : .hidden, for: .navigationBar)
        }
    }

    private static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .map(\.safeAreaInsets)
            .max { $0.top < $1.top } ?? .zero
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
                let end = min(1, max(-1, panel - value.translation.height / range))
                let moved = end - panel
                if abs(moved) <= 0.25 { snap(panel) }
                else if panel == 0 { snap(moved > 0 ? 1 : -1) }
                else if moved < 0 { snap(end < -0.25 ? -1 : 0) }
                else { snap(end > 0.25 ? 1 : 0) }
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
        if position < -0.5 {
            if hideAmounts { return "總淨值已隱藏" }
            return "總淨值 \(MoneyFormat.string(portfolio.netWorth))"
        }
        return "\(portfolio.statusTitle)。\(portfolio.allocationStatus)"
    }
}

private struct HomeHero: View {
    let portfolio: Portfolio
    var position: CGFloat
    var settled: CGFloat
    @AppStorage("hideAmounts") private var hideAmounts = false

    private var reveal: CGFloat { abs(position) }
    private var settledReveal: CGFloat { abs(settled) }
    private var toSavings: CGFloat { max(settled, 0) }
    private var toAssets: CGFloat { max(-settled, 0) }

    var body: some View {
        ZStack {
            GlowBackground(orbs: GlowOrb.orbs(for: portfolio), compact: reveal)

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
                    statusCopy.opacity(1 - settledReveal)
                    netWorthCopy.opacity(toAssets)
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
                .padding(.horizontal, 48 - 24 * settledReveal)
        }
    }

    private var netWorthCopy: some View {
        VStack(spacing: 6) {
            Text("總淨值")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
            Text(MoneyFormat.string(portfolio.netWorth, hidden: hideAmounts))
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(allocationPercents)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
    }

    private var allocationPercents: String {
        func pct(_ kind: AssetKind) -> Int { Int(portfolio.actualPercent(for: kind).rounded()) }
        return "原 \(pct(.original))%　槓 \(pct(.leverage))%　現 \(pct(.cash))%"
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
