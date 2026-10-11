import Charts
import SwiftUI

struct SavingsTunerView: View {
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @FocusState private var field: Field?
    @State private var costText = ""
    @State private var withdrawText = ""
    @State private var rateText = ""
    @State private var pmtText = ""
    @State private var yearsText = ""
    /// Nil asks “given this monthly amount, how many years?” A number asks the other way.
    @State private var horizon: Double?
    @State private var baseline: SavingsPlan?

    private enum Field: Hashable { case cost, withdraw, rate, pmt, years }

    var body: some View {
        Form {
            Section {
                moneyRow("年花費", text: $costText, field: .cost)
                percentRow("提領率", text: $withdrawText, focus: .withdraw)
                percentRow("年報酬率", text: $rateText, focus: .rate)
                moneyRow("月投資額", text: $pmtText, field: .pmt, keepSign: true)
                HStack {
                    Text("達標時間")
                    Spacer()
                    TextField("0", text: $yearsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($field, equals: .years)
                        .frame(width: 72)
                    Text("年").foregroundStyle(.secondary)
                }
                if let note = horizonNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                LabeledContent("額外收入", value: incomeShortfallText)
                LabeledContent("目標金額") {
                    Text(draftOutlook?.targetAmount.map(MoneyFormat.string) ?? "提領率需大於 0")
                }
            }
        }
        .scrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    if field == .pmt, horizon != nil { applyHorizon() }
                    field = nil
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: costText) { _, _ in followInputs() }
        .onChange(of: withdrawText) { _, _ in followInputs() }
        .onChange(of: rateText) { _, _ in followInputs() }
        .onChange(of: pmtText) { old, new in
            guard field == .pmt else { return }
            if let solved = solvedPayment(),
               let shown = NumberParse.decimal(new),
               shown == solved || shown == -solved {
                let text = contributionText(solved)
                if pmtText != text { pmtText = text }
                return
            }
            if NumberParse.decimal(old) == NumberParse.decimal(new) { return }
            horizon = nil
            persist()
            syncYears()
        }
        .onChange(of: yearsText) { _, _ in
            guard field == .years else { return }
            applyHorizon()
        }
        .onChange(of: portfolio.allocableTotal) { _, _ in
            if horizon != nil { applyHorizon() } else { syncYears() }
        }
        .onChange(of: field) { old, _ in
            finishPercent(old)
        }
    }

    private var horizonNote: String? {
        guard let payment = draft?.monthlyContribution else { return nil }
        if horizon == 0 {
            if payment > 0 { return "要現在補上，距離目標才是 0" }
            if payment < 0 { return "現在可提領，距離目標仍是 0" }
            return nil
        }
        return payment < 0 ? "不必再投入，每月可從目前資產提領" : nil
    }

    private var draft: SavingsPlan? {
        guard let cost = NumberParse.decimal(costText), cost >= 0,
              let withdrawal = NumberParse.double(withdrawText), withdrawal >= 0, withdrawal <= 100,
              let rate = NumberParse.double(rateText), rate >= 0, rate <= 100,
              let pmt = NumberParse.decimal(pmtText)
        else { return nil }
        return SavingsPlan(
            annualCost: cost,
            annualRatePercent: rate,
            withdrawalRatePercent: withdrawal,
            monthlyContribution: pmt,
            retirementYears: horizon
        )
    }

    /// Spending not covered by withdrawing from today's assets at the set rate.
    private var incomeShortfallText: String {
        guard let cost = NumberParse.decimal(costText), cost >= 0,
              let withdrawal = NumberParse.double(withdrawText), withdrawal >= 0, withdrawal <= 100
        else { return "—" }
        let gap = SavingsMath.incomeShortfall(
            cost: cost,
            presentValue: portfolio.allocableTotal,
            withdrawalRatePercent: withdrawal
        )
        return MoneyFormat.string(gap, hidden: hideAmounts)
    }

    private var draftOutlook: SavingsOutlook? {
        draft.map { SavingsMath.outlook(plan: $0, presentValue: portfolio.allocableTotal) }
    }

