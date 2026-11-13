import Charts
import SwiftUI

/// The path from today's assets to the target. Press the line to read a year and the two amounts.
struct SavingsCurve: View {
    var outlook: SavingsOutlook
    @Environment(Palette.self) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var selectedYear: Double?
    @State private var markerX: CGFloat?
    @State private var yearLabelWidth: CGFloat = 0
    /// Years under the two fingers. The right year is compared with the left.
    @State private var fingerSpan: SavingsFingerSpan?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCurve, let years = outlook.years, years > 0,
               let target = outlook.targetAmount.map({ NSDecimalNumber(decimal: $0).doubleValue }) {
                curve(years: years, target: target)
                legend
            } else if !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(palette.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, selectedYear != nil || fingerSpan != nil else { return }
            withoutAnimation { clearPress() }
        }
    }

    private var showsCurve: Bool {
        outlook.points.count >= 2 && outlook.targetAmount != nil
    }

    private var caption: String {
        if outlook.needsPositiveRate { return "提領率需大於 0" }
        if outlook.alreadyReached { return "已達目標" }
        if outlook.retiresNow { return "現在補上差額，就到達目標" }
        if outlook.unreachable { return "這個計畫到不了目標" }
        return ""
    }

    private func curve(years: Double, target: Double) -> some View {
        let amounts = outlook.points.map(\.amount) + outlook.cashPoints.map(\.amount)
        let peak = max(target, amounts.max() ?? target)
        let floor = min(0, amounts.min() ?? 0)
        let top = max(peak * 1.08, floor + 1)
        return Chart {
            ForEach(outlook.points) { point in
                AreaMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "股市"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.ink.opacity(0.18).gradient)
                LineMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "股市"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(outlook.cashPoints, id: \.year) { point in
                LineMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "不投入"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.quietInk)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: 0 ... years)
        .chartYScale(domain: floor ... top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 120)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                ZStack {
                    if let fingerSpan {
                        scrubRule(fingerSpan.start, plot: plot, proxy: proxy)
                        scrubRule(fingerSpan.end, plot: plot, proxy: proxy)
                    } else if let selectedYear {
                        scrubRule(selectedYear, plot: plot, proxy: proxy)
                    }
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(touchGesture(years: years, proxy: proxy, geometry: geometry))
                }
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { yearLabel }
    }

    /// Sits in the padding above the plot and tracks the pressed year.
    private var yearLabel: some View {
        GeometryReader { row in
            Text(readout)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .fixedSize()
                .background {
                    GeometryReader { text in
                        Color.clear
                            .onChange(of: text.size.width, initial: true) { _, width in
                                if yearLabelWidth != width { yearLabelWidth = width }
                            }
                    }
                }
                .position(x: placedYearX(in: row.size.width), y: row.size.height / 2)
                .opacity(showsReadout ? 1 : 0)
        }
        .frame(height: 20)
        .allowsHitTesting(false)
    }

    private func placedYearX(in width: CGFloat) -> CGFloat {
        let half = yearLabelWidth / 2
        let x = fingerSpan == nil ? (markerX ?? width / 2) : width / 2
        return min(max(x, half), max(half, width - half))
    }

    /// One year follows the finger. Two fingers read as one range, centered.
    private var readout: String {
        if let span = fingerSpan {
            return "\(yearText(span.start)) - \(yearText(span.end))"
        }
        return selectedYear.map(yearText) ?? " "
    }

    private var showsReadout: Bool { selectedYear != nil || fingerSpan != nil }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow("投入股市", dashed: false, color: palette.ink, points: outlook.points, amountInk: palette.ink)
            legendRow("不投入股市", dashed: true, color: palette.quietInk, points: outlook.cashPoints, amountInk: palette.quietInk)
        }
        .font(.caption)
        .foregroundStyle(palette.quietInk)
    }

    private func legendRow(
        _ title: String,
        dashed: Bool,
        color: Color,
        points: [SavingsPoint],
        amountInk: Color
    ) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: dashed ? 3 : 0) {
                Capsule().fill(color).frame(width: dashed ? 6 : 16, height: 2)
                if dashed {
                    Capsule().fill(color).frame(width: 6, height: 2)
                }
            }
            Text(title)
            Spacer(minLength: 8)
            Text(legendValue(points))
                .monospacedDigit()
                .foregroundStyle(amountInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Idle shows the whole path. One finger shows the amount. Two fingers compare the right year with the left.
    private func legendValue(_ points: [SavingsPoint]) -> String {
        if fingerSpan != nil { return rangeValue(points) }
        if selectedYear != nil { return amountText(points) }
        return changeText(points)
    }

    private func amountText(_ points: [SavingsPoint]) -> String {
        guard let year = selectedYear, let amount = amount(on: points, at: year) else { return " " }
        return MoneyFormat.string(Decimal(amount), hidden: hideAmounts)
    }

    private func changeText(_ points: [SavingsPoint]) -> String {
        guard let first = points.first?.amount, let last = points.last?.amount, first != 0 else { return "—" }
        let change = (last - first) / abs(first) * 100
        return String(format: "%+.0f%%", change)
    }

    /// Right year against the left: percent, then the amount.
    private func rangeValue(_ points: [SavingsPoint]) -> String {
        guard let span = fingerSpan,
              let left = amount(on: points, at: span.start),
              let right = amount(on: points, at: span.end) else { return "—" }
        let delta = right - left
        let percent = left == 0 ? "—" : String(format: "%+.0f%%", delta / abs(left) * 100)
        return "\(percent) \(signedMoney(delta))"
    }

    private func signedMoney(_ value: Double) -> String {
        let text = MoneyFormat.string(Decimal(value), hidden: hideAmounts)
        guard !hideAmounts, value > 0 else { return text }
        return "+\(text)"
    }

    /// Linear between the yearly samples. Close enough to the drawn line for a finger readout.
    private func amount(on points: [SavingsPoint], at year: Double) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if year <= first.year { return first.amount }
        if year >= last.year { return last.amount }
        guard let upper = points.first(where: { $0.year >= year }),
              let lower = points.last(where: { $0.year <= year }),
              upper.year > lower.year else { return first.amount }
        let span = upper.year - lower.year
        let t = (year - lower.year) / span
        return lower.amount + (upper.amount - lower.amount) * t
    }

    private func scrubRule(_ year: Double, plot: CGRect, proxy: ChartProxy) -> some View {
        let x = proxy.position(forX: year).map { plot.minX + $0 }
        return TaperedRule()
            .fill(palette.quietInk.opacity(0.7))
            .frame(width: 1, height: plot.height)
            .position(x: x ?? 0, y: plot.midY)
            .opacity(x == nil ? 0 : 1)
            .allowsHitTesting(false)
    }

    /// One touch follows that finger. The second touch adds the other end in the same coordinates.
    private func touchGesture(years: Double, proxy: ChartProxy, geometry: GeometryProxy) -> ChartTouchGesture {
        ChartTouchGesture { xs in
            guard let plotFrame = proxy.plotFrame else { return }
            let plot = geometry[plotFrame]
            func placed(_ x: CGFloat) -> Double? {
                year(atPlotX: x - plot.origin.x, years: years, proxy: proxy)
            }
            withoutAnimation {
                if xs.count >= 2, let start = placed(xs[0]), let end = placed(xs[1]) {
                    selectedYear = nil
                    markerX = nil
                    fingerSpan = SavingsFingerSpan(start: start, end: end)
                } else if let year = placed(xs[0]) {
                    fingerSpan = nil
                    selectedYear = year
                    if let plotX = proxy.position(forX: year) {
                        markerX = plot.minX + plotX
                    }
                }
            }
        } onEnd: {
            withoutAnimation { clearPress() }
        }
    }

    private func year(atPlotX x: CGFloat, years: Double, proxy: ChartProxy) -> Double? {
        guard let year: Double = proxy.value(atX: x) else { return nil }
        return min(max(year, 0), years)
    }

    private func clearPress() {
        selectedYear = nil
        markerX = nil
        fingerSpan = nil
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func yearText(_ year: Double) -> String {
        let years = plainYears(year)
        return years == "0" ? "現在" : "\(years) 年"
    }

    private func plainYears(_ years: Double) -> String {
        let text = String(format: "%.1f", years)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

private struct SavingsFingerSpan {
    var start: Double
    var end: Double
}
