import SwiftUI

struct HomeHero: View {
    let portfolio: Portfolio
    var position: CGFloat
    var settled: CGFloat
    /// 0 = 總淨值, 1 = 總曝險, including the in-flight drag.
    var lens: CGFloat
    var showsDots: Bool
    @Environment(Palette.self) private var palette
    @AppStorage("hideAmounts") private var hideAmounts = false

    private var reveal: CGFloat { abs(position) }
    private var settledReveal: CGFloat { abs(settled) }
    private var toSavings: CGFloat { max(settled, 0) }
    private var toAssets: CGFloat { max(-settled, 0) }

    var body: some View {
        ZStack {
            GlowBackground(orbs: GlowOrb.orbs(for: portfolio, palette: palette), compact: reveal)

            ZStack {
                statusCopy.opacity(1 - settledReveal)
                lensPager.opacity(toAssets)
                yearsCopy.opacity(toSavings)
            }
            VStack {
                Image(systemName: "chevron.compact.down")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - reveal)
                    .padding(.top, 8)
                    .safeAreaPadding(.top)
                    .accessibilityHidden(true)
                Spacer()
                Image(systemName: "chevron.compact.up")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .opacity(1 - reveal)
                    .padding(.bottom, 8)
                    .safeAreaPadding(.bottom)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            pageDots
                .padding(.bottom, 14)
                .opacity(showsDots ? 1 : 0)
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
                    .fill(.white.opacity(dotOn(index) ? 0.95 : 0.35))
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
