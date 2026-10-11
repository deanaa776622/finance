import SwiftUI

/// Finger position once a drag passes the slack. Held on a class so the arming sample cannot be published late.
private final class DragSession {
    var anchor: CGPoint?
    var axis: Axis?
    /// Where the finger sat in the card, 0 = top, 1 = bottom. That point tracks the finger.
    var grabFraction: CGFloat = 0.5
    var decided = false
    var ignored = false
}

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
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
    @State private var dragSession = DragSession()
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
                let card = Self.dockedCard
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

                let assetHeight = position < 0 ? max(0, range * -position - bottomLift - assetTop) : 0
                let savingsHeight = position > 0 ? max(0, range * position - topLift) : 0

                VStack(spacing: 0) {
                    shellSlot(height: assetHeight) {
                        AssetListView(
                            showsChrome: position < -0.5,
                            topInset: AssetListView.restingTopInset * drop,
                            exposureOnly: exposureList
                        )
                        .ignoresSafeArea(edges: .bottom)
                        .mask {
                            VStack(spacing: 0) {
                                ScrollFade.top
                                Color.black
                            }
                        }
                        .opacity(position < 0 ? -position : 0)
                        .scrollDisabled(panel > -0.95)
                        .allowsHitTesting(position < 0 && panel < -0.85)
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
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { heroFrame = $0 }
                        .onTapGesture { if panel != 0 { snap(0) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(hint(panel))
                        .accessibilityAction(named: "儲蓄目標") { snap(1) }
                        .accessibilityAction(named: "資產") { snap(-1) }
                        .accessibilityAction(named: "回到全螢幕") { snap(0) }
                        .accessibilityAction(named: "總淨值") { snapLens(0) }
                        .accessibilityAction(named: "總曝險") { snapLens(1) }
                        .accessibilityLabel(heroLabel(panel))

                    shellSlot(height: savingsHeight) {
                        SavingsTunerView()
                            .ignoresSafeArea(edges: .top)
                            .opacity(position > 0 ? position : 0)
                            .allowsHitTesting(position > 0.85)
                    }
                    .padding(.top, position > 0 ? 12 * position : 0)
                }
                .padding(.top, topLift + assetTop)
                .padding(.bottom, bottomLift)
                .contentShape(Rectangle())
                .simultaneousGesture(panelDrag(screen: geo.size.height))
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.top } action: { safeTop = $0 }
                    .onGeometryChange(for: CGFloat.self) { _ in Self.windowSafeArea.bottom } action: { safeBottom = $0 }
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .background(palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private static let dockedCard: CGFloat = 168

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

    /// Panels stay in the stack at height 0. Inserting them on the first pixel made the card jump.
    private func shellSlot<Content: View>(
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Color.clear
            .frame(height: max(0, height))
            .overlay(alignment: .top) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: max(height, 1), alignment: .top)
            }
            .clipped()
            .accessibilityHidden(height <= 0)
    }

    private func panelDrag(screen: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !dragSession.decided {
                    dragSession.decided = true
                    dragSession.ignored = ignoresShell(value.startLocation)
                }
                if dragSession.ignored { return }
                let dx = value.location.x - value.startLocation.x
                let dy = value.location.y - value.startLocation.y
                if dragSession.anchor == nil {
                    guard hypot(dx, dy) >= 10 else { return }
                    dragSession.anchor = value.location
                    let height = max(heroFrame.height, 1)
                    dragSession.grabFraction = min(1, max(0, (value.location.y - heroFrame.minY) / height))
                    _ = lockedAxis(dx: dx, dy: dy, start: value.startLocation)
                    return
                }
                let anchor = dragSession.anchor ?? value.location
                let moved = CGSize(width: value.location.x - anchor.x, height: value.location.y - anchor.y)
                applyDrag(moved, axis: dragSession.axis ?? .vertical, screen: screen)
            }
            .onEnded { value in
                let axis = dragSession.axis
                let anchor = dragSession.anchor
                let moved = anchor.map {
                    CGSize(width: value.location.x - $0.x, height: value.location.y - $0.y)
                }
                if let moved {
                    if axis == .horizontal {
                        endLens(moved)
                    } else {
                        endPanel(moved, screen: screen)
                    }
                }
                dragSession.anchor = nil
                dragSession.axis = nil
                dragSession.grabFraction = 0.5
                dragSession.decided = false
                dragSession.ignored = false
            }
    }

    /// List and savings own the drag once they are settled. The card does not.
    private func ignoresShell(_ start: CGPoint) -> Bool {
        if heroFrame.contains(start) { return false }
        return panel <= -0.95 || panel >= 0.95
    }

    private func applyDrag(_ moved: CGSize, axis: Axis, screen: CGFloat) {
        if axis == .horizontal {
            let width = max(heroFrame.width, 1)
            let next = min(1, max(0, lens - moved.width / width))
            lensDrag = next - lens
        } else {
            let next = trackedPanel(dy: moved.height, screen: screen)
            drag = next - panel
        }
    }

    /// Card height changes while it moves, so the point under the finger is what travels 1:1.
    private func trackedPanel(dy: CGFloat, screen: CGFloat) -> CGFloat {
        let range = max(screen - Self.dockedCard, 1)
        let f = min(1, max(0, dragSession.grabFraction))
        let slopeDown = range * (f - 1) + safeBottom
        let slopeUp = safeTop - f * range
        guard slopeDown < -0.5, slopeUp < -0.5 else {
            return min(1, max(-1, panel - dy / range))
        }
        let origin = f * screen
        let base = origin + (panel < 0 ? slopeDown : slopeUp) * panel
        let target = base + dy
        if target >= origin {
            return min(0, max(-1, (target - origin) / slopeDown))
        }
        return min(1, max(0, (target - origin) / slopeUp))
    }

    private func lockedAxis(dx: CGFloat, dy: CGFloat, start: CGPoint) -> Axis {
        if let axis = dragSession.axis { return axis }
        let horizontal = abs(dx) > abs(dy)
        let onHero = panel < -0.4 && heroFrame.contains(start)
        let axis: Axis = horizontal && onHero ? .horizontal : .vertical
        dragSession.axis = axis
        if axis == .horizontal {
            dotToken += 1
            withAnimation(.easeOut(duration: 0.12)) { showDots = true }
        }
        return axis
    }

    private func endPanel(_ translation: CGSize, screen: CGFloat) {
        let end = trackedPanel(dy: translation.height, screen: screen)
        let moved = end - panel
        if abs(moved) <= 0.25 { snap(panel) }
        else if panel == 0 { snap(moved > 0 ? 1 : -1) }
        else if moved < 0 { snap(end < -0.25 ? -1 : 0) }
        else { snap(end > 0.25 ? 1 : 0) }
    }

    private func endLens(_ translation: CGSize) {
        let width = max(heroFrame.width, 1)
        let end = min(1, max(0, lens - translation.width / width))
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
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion {
                guard token == dotToken, dragSession.axis == nil else { return }
                withAnimation(.easeOut(duration: 0.25)) { showDots = false }
            }
            withTransaction(transaction) {
                lens = to
                exposureList = to > 0.5
                AssetListMemory.showsExposure = to > 0.5
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
        .environment(Palette())
}

#Preview("偏離") {
    HomeView()
        .environment(Portfolio(items: [
            AssetItem(name: "活存", kind: .cash, amount: 2_000_000),
        ]))
        .environment(Palette())
}
