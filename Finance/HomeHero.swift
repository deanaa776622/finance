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
                    .opacity(1 - reveal)
                    .padding(.top, downChevronTop)
                    .accessibilityHidden(true)
                Spacer()
                Image(systemName: "chevron.compact.up")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - reveal)
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
                metric(title: "總淨值", value: portfolio.netWorth, showsMix: false)
                    .frame(width: geo.size.width, height: geo.size.height)
                metric(title: "總曝險", value: portfolio.exposure, showsMix: true)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -geo.size.width * lens)
        }
    }

    private func metric(title: String, value: Decimal, showsMix: Bool) -> some View {
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
            if showsMix {
                Text(portfolio.allocationMixLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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

/// Reads the fold. Nil on a normal iPhone.
struct UnfoldedHinge: UIViewRepresentable {
    @Binding var isUnfolded: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        guard #available(iOS 27.1, *) else { return view }
        view.addInteraction(UIHingeInteraction { _, update in
            let open = update.hinge?.status == .fullyOpen || update.hinge?.status == .partiallyOpen
            DispatchQueue.main.async {
                let binding = context.coordinator.isUnfolded
                if binding.wrappedValue != open { binding.wrappedValue = open }
            }
        })
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isUnfolded = $isUnfolded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isUnfolded: $isUnfolded)
    }

    final class Coordinator {
        var isUnfolded: Binding<Bool>
        init(isUnfolded: Binding<Bool>) { self.isUnfolded = isUnfolded }
    }
}
