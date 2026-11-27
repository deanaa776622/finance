import SwiftUI

/// Finger position once a drag passes the slack. Held on a class so the arming sample cannot be published late.
private final class DragSession {
    /// First sample of the gesture now in progress. A new finger-down has a new start.
    var start: CGPoint?
    var anchor: CGPoint?
    var axis: Axis?
    /// Where the finger sat in the card, 0 = top, 1 = bottom. That point tracks the finger.
    var grabFraction: CGFloat = 0.5
    var ignored = false
}

struct HomeView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage(ProPreview.key) private var isPro = false
    /// -1 assets, 0 home, 1 savings. Animated, so it passes through values between pages.
    @State private var panel: CGFloat = 0
    /// The page the sheet is committed to. Stays on a detent, so a flick cannot park between pages and lock the list.
    @State private var dock: CGFloat = 0
    @State private var drag: CGFloat = 0
    /// 0 = 總淨值, 1 = 總曝險
    @State private var lens: CGFloat = 0
    @State private var lensDrag: CGFloat = 0
    @State private var showDots = false
    @State private var exposureList = false
    @State private var heroFrame: CGRect = .zero
    @State private var dragSession = DragSession()
    @State private var dotToken = 0
    /// Settled window. A rotation layout pass still sees the previous orientation until UIKit commits it.
    @State private var windowSize = Self.windowBounds.size
    @State private var safeTop = Self.windowSafeArea.top
    @State private var safeBottom = Self.windowSafeArea.bottom
    @State private var safeLeft = Self.windowSafeArea.left
    @State private var safeRight = Self.windowSafeArea.right
    /// Unfolded Duo. Portrait then keeps the menu in the top safe area, not the phone's bottom bar.
    @State private var unfolded = false
    /// Hinge closed. A phone with no hinge stays false.
    @State private var folded = false
    /// Folded, hinge up. Home only, no touches, screen stays on.
    @State private var exhibit = false
    /// One grouping for both lenses. Closing the page must not drop open groups or merges.
    @State private var netGroups = AssetGroups()

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
                let bottomLift = dockedBottom * drop
                let assetTop = safeTop * drop
                let savingsProgress = portfolio.outlook?.progress ?? 0

                let savingsGap: CGFloat = position > 0 ? 12 * position : 0
                let assetHeight = position < 0 ? max(0, range * -position - bottomLift - assetTop) : 0
                let savingsHeight = position > 0 ? max(0, range * position - topLift - savingsGap) : 0
                let heroHeight = geo.size.height - range * reveal
                // Unfolded and wider than tall. The asset page splits down the hinge.
                let landscape = unfolded && windowSize.width > windowSize.height
                let assetOpen = min(1, max(-position, 0))
                let lead = landscape && position < 0
                    ? (geo.size.width / 2 + 16) * assetOpen
                    : (safeLeft + 16) * reveal
                let trail = (safeRight + 16) * reveal

                VStack(spacing: 0) {
                    shellSlot(height: assetHeight) {
                        if landscape {
                            Color.clear
                        } else {
                            assetPage(position: position, drop: drop, split: false, reserve: 0)
                                .opacity(position < 0 ? -position : 0)
                        }
                    }

                    if landscape {
                        Color.clear
                            .frame(height: heroHeight)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    } else {
                        heroFace(position: position, height: heroHeight, corner: corner, progress: savingsProgress, screen: geo.size)
                            .padding(.leading, lead)
                            .padding(.trailing, trail)
                    }

                    shellSlot(height: savingsHeight) {
                        SavingsTunerView(
                            showsChrome: position > 0.5,
                            sideColumn: sideStatus,
                            topColumn: topColumn,
                            assetGroups: netGroups
                        )
                            .padding(.leading, safeLeft)
                            .padding(.trailing, safeRight)
                            .ignoresSafeArea(edges: .top)
                            .opacity(position > 0 ? position : 0)
                            .allowsHitTesting(position > 0.85)
                    }
                    .padding(.top, savingsGap)
                }
                .padding(.top, topLift + assetTop)
                .padding(.bottom, bottomLift)
                .overlay(alignment: .topLeading) {
                    // Stay mounted. A threshold here freezes the page for the tap-home animation.
                    if landscape {
                        movingAssetPage(
                            width: geo.size.width,
                            screen: geo.size,
                            settledAsset: max(0, range - dockedBottom - safeTop),
                            open: assetOpen,
                            position: position
                        )
                        .allowsHitTesting(assetOpen > 0)
                        .accessibilityHidden(assetOpen == 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if landscape {
                        let cardTop = position < 0 ? assetHeight : 0
                        heroFace(position: position, height: heroHeight, corner: corner, progress: savingsProgress, screen: geo.size)
                            .frame(width: max(0, geo.size.width - lead - trail), height: heroHeight)
                            .padding(.top, cardTop)
                            .padding(.trailing, trail)
                            .contentShape(CardHit(top: cardTop, trail: trail, cardHeight: heroHeight))
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(panelDrag(screen: geo.size.height))
            }
            .background {
                UnfoldedHinge(isUnfolded: $unfolded, isFolded: $folded, onChrome: applyChrome, onExhibit: setExhibit)
            }
            .ignoresSafeArea()
            .background(palette.ground.ignoresSafeArea())
            .preferredColorScheme(palette.colorScheme)
            .toolbar((sideStatus || topColumn) && abs(panel + drag) > 0.5 ? .visible : .hidden, for: .navigationBar)
        }
        .environment(\.standDisplay, exhibit)
        .allowsHitTesting(!exhibit)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if exhibit {
                clearDrag()
                return
            }
            releaseDrag()
        }
        .onAppear(perform: GestureReset.arm)
    }

    private static let dockedCard: CGFloat = 168

    private func assetPage(
        position: CGFloat,
        drop: CGFloat,
        split: Bool,
        reserve: CGFloat
    ) -> some View {
        AssetListView(
            showsChrome: position < -0.5,
            sideColumn: sideStatus,
            topColumn: topColumn,
            topInset: AssetListView.restingTopInset * drop,
            exposureOnly: exposureList,
            cover: folded,
            splitPane: split,
            cardReserve: reserve,
            safeLeading: safeLeft,
            safeTrailing: safeRight,
            groups: netGroups
        )
        .padding(.leading, split ? 0 : safeLeft)
        .padding(.trailing, split ? 0 : safeRight)
        .ignoresSafeArea(edges: .bottom)
        .scrollDisabled(dock != -1)
        .allowsHitTesting(position < 0 && (dock == -1 || panel < -0.85))
    }

    /// Settled landscape asset page. Opening and closing only slide this layout.
    /// The home card shrinks onto the reserved slot on its own.
    private func movingAssetPage(
        width: CGFloat,
        screen: CGSize,
        settledAsset: CGFloat,
        open: CGFloat,
        position: CGFloat
    ) -> some View {
        let pageHeight = settledAsset + Self.dockedCard
        return assetPage(position: position, drop: 1, split: true, reserve: Self.dockedCard)
            .frame(width: width, height: pageHeight)
            .offset(y: settledAsset * (open - 1))
            .frame(width: width, height: screen.height, alignment: .top)
            .clipped()
            .opacity(open)
    }

    private func heroFace(
        position: CGFloat,
        height: CGFloat,
        corner: CGFloat,
        progress: Double,
        screen: CGSize
    ) -> some View {
        let reveal = abs(position)
        return HomeHero(
            portfolio: portfolio,
            position: position,
            settled: panel,
            lens: lensPosition,
            showsDots: showDots,
            screen: screen,
            safeTop: safeTop,
            safeBottom: safeBottom,
            safeLeft: safeLeft,
            safeRight: safeRight,
            opensVertically: windowSize.width < windowSize.height,
            unfolded: unfolded,
            exhibit: exhibit
        )
        .frame(height: height)
        .overlay(alignment: .bottom) {
            YearsProgressBar(progress: progress)
                .opacity(portfolio.savings == nil ? 0 : max(panel, 0))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
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
    }

    /// Status column on the left or the right. A tall frame must not steal the menu while this is set.
    private var sideStatus: Bool { safeLeft > 20 || safeRight > 20 }

    /// Status column is on the side: folded cover, or unfolded landscape (wider than tall).
    /// The card then sits as far from the bottom as the trend panel sits from the top.
    private var dockedBottom: CGFloat {
        let unfoldedLandscape = unfolded && windowSize.width > windowSize.height
        guard (sideStatus && !unfolded) || unfoldedLandscape else { return safeBottom }
        return safeTop + AssetListView.chartPanelTop
    }

    /// Unfolded Duo, taller than wide, and the status column is not on the side.
    private var topColumn: Bool {
        unfolded && windowSize.width < windowSize.height && !sideStatus
    }

    private func setExhibit(_ on: Bool) {
        guard exhibit != on else { return }
        exhibit = on
        UIApplication.shared.isIdleTimerDisabled = on
        guard on else { return }
        snap(0)
    }

    private func applyChrome(_ size: CGSize, _ insets: UIEdgeInsets) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if windowSize != size { windowSize = size }
            if safeTop != insets.top { safeTop = insets.top }
            if safeBottom != insets.bottom { safeBottom = insets.bottom }
            if safeLeft != insets.left { safeLeft = insets.left }
            if safeRight != insets.right { safeRight = insets.right }
        }
    }

    private static var windowBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .map(\.bounds)
            .max { $0.width * $0.height < $1.width * $1.height } ?? .zero
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
        // On the home card the finger tracks immediately. Once a page is open, leave the first
        // movement to that page's scroll; a zero-distance drag here keeps the list from ever moving.
        DragGesture(minimumDistance: dock == 0 ? 0 : 18, coordinateSpace: .global)
            .onChanged { value in
                if exhibit { return }
                // A chart scrub can end without onEnded. The next finger-down must not inherit "ignore".
                if dragSession.start != value.startLocation {
                    dragSession.start = value.startLocation
                    dragSession.anchor = nil
                    dragSession.axis = nil
                    dragSession.grabFraction = 0.5
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
                if exhibit {
                    clearDrag()
                    return
                }
                let axis = dragSession.axis
                let moved = dragSession.anchor.map {
                    CGSize(width: value.location.x - $0.x, height: value.location.y - $0.y)
                }
                if let moved {
                    if axis == .horizontal {
                        endLens(moved)
                    } else {
                        endPanel(moved, screen: screen)
                    }
                }
                clearDrag()
            }
    }

    /// App 切走時系統取消觸控，不一定會呼叫 onEnded。狀態留著的話，回來之後滑動會一直被丟掉。
    private func releaseDrag() {
        let axis = dragSession.axis
        let tracking = dragSession.anchor != nil
        clearDrag()
        guard tracking else { return }
        if axis == .horizontal {
            settleLens(min(1, max(0, lens + lensDrag)))
        } else {
            settlePanel(min(1, max(-1, panel + drag)))
        }
    }

    private func clearDrag() {
        dragSession.start = nil
        dragSession.anchor = nil
        dragSession.axis = nil
        dragSession.grabFraction = 0.5
        dragSession.ignored = false
    }

    /// List and savings own the drag once that page is committed. The card does not.
    private func ignoresShell(_ start: CGPoint) -> Bool {
        if heroFrame.contains(start) { return false }
        return dock != 0
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
        let slopeDown = range * (f - 1) + dockedBottom
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
        } else {
            hidePageDots()
        }
        return axis
    }

    private func endPanel(_ translation: CGSize, screen: CGFloat) {
        settlePanel(trackedPanel(dy: translation.height, screen: screen))
    }

    private func settlePanel(_ end: CGFloat) {
        let moved = end - panel
        if abs(moved) <= 0.25 { snap(panel) }
        else if panel == 0 { snap(moved > 0 ? 1 : -1) }
        else if moved < 0 { snap(end < -0.25 ? -1 : 0) }
        else { snap(end > 0.25 ? 1 : 0) }
    }

    private func endLens(_ translation: CGSize) {
        let width = max(heroFrame.width, 1)
        settleLens(min(1, max(0, lens - translation.width / width)))
    }

    private func settleLens(_ end: CGFloat) {
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
                guard token == dotToken else { return }
                hidePageDots()
            }
            withTransaction(transaction) {
                lens = to
                exposureList = to > 0.5
                AssetListMemory.showsExposure = to > 0.5
            }
        }
    }

    private func snap(_ to: CGFloat) {
        let detent: CGFloat = to > 0.5 ? 1 : (to < -0.5 ? -1 : 0)
        if exhibit, detent != 0 { return }
        let current = min(1, max(-1, panel + drag))
        panel = current
        drag = 0
        dock = detent
        if detent != -1 { hidePageDots() }
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.48, dampingFraction: 0.88)
        DispatchQueue.main.async {
            withAnimation(animation) {
                panel = detent
            }
        }
    }

    /// Net-worth and exposure only. A later vertical flick must not leave them on 距離目標.
    private func hidePageDots() {
        guard showDots else { return }
        dotToken += 1
        withAnimation(.easeOut(duration: 0.2)) { showDots = false }
    }

    private func heroLabel(_ position: CGFloat) -> String {
        if position > 0.5 {
            if isPro, let outlook = portfolio.outlook {
                return "距離目標 \(outlook.yearsText) 年，\(outlook.detailText)"
            }
            guard let line = ProPreview.coverageLine(portfolio: portfolio) else {
                return "儲蓄目標尚未設定"
            }
            let amount = hideAmounts ? "金額已隱藏" : MoneyFormat.string(line.amount)
            return "距離目標 \(amount)，\(line.detail)"
        }
        if position < -0.5 {
            let title = exposureList ? "總曝險" : "總淨值"
            if hideAmounts { return "\(title)已隱藏" }
            let amount = exposureList ? portfolio.exposure : portfolio.netWorth
            return "\(title) \(MoneyFormat.string(amount))"
        }
        return "\(portfolio.statusTitle)。\(portfolio.homeSubtitle())"
    }
}

