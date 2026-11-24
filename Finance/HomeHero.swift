import SwiftUI
import UIKit

struct HomeHero: View {
    let portfolio: Portfolio
    var position: CGFloat
    var settled: CGFloat
    /// 0 = 總淨值, 1 = 總曝險, including the in-flight drag.
    var lens: CGFloat
    var showsDots: Bool
    var screen: CGSize
    var safeTop: CGFloat
    var safeBottom: CGFloat
    var safeLeft: CGFloat = 0
    var safeRight: CGFloat = 0
    /// Window is taller than wide: the screen opens top to bottom.
    var opensVertically = false
    /// Unfolded Duo. A normal iPhone has no hinge, so portrait stays under the island.
    var unfolded = false
    /// Folded Duo, hinge up. Chevrons stay off; the screen is only for looking.
    var exhibit = false
    @Environment(Palette.self) private var palette
    @AppStorage("hideAmounts") private var hideAmounts = false

    /// Same distance from the screen edge as the up chevron.
    private var edgeInset: CGFloat { safeBottom + 8 }

    /// 直立且展開時，上方安全區是空的，下箭頭跟上箭頭同一個邊緣距離。
    /// 一般 iPhone 直立有靈動島，維持在安全區下方。橫放有側欄時再往下對齊。
    private var downChevronTop: CGFloat {
        if opensVertically, unfolded {
            return edgeInset
        }
        if safeLeft > 20 || safeRight > 20 {
            return max(safeTop, edgeInset)
        }
        return safeTop + 8
    }

    private var reveal: CGFloat { abs(position) }
    private var settledReveal: CGFloat { abs(settled) }
    private var toSavings: CGFloat { max(settled, 0) }
    private var toAssets: CGFloat { max(-settled, 0) }

    var body: some View {
        ZStack {
            GlowBackground(orbs: GlowOrb.orbs(for: portfolio, palette: palette), screen: screen)

            ZStack {
                statusCopy.opacity(1 - settledReveal)
                lensPager.opacity(toAssets)
                GoalDistanceCopy(portfolio: portfolio).opacity(toSavings)
            }
            VStack {
                Image(systemName: "chevron.compact.down")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(exhibit ? 0 : 1 - reveal)
                    .padding(.top, downChevronTop)
                    .accessibilityHidden(true)
                Spacer()
                Image(systemName: "chevron.compact.up")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(exhibit ? 0 : 1 - reveal)
                    .padding(.bottom, edgeInset)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            pageDots
                .padding(.bottom, 14)
                .opacity(showsDots && position < -0.5 ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var lensPager: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                metric(title: "總淨值", value: portfolio.netWorth)
                    .frame(width: geo.size.width, height: geo.size.height)
                metric(title: "總曝險", value: portfolio.exposure)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -geo.size.width * lens)
        }
    }

    private func metric(title: String, value: Decimal) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
            Text(MoneyFormat.string(value, hidden: hideAmounts))
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(dotOn(index) ? 0.95 : 0.35))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotOn(index) ? 1.15 : 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func dotOn(_ index: Int) -> Bool {
        (lens < 0.5 ? 0 : 1) == index
    }

    private var statusCopy: some View {
        let tracking: CGFloat = 6
        return VStack(spacing: 14) {
            Text(portfolio.statusTitle)
                .font(.title3.weight(.semibold))
                .tracking(tracking)
                // The last glyph keeps a tracking gap. Without this the title sits left of the subtitle.
                .padding(.trailing, -tracking)
            Text(portfolio.homeSubtitle())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48 - 24 * settledReveal)
        }
    }

}

/// Fold, plus the window after rotation commits. A geometry callback reads the old orientation.
struct UnfoldedHinge: UIViewControllerRepresentable {
    @Binding var isUnfolded: Bool
    @Binding var isFolded: Bool
    var onChrome: (CGSize, UIEdgeInsets) -> Void
    var onExhibit: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onChrome = onChrome
        controller.onExhibit = onExhibit
        controller.fold = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onChrome = onChrome
        controller.onExhibit = onExhibit
        context.coordinator.isUnfolded = $isUnfolded
        context.coordinator.isFolded = $isFolded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isUnfolded: $isUnfolded, isFolded: $isFolded)
    }

    final class Coordinator {
        var isUnfolded: Binding<Bool>
        var isFolded: Binding<Bool>
        init(isUnfolded: Binding<Bool>, isFolded: Binding<Bool>) {
            self.isUnfolded = isUnfolded
            self.isFolded = isFolded
        }
    }

    final class Controller: UIViewController {
        var onChrome: ((CGSize, UIEdgeInsets) -> Void)?
        var onExhibit: ((Bool) -> Void)?
        var fold: Coordinator?
        private var boundsToken: NSKeyValueObservation?
        private var turnObserver: NSObjectProtocol?
        private var applied: (CGSize, UIEdgeInsets)?
        /// Hinge reports closed. A phone with no hinge stays false.
        private var folded = false
        private var exhibit = false
        private var watchingTurns = false

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { InterfaceLock.mask }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            guard #available(iOS 27.1, *), let fold else { return }
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                let status = update.hinge?.status
                let open = status == .fullyOpen || status == .partiallyOpen
                DispatchQueue.main.async {
                    guard let self else { return }
                    let closed = status == .closed
                    self.folded = closed
                    if fold.isUnfolded.wrappedValue != open { fold.isUnfolded.wrappedValue = open }
                    if fold.isFolded.wrappedValue != closed { fold.isFolded.wrappedValue = closed }
                    self.syncExhibit()
                }
            })
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !watchingTurns {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                watchingTurns = true
            }
            if turnObserver == nil {
                turnObserver = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.syncExhibit()
                }
            }
            watchWindow()
            publish()
            syncExhibit()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if boundsToken == nil { watchWindow() }
            // Skip when this pass still shows the orientation we already applied.
            guard let window = view.window else { return }
            let size = window.bounds.size
            let insets = window.safeAreaInsets
            guard applied?.0 != size || applied?.1 != insets else { return }
            publish()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            publish()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { _ in
                self.publish()
                DispatchQueue.main.async { self.publish() }
            }
        }

        deinit {
            boundsToken?.invalidate()
            if let turnObserver { NotificationCenter.default.removeObserver(turnObserver) }
            if watchingTurns {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }

        /// Clockwise 90° from portrait: power button down, hinge up.
        /// That device orientation is landscapeRight; the interface that keeps the hinge at the top is landscapeLeft.
        private func syncExhibit() {
            let orientation = UIDevice.current.orientation
            guard orientation != .faceUp, orientation != .faceDown, orientation != .unknown else { return }
            let next = folded && orientation == .landscapeRight
            guard next != exhibit else { return }
            exhibit = next
            setNeedsUpdateOfSupportedInterfaceOrientations()
            onExhibit?(next)
            InterfaceLock.apply(next ? .landscapeLeft : .portrait)
        }

        private func watchWindow() {
            guard boundsToken == nil, let window = view.window else { return }
            boundsToken = window.layer.observe(\.bounds) { [weak self] _, _ in
                self?.publish()
            }
        }

        /// Next turn: bounds KVO can run before the safe area matches the new size.
        private func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.view.window else { return }
                let size = window.bounds.size
                let insets = window.safeAreaInsets
                guard size.width > 1, size.height > 1 else { return }
                guard self.applied?.0 != size || self.applied?.1 != insets else { return }
                self.applied = (size, insets)
                self.onChrome?(size, insets)
            }
        }
    }
}
