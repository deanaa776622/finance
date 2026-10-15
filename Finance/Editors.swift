import SwiftUI

struct TargetEditor: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hideAmounts") private var hideAmounts = false
    @FocusState private var field: Field?

    @State private var originalText = ""
    @State private var leverageText = ""
    @State private var cashText = ""

    private enum Field: Hashable { case original, leverage, cash }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 16) {
                                percentField("原型", text: $originalText, field: .original, kind: .original)
                                percentField("槓桿", text: $leverageText, field: .leverage, kind: .leverage)
                                percentField("現金", text: $cashText, field: .cash, kind: .cash)
                            }
                            centeredTrack(original: originalPercent, leverage: leveragePercent, onChange: setRatios)
                        }
                        if portfolio.allocableTotal > 0 {
                            HStack(spacing: 16) {
                                gapReadout("原型", kind: .original, percent: originalPercent)
                                gapReadout("槓桿", kind: .leverage, percent: leveragePercent)
                                gapReadout("現金", kind: .cash, percent: cashPercent)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                centeredTrack(
                                    original: portfolio.actualPercent(for: .original),
                                    leverage: portfolio.actualPercent(for: .leverage),
                                    tracksDrift: true,
                                    label: "目前比例",
                                    showsTitle: true
                                )
                                HStack(spacing: 16) {
                                    percentReadout("原型", percent: portfolio.actualPercent(for: .original), kind: .original)
                                    percentReadout("槓桿", percent: portfolio.actualPercent(for: .leverage), kind: .leverage)
                                    percentReadout("現金", percent: portfolio.actualPercent(for: .cash), kind: .cash)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if portfolio.allocableTotal <= 0 {
                        Text("新增資產後，會顯示再平衡差額")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .palettePanel(palette)
            .scrollEdgeFade()
            .navigationTitle("目標配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { commit(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { field = nil }
                }
            }
            .onAppear(perform: load)
        }
        .presentationBackground(palette.panel)
        .presentationDetents([.height(portfolio.allocableTotal > 0 ? 440 : 300)])
        .presentationDragIndicator(.visible)
    }

    private func centeredTrack(
        original: Double,
        leverage: Double,
        onChange: ((Double, Double) -> Void)? = nil,
        tracksDrift: Bool = false,
        label: String = "目標比例",
        showsTitle: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            trackGutter(showsTitle: showsTitle)
            AllocationGlowTrack(
                original: original,
                leverage: leverage,
                onChange: onChange,
                tracksDrift: tracksDrift,
                label: label
            )
            trackGutter(showsTitle: false)
        }
    }

    /// Same width on both sides, so the two bars match and sit in the center. Only the current bar shows the title.
    /// Leading inset is tighter than the word, so the bars use the spare margin without covering「目前」.
    private func trackGutter(showsTitle: Bool) -> some View {
        Text("目前")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.leading, -16)
            .opacity(showsTitle ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func percentField(_ title: String, text: Binding<String>, field: Field, kind: AssetKind) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($field, equals: field)
                    .frame(width: 36)
                    .accessibilityLabel(title)
                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(
                palette.glow(for: kind, factor: 0)
                    .readable(on: palette.panel, scheme: palette.colorScheme)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func gapReadout(_ title: String, kind: AssetKind, percent: Double) -> some View {
        let label = gapLabel(kind: kind, percent: percent)
        return Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(title)，\(label)")
    }

    private func percentReadout(_ title: String, percent: Double, kind: AssetKind) -> some View {
        let shown = NumberParse.displayPercent(percent.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            TextField("0", text: .constant(shown))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .allowsHitTesting(false)
                .frame(width: 36)
            Text("%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(
            palette.glow(for: kind, factor: portfolio.driftFactor(for: kind))
                .readable(on: palette.panel, scheme: palette.colorScheme)
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(shown)%")
    }

    private func gapLabel(kind: AssetKind, percent: Double) -> String {
        let gap = portfolio.rebalanceGap(for: kind, targetPercent: percent)
        let magnitude = gap < 0 ? -gap : gap
        if magnitude < 1 { return "剛好" }
        let amount = MoneyFormat.string(magnitude, hidden: hideAmounts)
        return gap > 0 ? "少 \(amount)" : "多 \(amount)"
    }

    private var originalPercent: Double { NumberParse.double(originalText) ?? 0 }
    private var leveragePercent: Double { NumberParse.double(leverageText) ?? 0 }
    private var cashPercent: Double { NumberParse.double(cashText) ?? 0 }

    private func setRatios(original: Double, leverage: Double) {
        let orig = min(100, max(0, original))
        let lev = min(100 - orig, max(0, leverage))
        originalText = NumberParse.displayPercent(orig)
        leverageText = NumberParse.displayPercent(lev)
        cashText = NumberParse.displayPercent(100 - orig - lev)
    }

    private func load() {
        originalText = NumberParse.displayPercent(portfolio.targets.original)
        leverageText = NumberParse.displayPercent(portfolio.targets.leverage)
        cashText = NumberParse.displayPercent(portfolio.targets.cash)
    }

    private func commit() {
        if let v = NumberParse.double(originalText) { portfolio.targets.original = v }
        if let v = NumberParse.double(leverageText) { portfolio.targets.leverage = v }
        if let v = NumberParse.double(cashText) { portfolio.targets.cash = v }
        portfolio.save()
    }
}

private struct AllocationGlowTrack: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    var original: Double
    var leverage: Double
    var onChange: ((Double, Double) -> Void)? = nil
    var tracksDrift = false
    var label: String = "目標比例"
    @State private var boundary = 0
    @State private var hapticTick = 0

    var body: some View {
        let orig = min(100, max(0, original))
        let lev = min(max(0, leverage), 100 - orig)
        let p1 = orig / 100
        let p2 = (orig + lev) / 100
        let originalColor = palette.glow(for: .original, factor: drift(.original))
        let leverageColor = palette.glow(for: .leverage, factor: drift(.leverage))
        let cashColor = palette.glow(for: .cash, factor: drift(.cash))
        GeometryReader { geo in
            let bar = Capsule()
                .fill(LinearGradient(stops: [
                    .init(color: originalColor, location: 0),
                    .init(color: originalColor, location: p1),
                    .init(color: leverageColor, location: p1),
                    .init(color: leverageColor, location: p2),
                    .init(color: cashColor, location: p2),
                    .init(color: cashColor, location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        if orig > 0, lev > 0, colorsMatch(originalColor, leverageColor) {
                            seam.offset(x: geo.size.width * p1)
                        }
                        if lev > 0, orig + lev < 100, colorsMatch(leverageColor, cashColor) {
                            seam.offset(x: geo.size.width * p2)
                        }
                    }
                }
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.primary.opacity(0.28), radius: 8)
            if onChange != nil {
                bar.highPriorityGesture(drag(width: geo.size.width))
            } else {
                bar
            }
        }
        .frame(height: 20)
        .sensoryFeedback(.selection, trigger: hapticTick)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("原型 \(Int(orig.rounded()))%，槓桿 \(Int(lev.rounded()))%，現金 \(Int((100 - orig - lev).rounded()))%")
    }

    private func drift(_ kind: AssetKind) -> Double {
        tracksDrift ? portfolio.driftFactor(for: kind) : 0
    }

    private var seam: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.9))
            .frame(width: 1)
    }

    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        let left = a.resolve(in: EnvironmentValues())
        let right = b.resolve(in: EnvironmentValues())
        let dr = left.red - right.red
        let dg = left.green - right.green
        let db = left.blue - right.blue
        return dr * dr + dg * dg + db * db < 0.004
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let percent = min(100, max(0, value.location.x / max(width, 1) * 100))
                var orig = min(100, max(0, original))
                var lev = min(100 - orig, max(0, leverage))
                let before = Int(orig.rounded()) * 100 + Int(lev.rounded())
                if boundary == 0 {
                    boundary = abs(percent - orig) <= abs(percent - (orig + lev)) ? 1 : 2
                }
                let snapped = (percent / 10).rounded() * 10
                if boundary == 1 {
                    let edge = orig + lev
                    orig = min(edge, max(0, snapped))
                    lev = edge - orig
                } else {
                    lev = min(100, max(orig, snapped)) - orig
                }
                let after = Int(orig.rounded()) * 100 + Int(lev.rounded())
                if after != before { hapticTick += 1 }
                onChange?(orig, lev)
            }
            .onEnded { _ in boundary = 0 }
    }
}
