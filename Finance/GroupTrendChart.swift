import Charts
import SwiftUI

/// Monthly lines for the groups on screen. Press to read a month.
struct GroupTrendChart: View, Equatable {
    var buckets: [AssetBucket]
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var selected: String?
    @State private var markerX: CGFloat?
    @State private var monthLabelWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
                .frame(height: 112)
                .padding(.top, 20)
                .overlay(alignment: .top) { monthLabel }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                marks(line)
            }
            if let selected {
                RuleMark(x: .value("月", selected))
                    .foregroundStyle(palette.quietInk.opacity(0.7))
            }
            RuleMark(y: .value("金額", 0))
                .foregroundStyle(palette.quietInk.opacity(0.35))
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .transaction { $0.animation = nil }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(scrub(proxy: proxy, geometry: geometry))
            }
        }
    }

    /// Includes zero so the baseline stays visible when every group is positive.
    private var yDomain: ClosedRange<Double> {
        let plots = series.flatMap(\.points).map(\.plot)
        let low = min(0, plots.min() ?? 0)
        let high = max(0, plots.max() ?? 0)
        let pad = max((high - low) * 0.08, 1)
        return (low - pad)...(high + pad)
    }

    /// Horizontal only, and shared with the list, so a vertical flick can still scroll.
    private func scrub(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                let travel = drag.translation
                guard abs(travel.width) > abs(travel.height) else { return }
                guard let plotFrame = proxy.plotFrame else { return }
                let plot = geometry[plotFrame]
                let x = drag.location.x - plot.origin.x
                guard let month: String = proxy.value(atX: x) else { return }
                if month != selected { selected = month }
                if let plotX = proxy.position(forX: month) {
                    let next = plot.minX + plotX
                    if markerX != next { markerX = next }
                }
            }
        .onEnded { _ in
            selected = nil
            markerX = nil
        }
    }

    static func == (lhs: GroupTrendChart, rhs: GroupTrendChart) -> Bool {
        lhs.buckets == rhs.buckets
    }

    @ChartContentBuilder
    private func marks(_ line: TrendLine) -> some ChartContent {
        if line.points.count >= 2 {
            ForEach(line.points) { point in
                if series.count == 1 {
                    AreaMark(x: .value("月", point.month), y: .value("金額", point.plot))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(line.color.opacity(0.16).gradient)
                }
                LineMark(
                    x: .value("月", point.month),
                    y: .value("金額", point.plot),
                    series: .value("群組", line.id)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        } else if let point = line.points.first {
            PointMark(x: .value("月", point.month), y: .value("金額", point.plot))
                .foregroundStyle(line.color)
        }
    }

    private var monthLabel: some View {
        GeometryReader { row in
            Text(selected.map(spokenMonth) ?? " ")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .fixedSize()
                .background {
                    GeometryReader { text in
                        Color.clear
                            .onChange(of: text.size.width, initial: true) { _, width in
                                if monthLabelWidth != width { monthLabelWidth = width }
                            }
                    }
                }
                .position(x: placedMonthX(in: row.size.width), y: row.size.height / 2)
                .opacity(selected == nil ? 0 : 1)
        }
        .frame(height: 20)
        .allowsHitTesting(false)
    }

    private func placedMonthX(in width: CGFloat) -> CGFloat {
        let half = monthLabelWidth / 2
        let x = markerX ?? width / 2
        return min(max(x, half), max(half, width - half))
    }

    private var legend: some View {
        let lines = series
        return Group {
            if isFiveKindLegend(lines) {
                HStack(alignment: .top, spacing: 12) {
                    legendColumn(lines, ids: ["original", "leverage", "cash"])
                    legendColumn(lines, ids: ["realEstate", "debt"])
                }
            } else {
                legendColumn(lines, ids: lines.map(\.id))
            }
        }
        .font(.caption)
        .foregroundStyle(palette.quietInk)
    }

    /// 原型、槓桿、現金在左半；實體、負債在右半。
    private func isFiveKindLegend(_ lines: [TrendLine]) -> Bool {
        Set(lines.map(\.id)) == ["original", "leverage", "cash", "realEstate", "debt"]
    }

    private func legendColumn(_ lines: [TrendLine], ids: [String]) -> some View {
        let shown = ids.compactMap { id in lines.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { line in
                legendRow(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ line: TrendLine) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(line.color).frame(width: 16, height: 2)
            Text(line.title).lineLimit(1)
            Spacer(minLength: 4)
            Text(amountText(line))
                .monospacedDigit()
                .foregroundStyle(line.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(selected == nil ? 0 : 1)
        }
    }

    private func amountText(_ line: TrendLine) -> String {
        guard let month = selected,
              let amount = line.points.first(where: { $0.month == month })?.amount else { return " " }
        return MoneyFormat.string(amount, hidden: hideAmounts)
    }

    private var series: [TrendLine] {
        buckets.map { bucket in
            TrendLine(
                id: bucket.id,
                title: bucket.title,
                color: color(for: bucket),
                points: AssetHistory.months(
                    kinds: bucket.kinds,
                    items: portfolio.items,
                    histories: portfolio.histories,
                    rateMonths: portfolio.rateMonths
                )
            )
        }
    }

    private func color(for bucket: AssetBucket) -> Color {
        guard bucket.kinds.count == 1, let kind = bucket.kinds.first else { return palette.ink }
        return palette.glow(for: kind, factor: 0)
    }

    private var months: [String] {
        Array(Set(series.flatMap { $0.points.map(\.month) })).sorted()
    }

    private func spokenMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2 else { return month }
        return "\(parts[0])年\(Int(parts[1]) ?? 0)月"
    }

    private var accessibilityText: String {
        let month = selected ?? months.last
        let bits = series.map { line -> String in
            let amount = line.points.first { $0.month == month }?.amount ?? 0
            return "\(line.title) \(MoneyFormat.string(amount, hidden: hideAmounts))"
        }
        return "每月趨勢，\(month.map(spokenMonth) ?? "")，" + bits.joined(separator: "，")
    }
}

private struct TrendLine: Identifiable {
    var id: String
    var title: String
    var color: Color
    var points: [GroupMonthPoint]
}
