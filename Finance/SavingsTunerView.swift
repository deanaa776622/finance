import Charts
import SwiftUI

struct SavingsTunerView: View {
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @FocusState private var field: Field?
    @State private var costText = ""
    @State private var rateText = ""
    @State private var pmtText = ""
    @State private var baseline: SavingsPlan?

    private enum Field: Hashable { case cost, rate, pmt }

    var body: some View {
        Form {
            Section {
                moneyRow("年花費", text: $costText, field: .cost)
                HStack {
                    Text("年報酬率")
                    Spacer()
                    TextField("％", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($field, equals: .rate)
                        .frame(width: 72)
                    Text("%").foregroundStyle(.secondary)
                }
                moneyRow("月投資額", text: $pmtText, field: .pmt)
            }

            if let points = draftOutlook?.points, !points.isEmpty {
                Section {
                    Chart(points) { p in
                        AreaMark(x: .value("年", p.year), y: .value("資產", p.amount))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.white.opacity(0.18).gradient)
                        LineMark(x: .value("年", p.year), y: .value("資產", p.amount))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartLegend(.hidden)
                    .frame(height: 120)
                    .accessibilityLabel("預估資產曲線")
                }
            }

            Section {
                LabeledContent("目前資產", value: MoneyFormat.string(portfolio.allocableTotal, hidden: hideAmounts))
                LabeledContent("目標金額") {
                    Text(draftOutlook?.targetAmount.map(MoneyFormat.string) ?? "報酬率需大於 0")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                Color.black
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { field = nil }
            }
        }
        .onAppear(perform: load)
        .onChange(of: costText) { _, _ in persist() }
        .onChange(of: rateText) { _, _ in persist() }
        .onChange(of: pmtText) { _, _ in persist() }
    }

    private var draft: SavingsPlan? {
        guard let cost = NumberParse.decimal(costText), cost >= 0,
              let rate = NumberParse.double(rateText), rate >= 0, rate <= 100,
              let pmt = NumberParse.decimal(pmtText), pmt >= 0
        else { return nil }
        return SavingsPlan(annualCost: cost, annualRatePercent: rate, monthlyContribution: pmt)
    }

    private var draftOutlook: SavingsOutlook? {
        draft.map { SavingsMath.outlook(plan: $0, presentValue: portfolio.allocableTotal) }
    }

    private func moneyRow(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: grouped(text))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($field, equals: field)
                .frame(minWidth: 120)
        }
    }

    private func grouped(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = NumberParse.grouped($0) }
        )
    }

    private func load() {
        let plan = portfolio.savings ?? .prototype
        costText = NumberParse.grouped(plan.annualCost)
        rateText = String(format: "%.2f", plan.annualRatePercent)
        pmtText = NumberParse.grouped(plan.monthlyContribution)
        baseline = plan
    }

    private func persist() {
        guard let draft, let baseline, draft != baseline else { return }
        self.baseline = draft
        portfolio.setSavings(draft)
    }
}

#Preview {
    NavigationStack {
        SavingsTunerView()
            .environment(Portfolio(items: [
                AssetItem(name: "全球股票 ETF", kind: .original, amount: 1_000_000),
                AssetItem(name: "2x 槓桿 ETF", kind: .leverage, amount: 600_000),
                AssetItem(name: "活存", kind: .cash, amount: 400_000),
            ]))
    }
    .preferredColorScheme(.dark)
}