/// Hit target of the total card. The padding that places it is not part of the card.
private struct CardHit: Shape {
    var top: CGFloat
    var lead: CGFloat = 0
    var trail: CGFloat
    var cardHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: lead, y: top, width: max(0, rect.width - lead - trail), height: cardHeight))
    }
}

/// Folded Duo with the hinge up. Sheets and alerts close so the home screen is all that's left.
private struct StandDisplayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var standDisplay: Bool {
        get { self[StandDisplayKey.self] }
        set { self[StandDisplayKey.self] = newValue }
    }
}

/// Hairline under 距離目標.
struct YearsProgressBar: View {
    var progress: Double

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { bar in
                    if progress > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 2,
                            topTrailingRadius: 2
                        )
                        .fill(LinearGradient(
                            colors: [Color.primary.opacity(0.35), Color.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: bar.size.width * min(1, max(0, progress)), height: 3)
                        .shadow(color: Color.primary.opacity(0.45), radius: 8)
                    }
                }
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
        .environment(Palette())
}

#Preview("偏離") {
    HomeView()
        .environment(Portfolio(items: [
            AssetItem(name: "活存", kind: .cash, amount: 2_000_000),
        ], targets: TargetWeights(original: 50, leverage: 30, cash: 20)))
        .environment(Palette())
}
