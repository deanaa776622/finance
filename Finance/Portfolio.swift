import Foundation
import Observation

@Observable
final class Portfolio {
    var items: [AssetItem]
    var targets: TargetWeights?
    /// Nil or ≤0 → orb sizing falls back to current allocable total (same as web).
    var targetTotal: Decimal?
    var savings: SavingsPlan?
    var histories: [UUID: [AssetMonthMark]]
    var rateMonths: [String: [String: Decimal]]
    /// Hand-entered totals for past months that had no asset records.
    var backfills: [MonthBackfill]

    /// First-use preview keeps edits in memory. The file on disk stays as it was.
    var discardsSaves = false

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("portfolio.json")
    }

    init(
        items: [AssetItem] = [],
        targets: TargetWeights? = nil,
        targetTotal: Decimal? = nil,
        savings: SavingsPlan? = nil,
        histories: [UUID: [AssetMonthMark]] = [:],
        rateMonths: [String: [String: Decimal]] = [:],
        backfills: [MonthBackfill] = []
    ) {
        self.items = items
        self.targets = targets
        self.targetTotal = targetTotal
        self.savings = savings
        self.histories = histories
        self.rateMonths = rateMonths
        self.backfills = backfills
    }

    static func load() -> Portfolio {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Portfolio() }
        let portfolio = Portfolio(
            items: snap.items,
            targets: snap.targets,
            targetTotal: snap.targetTotal,
            savings: snap.savings,
            histories: Dictionary(uniqueKeysWithValues: snap.marks.map { ($0.assetID, $0.months) }),
            rateMonths: Dictionary(uniqueKeysWithValues: snap.rateMonths.map { ($0.month, $0.twdPerUnit) }),
            backfills: snap.backfills
        )
        if AssetHistory.stamp(
            items: portfolio.items,
            histories: &portfolio.histories,
            rateMonths: &portfolio.rateMonths,
            book: RateBook.rates()
        ) {
            portfolio.save()
        }
        return portfolio
    }

    func save() {
        _ = AssetHistory.stamp(
            items: items,
            histories: &histories,
            rateMonths: &rateMonths,
            book: RateBook.rates()
        )
        if discardsSaves { return }
        let snap = Snapshot(
            items: items,
            targets: targets,
            targetTotal: targetTotal,
            savings: savings,
            marks: histories.map { AssetMarks(assetID: $0.key, months: $0.value) },
            rateMonths: rateMonths.map { RateMonth(month: $0.key, twdPerUnit: $0.value) },
            backfills: backfills
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic])
    }

    var netWorth: Decimal {
        items.reduce(0) { partial, item in
            item.kind == .debt ? partial - item.twdValue : partial + item.twdValue
        }
    }

    /// Prototype at face value, leverage scaled by its multiple. Cash, property, and debt sit outside.
    var exposure: Decimal {
        items.reduce(0) { partial, item in
            switch item.kind {
            case .original:
                partial + item.twdValue
            case .leverage:
                partial + item.twdValue * Decimal(item.leverageMultiple ?? 2)
            case .cash, .realEstate, .debt:
                partial
            }
        }
    }

    var allocationMixLabel: String {
        func pct(_ kind: AssetKind) -> Int { Int(actualPercent(for: kind).rounded()) }
        return "原 \(pct(.original))%　槓 \(pct(.leverage))%　現 \(pct(.cash))%"
    }

    var allocableTotal: Decimal {
        items.filter(\.kind.countsTowardAllocation).reduce(0) { $0 + $1.twdValue }
    }

    /// Current mix, used as the target until the user moves the bar.
    var impliedTargets: TargetWeights? {
        guard allocableTotal > 0 else { return nil }
        return TargetWeights(
            original: actualPercent(for: .original),
            leverage: actualPercent(for: .leverage),
            cash: actualPercent(for: .cash)
        )
    }

    /// Baseline for per-bucket target amounts (年花費 ÷ 提領率).
    var targetFromSavings: Decimal? {
        guard let savings else { return nil }
        return SavingsMath.targetAmount(cost: savings.annualCost, withdrawalRatePercent: savings.withdrawalRatePercent)
    }

    /// Nest egg to show before a contribution plan exists. First use types the goal first.
    var goalAmount: Decimal? {
        if let targetFromSavings, targetFromSavings > 0 { return targetFromSavings }
        if savings == nil, let targetTotal, targetTotal > 0 { return targetTotal }
        return nil
    }

    /// Keep the docked distance copy in step with the goal, before rate and contribution are filled in.
    func noteGoal(cost: Decimal?, withdrawalRatePercent: Double?) {
        guard savings == nil else { return }
        guard let cost, cost >= 0,
              let withdrawalRatePercent, withdrawalRatePercent > 0, withdrawalRatePercent <= 100,
              let amount = SavingsMath.targetAmount(cost: cost, withdrawalRatePercent: withdrawalRatePercent),
              amount > 0
        else {
            targetTotal = nil
            return
        }
        targetTotal = amount
    }

    var effectiveTargetTotal: Decimal {
        if let targetFromSavings, targetFromSavings > 0 { return targetFromSavings }
        if let targetTotal, targetTotal > 0 { return targetTotal }
        return allocableTotal
    }

    var outlook: SavingsOutlook? {
        guard let savings else { return nil }
        return SavingsMath.outlook(plan: savings, presentValue: allocableTotal)
    }

    func setSavings(_ plan: SavingsPlan) {
        savings = plan
        if let fv = targetFromSavings { targetTotal = fv }
        save()
    }

    func items(for kind: AssetKind) -> [AssetItem] {
        items.filter { $0.kind == kind }
    }

    func amount(for kind: AssetKind) -> Decimal {
        items(for: kind).reduce(0) { $0 + $1.twdValue }
    }

    func actualPercent(for kind: AssetKind) -> Double {
        guard kind.countsTowardAllocation, allocableTotal > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount(for: kind)).doubleValue
            / NSDecimalNumber(decimal: allocableTotal).doubleValue * 100
    }

    /// Signed TWD so `kind` matches `targetPercent` of today's allocable total. Positive means short.
    func rebalanceGap(for kind: AssetKind, targetPercent: Double) -> Decimal {
        guard kind.countsTowardAllocation else { return 0 }
        return allocableTotal * Decimal(targetPercent) / 100 - amount(for: kind)
    }

    /// 0…1 how far this bucket is toward its slice of the long-term total.
    func achievement(for kind: AssetKind) -> Double {
        guard kind.countsTowardAllocation else { return 0 }
        let percent = targets?.percent(for: kind) ?? actualPercent(for: kind)
        let slice = effectiveTargetTotal * Decimal(percent / 100)
        let actual = amount(for: kind)
        if slice > 0 {
            return min(
                1,
                NSDecimalNumber(decimal: actual).doubleValue
                    / NSDecimalNumber(decimal: slice).doubleValue
            )
        }
        return actual > 0 ? 1 : 0
    }

    func drift(for kind: AssetKind) -> Double {
        guard let targets else { return 0 }
        return abs(actualPercent(for: kind) - targets.percent(for: kind))
    }

    /// 0 at no drift, 1 at 10% and beyond.
    func driftFactor(for kind: AssetKind) -> Double {
        min(1, drift(for: kind) / 10)
    }

    var maxAllocationDrift: Double {
        AssetKind.allCases
            .filter(\.countsTowardAllocation)
            .map { drift(for: $0) }
            .max() ?? 0
    }

    var isBalanced: Bool { maxAllocationDrift < 10 }

    var statusTitle: String {
        if allocableTotal <= 0 { return "尚無紀錄" }
        return isBalanced ? "平衡" : "留意配置"
    }

    var allocationStatus: String {
        if allocableTotal <= 0 { return "新增資產後，會顯示與目標配置的差距" }
        if isBalanced { return "配置大致平衡" }
        return String(format: "與目標最多偏離約 %.0f%%", maxAllocationDrift)
    }

    func upsert(_ item: AssetItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        save()
    }

    func delete(ids: [UUID]) {
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
        for id in set { histories[id] = nil }
        save()
    }

    func delete(_ subset: [AssetItem], at offsets: IndexSet) {
        delete(ids: offsets.map { subset[$0].id })
    }

    func applyQuotes(_ quotes: [UUID: Quote]) {
        guard !quotes.isEmpty else { return }
        for i in items.indices {
            guard let quote = quotes[items[i].id] else { continue }
            items[i].apply(quote)
        }
        save()
    }

    func applyUsdTwd(_ rate: Decimal) {
        var changed = false
        for i in items.indices where items[i].currency == .usd {
            items[i].usdTwdRate = rate
            changed = true
        }
        if changed { save() }
    }

    /// Empty portfolio for the first-use preview. Nothing here is written.
    func beginFirstUse() {
        discardsSaves = true
        items = []
        targets = nil
        targetTotal = nil
        savings = nil
        histories = [:]
        rateMonths = [:]
        backfills = []
    }

    /// Drop the preview and show the portfolio that was already on disk.
    func endFirstUse() {
        let stored = Portfolio.load()
        items = stored.items
        targets = stored.targets
        targetTotal = stored.targetTotal
        savings = stored.savings
        histories = stored.histories
        rateMonths = stored.rateMonths
        backfills = stored.backfills
        discardsSaves = false
    }

    /// Past month with no mark on any asset and no earlier backfill.
    func canBackfill(_ month: String) -> Bool {
        guard month < AssetHistory.monthKey() else { return false }
        if backfills.contains(where: { $0.month == month }) { return false }
        return !histories.values.contains { marks in marks.contains { $0.month == month } }
    }

    func addBackfill(_ row: MonthBackfill) {
        guard canBackfill(row.month) else { return }
        backfills.append(row)
        save()
    }

    /// Changes when a month's amount changes, so the trend chart redraws.
    var historyKey: String {
        var parts: [String] = []
        for (id, marks) in histories {
            for mark in marks {
                parts.append("\(id.uuidString) \(mark.month) \(mark.native)")
            }
        }
        for row in backfills {
            parts.append("b \(row.month) \(row.original) \(row.leverage) \(row.cash) \(row.realEstate) \(row.debt)")
        }
        return parts.sorted().joined(separator: "|")
    }
}
