import Charts
import SwiftUI

/// Monthly lines for the groups on screen. Press to read a month.
struct GroupTrendChart: View, Equatable {
    /// Plot, the room above it, the gap, and three legend rows. The exposure page's target editor uses this band.
    private static let legendHeight: CGFloat = 84
    static let bandHeight: CGFloat = 112 + 36 + 8 + legendHeight
    var buckets: [AssetBucket]
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var selected: String?
    @State private var markerX: CGFloat?
    @State private var monthLabelWidth: CGFloat = 0
    /// Screen positions, 0 = bottom of the plot and 1 = top. Animating these moves the strokes.
    @State private var drawn: [DrawnLine] = []
    @State private var zeroUnit: Double = 0
    @State private var morphToken = UUID()
    @State private var span: ChartSpan = .year
    @State private var showCustom = false
    @State private var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    /// Legend ids drawn without a swatch. Those lines stay off the chart.
    @State private var hiddenIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                chart
                    .frame(height: 112)
                    .padding(.top, 36)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
                rangeBand
            }
            legend
                .frame(height: Self.legendHeight, alignment: .top)
        }
        .frame(height: Self.bandHeight, alignment: .top)
        .onChange(of: plotKey, initial: true) { _, _ in
            let placed = layout()
            morph(to: placed.lines, zero: placed.zero)
        }
        .sheet(isPresented: $showCustom) {
            ChartSpanEditor(start: $customStart, end: $customEnd)
        }
    }

    /// The month row. Scrubbing hides the ranges and shows the month under the finger.
    private var rangeBand: some View {
        ZStack {
            ChartSpanPicker(span: $span) { showCustom = true }
                .opacity(selected == nil ? 1 : 0)
                .allowsHitTesting(selected == nil)
            monthLabel
        }
    }

    private var chart: some View {
        Chart {
            ForEach(visibleLines) { line in
                marks(line)
            }
            if let selected {
                RuleMark(x: .value("月", selected))
                    .foregroundStyle(palette.quietInk.opacity(0.7))
            }
            if months.isEmpty == false {
                RuleMark(y: .value("金額", visibleZero))
                    .foregroundStyle(palette.quietInk.opacity(0.35))
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(scrub(proxy: proxy, geometry: geometry))
            }
        }
    }

    private var visibleLines: [DrawnLine] {
        drawn.isEmpty ? layout().lines : drawn
    }

    private var visibleZero: Double {
        drawn.isEmpty ? layout().zero : zeroUnit
    }

    /// Puts every line in the same screen space, so a later change can move a stroke from where it was.
    private func layout() -> (lines: [DrawnLine], zero: Double) {
        let rows = series
        let plots = rows.flatMap { $0.points.map(\.plot) }
        let low = min(0, plots.min() ?? 0)
        let high = max(0, plots.max() ?? 0)
        let pad = max((high - low) * 0.08, 1)
        let floor = low - pad
        let span = max((high + pad) - floor, 0.0001)
        func place(_ value: Double) -> Double { (value - floor) / span }
        let lines = rows.map { line in
            DrawnLine(
                id: line.id,
                color: line.color,
                points: line.points.map { DrawnPoint(month: $0.month, unit: place($0.plot)) }
            )
        }
        return (lines, place(0))
    }

    /// Shared lines travel to their new height. Lines that leave settle on the baseline; lines that arrive leave it.
    private func morph(to next: [DrawnLine], zero: Double) {
        guard !drawn.isEmpty, !reduceMotion else {
            drawn = next
            zeroUnit = zero
            return
        }
        let nextIDs = Set(next.map(\.id))
        var start: [DrawnLine] = []
        for line in next {
            if var old = drawn.first(where: { $0.id == line.id }) {
                old.color = line.color
                start.append(old)
            } else {
                start.append(line.flat(zeroUnit))
            }
        }
        for line in drawn where !nextIDs.contains(line.id) {
            start.append(line)
        }
        var end = next
        for line in start where !nextIDs.contains(line.id) {
            end.append(line.flat(zero))
        }
        drawn = start
        let token = UUID()
        morphToken = token
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.48)) {
                drawn = end
                zeroUnit = zero
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                guard morphToken == token else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drawn = next
                    zeroUnit = zero
                }
            }
        }
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
                withoutAnimation {
                    if month != selected { selected = month }
                    if let plotX = proxy.position(forX: month) {
                        let next = plot.minX + plotX
                        if markerX != next { markerX = next }
                    }
                }
            }
        .onEnded { _ in
            withoutAnimation {
                selected = nil
                markerX = nil
            }
        }
    }

    /// Finger scrub stays put. Page changes move the strokes themselves.
    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    static func == (lhs: GroupTrendChart, rhs: GroupTrendChart) -> Bool {
        lhs.buckets == rhs.buckets
    }

    @ChartContentBuilder
    private func marks(_ line: DrawnLine) -> some ChartContent {
        if line.points.count >= 2 {
            ForEach(line.points) { point in
                LineMark(
                    x: .value("月", point.month),
                    y: .value("位置", point.unit),
                    series: .value("群組", line.id)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        } else if let point = line.points.first {
            PointMark(x: .value("月", point.month), y: .value("位置", point.unit))
                .foregroundStyle(.clear)
                .annotation(position: .overlay) { lineSwatch(line.color) }
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
        .frame(height: 32)
        .allowsHitTesting(false)
    }

    private func placedMonthX(in width: CGFloat) -> CGFloat {
        let half = monthLabelWidth / 2
        let x = markerX ?? width / 2
        return min(max(x, half), max(half, width - half))
    }

    private var legend: some View {
        let lines = windowed
        let leftCount = (lines.count + 1) / 2
        return ZStack(alignment: .topLeading) {
            legendColumn(slotLines)
                .hidden()
                .accessibilityHidden(true)
            if lines.count < 2 {
                legendColumn(lines)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    legendColumn(Array(lines.prefix(leftCount)))
                    legendColumn(Array(lines.suffix(lines.count - leftCount)))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(palette.quietInk)
    }

    /// Tallest legend is three rows. Fewer groups keep that height so the chart does not jump.
    private var slotLines: [TrendLine] {
        (0..<3).map { TrendLine(id: "slot-\($0)", title: " ", color: .clear, points: []) }
    }

    private func legendColumn(_ lines: [TrendLine]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                legendRow(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineSwatch(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 16, height: 2)
    }

    private func legendRow(_ line: TrendLine) -> some View {
        let shown = !hiddenIDs.contains(line.id)
        let ink = shown ? chipInk(line.color) : palette.quietInk
        return Button {
            var next = hiddenIDs
            if shown { next.insert(line.id) } else { next.remove(line.id) }
            hiddenIDs = next
        } label: {
            HStack(spacing: 6) {
                lineSwatch(shown ? ink : line.color)
                Text(line.title).lineLimit(1)
                Spacer(minLength: 4)
                Text(selected == nil ? changeText(line) : amountText(line))
                    .monospacedDigit()
                    .foregroundStyle(shown ? ink : line.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { if shown { Capsule().fill(line.color) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.title)
        .accessibilityValue(shown ? "顯示趨勢線" : "不顯示趨勢線")
        .accessibilityHint("點一下切換")
    }

    /// Black or white, so the title stays readable on the swatch.
    private func chipInk(_ color: Color) -> Color {
        color.relativeLuminance(scheme: palette.colorScheme) > 0.179 ? .black : .white
    }

    /// Change across the months on screen: last value against the first.
    private func changeText(_ line: TrendLine) -> String {
        guard let first = line.points.first, let last = line.points.last, first.month != last.month else { return "—" }
        let start = first.plot
        guard start != 0 else { return "—" }
        let change = (last.plot - start) / abs(start) * 100
        return String(format: "%+.0f%%", change)
    }

    private func amountText(_ line: TrendLine) -> String {
        guard let month = selected,
              let amount = line.points.first(where: { $0.month == month })?.amount else { return " " }
        return MoneyFormat.string(amount, hidden: hideAmounts)
    }

    private var fullSeries: [TrendLine] {
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

    /// Every group in the selected span, including ones tapped off the chart.
    private var windowed: [TrendLine] {
        let rows = fullSeries
        let anchor = rows.flatMap { $0.points.map(\.month) }.max()
        return rows.map { line in
            var copy = line
            copy.points = line.points.filter { shows($0.month, anchor: anchor) }
            return copy
        }
    }

    /// Lines with a legend swatch. Hidden legends leave this set, so the stroke morphs away.
    private var series: [TrendLine] {
        windowed.filter { !hiddenIDs.contains($0.id) }
    }

    /// 今年 is this calendar year, 年 the twelve months ending at the latest record, 全部 every recorded month.
    private func shows(_ month: String, anchor: String?) -> Bool {
        switch span {
        case .thisYear:
            let year = Calendar.current.component(.year, from: Date())
            return month.hasPrefix(String(format: "%04d", year))
        case .year:
            guard let anchor, let start = self.month(byAdding: -11, to: anchor) else { return false }
            return month >= start && month <= anchor
        case .all:
            return true
        case .custom:
            let start = monthKey(customStart)
            let end = monthKey(customEnd)
            return month >= min(start, end) && month <= max(start, end)
        }
    }

    private func month(byAdding delta: Int, to month: String) -> String? {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let monthIndex = Int(parts[1]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = monthIndex
        comps.day = 1
        guard let date = Calendar.current.date(from: comps),
              let shifted = Calendar.current.date(byAdding: .month, value: delta, to: date) else { return nil }
        return monthKey(shifted)
    }

    private func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 1)
    }

    private func color(for bucket: AssetBucket) -> Color {
        guard bucket.kinds.count == 1, let kind = bucket.kinds.first else { return palette.ink }
        return palette.glow(for: kind, factor: 0)
    }

    private var plotKey: String {
        series.map { line in
            let tail = line.points.map { "\($0.month):\($0.plot)" }.joined(separator: ",")
            return "\(line.id)#\(line.title)#\(tail)"
        }.joined(separator: "|")
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
            if selected == nil { return "\(line.title) \(changeText(line))" }
            let amount = line.points.first { $0.month == month }?.amount ?? 0
            return "\(line.title) \(MoneyFormat.string(amount, hidden: hideAmounts))"
        }
        return "\(span.title)，\(month.map(spokenMonth) ?? "")，" + bits.joined(separator: "，")
    }
}

private struct TrendLine: Identifiable {
    var id: String
    var title: String
    var color: Color
    var points: [GroupMonthPoint]
}

/// One stroke in plot space. `unit` is where it sits between the bottom and top of the chart.
private struct DrawnLine: Identifiable {
    var id: String
    var color: Color
    var points: [DrawnPoint]

    func flat(_ unit: Double) -> DrawnLine {
        var copy = self
        for index in copy.points.indices { copy.points[index].unit = unit }
        return copy
    }
}

private struct DrawnPoint: Identifiable {
    var month: String
    var unit: Double
    var id: String { month }
}
