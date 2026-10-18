import Charts
import SwiftUI

/// The path from today's assets to the target. Press the line to read a year and the two amounts.
struct SavingsCurve: View {
    var outlook: SavingsOutlook
    @Environment(Palette.self) private var palette
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var selectedYear: Double?
    @State private var markerX: CGFloat?
    @State private var yearLabelWidth: CGFloat = 0

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
            RuleMark(y: .value("目標", target))
                .foregroundStyle(palette.quietInk.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(outlook.points) { point in
                AreaMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "股市"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.ink.opacity(0.18).gradient)
                LineMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "股市"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(outlook.cashPoints, id: \.year) { point in
                LineMark(x: .value("年", point.year), y: .value("資產", point.amount), series: .value("線", "不投入"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(palette.quietInk)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let selectedYear {
                RuleMark(x: .value("年", selectedYear))
                    .foregroundStyle(palette.quietInk.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
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
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plot = geometry[plotFrame]
                                let x = drag.location.x - plot.origin.x
                                guard let year: Double = proxy.value(atX: x) else { return }
                                let clamped = min(max(year, 0), years)
                                selectedYear = clamped
                                if let plotX = proxy.position(forX: clamped) {
                                    markerX = plot.minX + plotX
                                }
                            }
                            .onEnded { _ in
                                selectedYear = nil
                                markerX = nil
                            }
                    )
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { yearLabel }
    }

    /// Sits in the padding above the plot and tracks the pressed year.
    private var yearLabel: some View {
        GeometryReader { row in
            Text(selectedYear.map(yearText) ?? " ")
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
                .opacity(selectedYear == nil ? 0 : 1)
        }
        .frame(height: 20)
        .allowsHitTesting(false)
    }

    private func placedYearX(in width: CGFloat) -> CGFloat {
        let half = yearLabelWidth / 2
        let x = markerX ?? width / 2
        return min(max(x, half), max(half, width - half))
    }

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
            Text(amountText(points))
                .monospacedDigit()
                .foregroundStyle(amountInk)
                .opacity(selectedYear == nil ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func amountText(_ points: [SavingsPoint]) -> String {
        guard let year = selectedYear, let amount = amount(on: points, at: year) else { return " " }
        return MoneyFormat.string(Decimal(amount), hidden: hideAmounts)
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

    private func yearText(_ year: Double) -> String {
        let years = plainYears(year)
        return years == "0" ? "現在" : "\(years) 年"
    }

    private func plainYears(_ years: Double) -> String {
        let text = String(format: "%.1f", years)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
