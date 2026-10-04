import SwiftUI

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hideAmounts") private var hideAmounts = false
    /// -1 assets, 0 home, 1 savings
    @State private var panel: CGFloat = 0
    @State private var drag: CGFloat = 0
    /// 0 = 總淨值, 1 = 總曝險
    @State private var lens: CGFloat = 0
    @State private var lensDrag: CGFloat = 0
    @State private var showDots = false
    @State private var exposureList = false
    @State private var heroFrame: CGRect = .zero
    @State private var dragAxis: Axis?
    @State private var dotToken = 0
    @State private var safeTop: CGFloat = 0
    @State private var safeBottom: CGFloat = 0

    init() {
        let exposure = AssetListMemory.showsExposure
        _lens = State(initialValue: exposure ? 1 : 0)
        _exposureList = State(initialValue: exposure)
    }

    private var lensPosition: CGFloat { min(1, max(0, lens + lensDrag)) }

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
                let assetTop = safeTop * drop
                let savingsProgress = SavingsMath.outlook(
                    plan: portfolio.savings ?? .prototype,
                    presentValue: portfolio.allocableTotal
                ).progress

                VStack(spacing: position < 0 ? 0 : 12 * reveal) {
                    if position < 0 {
                        AssetListView(
                            showsChrome: position < -0.5,
                            topInset: AssetListView.restingTopInset * drop,
                            exposureOnly: exposureList
                        )
                            .ignoresSafeArea(edges: .bottom)
                            .frame(height: max(0, range * -position - bottomLift - assetTop))
                            .mask {
                                VStack(spacing: 0) {
                                    ScrollFade.top
                                    Color.black
                                }
                            }
                            .opacity(-position)
                            .scrollDisabled(panel > -0.95)
                            .allowsHitTesting(panel < -0.85)
                    }

                    HomeHero(
                        portfolio: portfolio,
                        position: position,
                        settled: panel,
                        lens: lensPosition,
                        showsDots: showDots
                    )
                        .frame(height: geo.size.height - range * reveal)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(.white.opacity(0.05))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    GeometryReader { bar in
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
                                            .frame(width: bar.size.width * savingsProgress, height: 3)
                                            .shadow(color: .white.opacity(0.7), radius: 8)
                                        }
                                    }
                                }
                                .opacity(max(panel, 0))
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .padding(.horizontal, 16 * reveal)
                        .shadow(color: .black.opacity(0.35 * reveal), radius: 20 * reveal, y: 8 * reveal)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("home")) } action: { heroFrame = $0 }
                        .onTapGesture { if panel != 0 { snap(0) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(hint(panel))
                        .accessibilityAction(named: "儲蓄目標") { snap(1) }
                        .accessibilityAction(named: "資產") { snap(-1) }
                        .accessibilityAction(named: "回到全螢幕") { snap(0) }
                        .accessibilityAction(named: "總淨值") { snapLens(0) }
                        .accessibilityAction(named: "總曝險") { snapLens(1) }
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
                .coordinateSpace(.named("home"))
                .gesture(panelDrag(range: range))
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.top } action: { safeTop = $0 }
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.bottom } action: { safeBottom = $0 }
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        if position < -0.5 { return "左右滑動切換總淨值與總曝險，輕點回到全螢幕" }
        return "上滑查看儲蓄目標，下滑查看資產"
    }

    private func panelDrag(range: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("home"))
            .onChanged { value in
                let axis = lockedAxis(for: value)
                if axis == .horizontal {
                    let width = max(heroFrame.width, 1)
                    let next = min(1, max(0, lens - value.translation.width / width))
                    lensDrag = next - lens
                    let showExposure = next > 0.5
                    if exposureList != showExposure { exposureList = showExposure }
                } else {
                    let next = min(1, max(-1, panel - value.translation.height / range))
                    drag = next - panel
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                if axis == .horizontal {
                    endLens(value)
                } else {
                    endPanel(value, range: range)
                }
            }
    }

    private func lockedAxis(for value: DragGesture.Value) -> Axis {
        if let dragAxis { return dragAxis }
        let horizontal = abs(value.translation.width) > abs(value.translation.height)
        let onHero = panel < -0.4 && heroFrame.contains(value.startLocation)
        let axis: Axis = horizontal && onHero ? .horizontal : .vertical
        dragAxis = axis
        if axis == .horizontal {
            dotToken += 1
            withAnimation(.easeOut(duration: 0.12)) { showDots = true }
        }
        return axis
    }

    private func endPanel(_ value: DragGesture.Value, range: CGFloat) {
        let end = min(1, max(-1, panel - value.translation.height / range))
        let moved = end - panel
        if abs(moved) <= 0.25 { snap(panel) }
        else if panel == 0 { snap(moved > 0 ? 1 : -1) }
        else if moved < 0 { snap(end < -0.25 ? -1 : 0) }
        else { snap(end > 0.25 ? 1 : 0) }
    }

    private func endLens(_ value: DragGesture.Value) {
        let width = max(heroFrame.width, 1)
        let end = min(1, max(0, lens - value.translation.width / width))
        let moved = end - lens
        snapLens(abs(moved) <= 0.25 ? lens : (moved > 0 ? 1 : 0))
    }

    private func snapLens(_ to: CGFloat) {
        let current = min(1, max(0, lens + lensDrag))
        lens = current
        lensDrag = 0
        let token = dotToken
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.48, dampingFraction: 0.88)
        DispatchQueue.main.async {
            withAnimation(animation) {
                lens = to
                exposureList = to > 0.5
                AssetListMemory.showsExposure = to > 0.5
            } completion: {
                guard token == dotToken, dragAxis == nil else { return }
                withAnimation(.easeOut(duration: 0.25)) { showDots = false }
            }
        }
    }

    private func snap(_ to: CGFloat) {
        let current = min(1, max(-1, panel + drag))
        panel = current
        drag = 0
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.48, dampingFraction: 0.88)
        DispatchQueue.main.async {
            withAnimation(animation) {
                panel = to
            }
        }
    }

    private func heroLabel(_ position: CGFloat) -> String {
        if position > 0.5 {
            let outlook = portfolio.outlook
                ?? SavingsMath.outlook(plan: .prototype, presentValue: portfolio.allocableTotal)
            return "距離目標 \(outlook.yearsText) 年，\(outlook.detailText)"
        }
        if position < -0.5 {
            if hideAmounts { return exposureList ? "總曝險已隱藏" : "總淨值已隱藏" }
            if exposureList {
                return "總曝險 \(MoneyFormat.string(portfolio.exposure))，\(portfolio.allocationMixLabel)"
            }
            return "總淨值 \(MoneyFormat.string(portfolio.netWorth))"
        }
        return "\(portfolio.statusTitle)。\(portfolio.allocationStatus)"
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
