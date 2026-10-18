import Charts
import SwiftUI

/// The path from today's assets to the target. No axes; the sentence and the two ends carry the meaning.
struct SavingsCurve: View {
    var outlook: SavingsOutlook
    var nowText: String
    var targetText: String
    @Environment(Palette.self) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(palette.ink)
            if showsCurve, let years = outlook.years, years > 0,
               let target = outlook.targetAmount.map({ NSDecimalNumber(decimal: $0).doubleValue }) {
                curve(years: years, target: target)
                legend
                anchors(years: years)
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
        guard let years = outlook.years else { return "預估資產" }
        return "預估資產，約 \(plainYears(years)) 年到達目標"
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
        }
        .chartXScale(domain: 0 ... years)
        .chartYScale(domain: floor ... top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 120)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("投入股市", dashed: false, color: palette.ink)
            legendItem("不投入股市", dashed: true, color: palette.quietInk)
        }
        .font(.caption)
        .foregroundStyle(palette.quietInk)
    }

    private func legendItem(_ title: String, dashed: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: dashed ? 3 : 0) {
                Capsule().fill(color).frame(width: dashed ? 6 : 16, height: 2)
                if dashed {
                    Capsule().fill(color).frame(width: 6, height: 2)
                }
            }
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    private func anchors(years: Double) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("現在")
                Text(nowText).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(plainYears(years) + " 年").monospacedDigit()
                Text(targetText).monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(palette.quietInk)
    }

    private func plainYears(_ years: Double) -> String {
        let text = String(format: "%.1f", years)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
