import SwiftUI

struct TargetEditor: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.dismiss) private var dismiss
    @FocusState private var field: Field?

    @State private var originalText = ""
    @State private var leverageText = ""
    @State private var cashText = ""

    private enum Field: Hashable { case original, leverage, cash }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        percentField("原型", text: $originalText, field: .original, kind: .original)
                        percentField("槓桿", text: $leverageText, field: .leverage, kind: .leverage)
                        percentField("現金", text: $cashText, field: .cash, kind: .cash)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    AllocationGlowTrack(original: originalPercent, leverage: leveragePercent, onChange: setRatios)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("目標配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("取消") { dismiss() }
                    Spacer()
                    Button("儲存") { commit(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { field = nil }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.height(300)])
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
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
            .foregroundStyle(portfolio.glowColor(for: kind))
        }
        .frame(maxWidth: .infinity)
    }

    private var originalPercent: Double { NumberParse.double(originalText) ?? 0 }
    private var leveragePercent: Double { NumberParse.double(leverageText) ?? 0 }

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
    var original: Double
    var leverage: Double
    var onChange: (Double, Double) -> Void
    @State private var boundary = 0
    @State private var hapticTick = 0

    var body: some View {
        let orig = min(100, max(0, original))
        let lev = min(max(0, leverage), 100 - orig)
        let p1 = orig / 100
        let p2 = (orig + lev) / 100
        let originalColor = portfolio.glowColor(for: .original)
        let leverageColor = portfolio.glowColor(for: .leverage)
        let cashColor = portfolio.glowColor(for: .cash)
        GeometryReader { geo in
            Capsule()
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
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .white.opacity(0.28), radius: 8)
                .highPriorityGesture(drag(width: geo.size.width))
        }
        .frame(height: 20)
        .sensoryFeedback(.selection, trigger: hapticTick)
        .accessibilityElement()
        .accessibilityLabel("目標比例")
        .accessibilityValue("原型 \(Int(orig.rounded()))%，槓桿 \(Int(lev.rounded()))%，現金 \(Int((100 - orig - lev).rounded()))%")
    }

    private var seam: some View {
        Rectangle()
            .fill(.white.opacity(0.9))
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
                onChange(orig, lev)
            }
            .onEnded { _ in boundary = 0 }
    }
}
