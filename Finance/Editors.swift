import SwiftUI

struct TargetEditor: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.dismiss) private var dismiss
    @FocusState private var field: Field?

    @State private var totalText = ""
    @State private var originalText = ""
    @State private var leverageText = ""
    @State private var cashText = ""

    private enum Field: Hashable { case total, original, leverage, cash }

    var body: some View {
        NavigationStack {
            Form {
                Text("以長期配置為準。偏離約 10% 內可視為大致平衡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)

                Section {
                    if portfolio.savings != nil {
                        LabeledContent("目標總額") {
                            Text(portfolio.targetFromSavings.map(MoneyFormat.string) ?? "—")
                        }
                    } else {
                        HStack {
                            Text("目標總額")
                            Spacer()
                            TextField("選填", text: $totalText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($field, equals: .total)
                                .frame(minWidth: 120)
                        }
                    }
                } footer: {
                    Text(
                        portfolio.savings == nil
                            ? "光球依達成率長大。留空則以目前持有總額為基準。"
                            : "由儲蓄目標的年花費 ÷ 報酬率推算。"
                    )
                }

                Section("目標比例") {
                    AllocationGlowTrack(original: originalPercent, leverage: leveragePercent, onChange: setRatios)
                    percentRow("原型", text: $originalText, field: .original)
                    percentRow("槓桿", text: $leverageText, field: .leverage)
                    percentRow("現金", text: $cashText, field: .cash)
                }
            }
            .navigationTitle("目標配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { field = nil }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func percentRow(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("％", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($field, equals: field)
                .frame(width: 72)
            Text("%").foregroundStyle(.secondary)
        }
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
        totalText = portfolio.targetTotal.map(NumberParse.display) ?? ""
        originalText = NumberParse.displayPercent(portfolio.targets.original)
        leverageText = NumberParse.displayPercent(portfolio.targets.leverage)
        cashText = NumberParse.displayPercent(portfolio.targets.cash)
    }

    private func commit() {
        if portfolio.savings == nil {
            if totalText.trimmingCharacters(in: .whitespaces).isEmpty {
                portfolio.targetTotal = nil
            } else if let total = NumberParse.decimal(totalText), total > 0 {
                portfolio.targetTotal = total
            }
        }
        if let v = NumberParse.double(originalText) { portfolio.targets.original = v }
        if let v = NumberParse.double(leverageText) { portfolio.targets.leverage = v }
        if let v = NumberParse.double(cashText) { portfolio.targets.cash = v }
        portfolio.save()
    }
}

private struct AllocationGlowTrack: View {
    var original: Double
    var leverage: Double
    var onChange: (Double, Double) -> Void
    @State private var boundary = 0

    var body: some View {
        let orig = min(100, max(0, original))
        let lev = min(max(0, leverage), 100 - orig)
        let p1 = orig / 100
        let p2 = (orig + lev) / 100
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(stops: [
                    .init(color: AssetKind.original.glowColor, location: 0),
                    .init(color: AssetKind.original.glowColor, location: p1),
                    .init(color: AssetKind.leverage.glowColor, location: p1),
                    .init(color: AssetKind.leverage.glowColor, location: p2),
                    .init(color: AssetKind.cash.glowColor, location: p2),
                    .init(color: AssetKind.cash.glowColor, location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .white.opacity(0.28), radius: 8)
                .highPriorityGesture(drag(width: geo.size.width))
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("目標比例")
        .accessibilityValue("原型 \(Int(orig.rounded()))%，槓桿 \(Int(lev.rounded()))%，現金 \(Int((100 - orig - lev).rounded()))%")
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let percent = min(100, max(0, value.location.x / max(width, 1) * 100))
                var orig = min(100, max(0, original))
                var lev = min(100 - orig, max(0, leverage))
                if boundary == 0 {
                    boundary = abs(percent - orig) <= abs(percent - (orig + lev)) ? 1 : 2
                }
                let snapped = (percent / 10).rounded() * 10
                if boundary == 1 {
                    orig = min(100, max(0, snapped))
                    if orig + lev > 100 { lev = 100 - orig }
                } else {
                    lev = min(100, max(orig, snapped)) - orig
                }
                onChange(orig, lev)
            }
            .onEnded { _ in boundary = 0 }
    }
}