    private func percentRow(_ title: String, text: Binding<String>, focus: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("％", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($field, equals: focus)
                .frame(width: 72)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private func moneyRow(
        _ title: String,
        text: Binding<String>,
        field: Field,
        keepSign: Bool = false
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                if keepSign, text.wrappedValue.hasPrefix("-") {
                    Text("−")
                        .accessibilityHidden(true)
                }
                TextField("0", text: keepSign ? magnitude(text) : grouped(text))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($field, equals: field)
                    .fixedSize(horizontal: keepSign && text.wrappedValue.hasPrefix("-"), vertical: false)
                    .frame(
                        minWidth: keepSign && text.wrappedValue.hasPrefix("-") ? 0 : 120,
                        alignment: .trailing
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func grouped(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = NumberParse.grouped($0) }
        )
    }

    /// The number pad drops a minus typed into the field. Keep it beside the digits.
    private func magnitude(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: {
                let raw = text.wrappedValue
                return raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
            },
            set: { raw in
                let body = NumberParse.grouped(raw)
                let negative = text.wrappedValue.hasPrefix("-")
                let next = negative && !body.isEmpty ? "-\(body)" : body
                if text.wrappedValue != next { text.wrappedValue = next }
            }
        )
    }

    private func load() {
        let plan = portfolio.savings ?? .prototype
        horizon = plan.retirementYears
        costText = NumberParse.grouped(plan.annualCost)
        withdrawText = percentText(plan.withdrawalRatePercent)
        rateText = percentText(plan.annualRatePercent)
        pmtText = contributionText(plan.monthlyContribution)
        if let years = plan.retirementYears {
            yearsText = yearsLabel(years)
        }
        baseline = plan
        if horizon != nil { applyHorizon() } else { syncYears() }
    }

    /// Two decimals once the field is no longer being edited. A trailing dot still counts.
    private func finishPercent(_ focus: Field?) {
        switch focus {
        case .withdraw:
            let shown = percentText(withdrawText)
            if withdrawText != shown { withdrawText = shown }
        case .rate:
            let shown = percentText(rateText)
            if rateText != shown { rateText = shown }
        default:
            break
        }
    }

    private func percentText(_ text: String) -> String {
        var raw = text
        if raw.hasSuffix(".") { raw.removeLast() }
        guard let value = NumberParse.double(raw) else { return text }
        return percentText(value)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Cost and rate keep whichever question was asked last.
    private func followInputs() {
        if horizon != nil { applyHorizon() } else { persist(); syncYears() }
    }

    private func solvedPayment() -> Decimal? {
        guard let years = horizon, years >= 0,
              let cost = NumberParse.decimal(costText),
              let withdrawal = NumberParse.double(withdrawText), withdrawal > 0, withdrawal <= 100,
              let rate = NumberParse.double(rateText), rate >= 0, rate <= 100,
              let future = SavingsMath.targetAmount(cost: cost, withdrawalRatePercent: withdrawal)
        else { return nil }
        return SavingsMath.monthlyContribution(
            years: years,
            annualRatePercent: rate,
            presentValue: portfolio.allocableTotal,
            futureValue: future
        )
    }

    private func applyHorizon() {
        guard let years = NumberParse.double(yearsText), years >= 0,
              let cost = NumberParse.decimal(costText),
              let withdrawal = NumberParse.double(withdrawText), withdrawal > 0, withdrawal <= 100,
              let rate = NumberParse.double(rateText), rate >= 0, rate <= 100,
              let future = SavingsMath.targetAmount(cost: cost, withdrawalRatePercent: withdrawal),
              let payment = SavingsMath.monthlyContribution(
                years: years,
                annualRatePercent: rate,
                presentValue: portfolio.allocableTotal,
                futureValue: future
              )
        else { return }
        horizon = years
        let text = contributionText(payment)
        if pmtText != text { pmtText = text }
        persist()
    }

    private func syncYears() {
        guard field != .years, horizon == nil else { return }
        guard let years = draftOutlook?.years else {
            yearsText = ""
            return
        }
        let text = yearsLabel(years)
        if yearsText != text { yearsText = text }
    }

    /// Keeps a leading minus. The shared grouped parser drops every non-digit.
    private func contributionText(_ value: Decimal) -> String {
        let magnitude = NumberParse.grouped(value < 0 ? -value : value)
        return value < 0 ? "-\(magnitude)" : magnitude
    }

    private func yearsLabel(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private func persist() {
        guard let draft, let baseline, draft != baseline else { return }
        self.baseline = draft
        portfolio.setSavings(draft)
    }
}

#Preview {
    let _ = {
        let egg = SavingsMath.targetAmount(cost: 1_440_000, withdrawalRatePercent: 4)
        assert(egg == .some(36_000_000))
        let gap = SavingsMath.incomeShortfall(cost: 1_440_000, presentValue: 10_000_000, withdrawalRatePercent: 4)
        assert(gap == 1_040_000)
        assert(SavingsMath.incomeShortfall(cost: 1_440_000, presentValue: 40_000_000, withdrawalRatePercent: 4) == 0)
        return egg
    }()
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
