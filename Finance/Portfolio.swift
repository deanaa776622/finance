import Foundation
import Observation

@Observable
final class Portfolio {
    var items: [AssetItem]
    var targets: TargetWeights
    /// Nil or ≤0 → orb sizing falls back to current allocable total (same as web).
    var targetTotal: Decimal?
    var savings: SavingsPlan?

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("portfolio.json")
    }

    init(
        items: [AssetItem] = [],
        targets: TargetWeights = TargetWeights(),
        targetTotal: Decimal? = nil,
        savings: SavingsPlan? = nil
    ) {
        self.items = items
        self.targets = targets
        self.targetTotal = targetTotal
        self.savings = savings
    }

    static func load() -> Portfolio {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Portfolio() }
        return Portfolio(
            items: snap.items,
            targets: snap.targets,
            targetTotal: snap.targetTotal,
            savings: snap.savings
        )
    }

    func save() {
        let snap = Snapshot(items: items, targets: targets, targetTotal: targetTotal, savings: savings)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic])
    }

    var netWorth: Decimal {
        items.reduce(0) { partial, item in
            item.kind == .debt ? partial - item.twdValue : partial + item.twdValue
        }
    }

    var allocableTotal: Decimal {
        items.filter(\.kind.countsTowardAllocation).reduce(0) { $0 + $1.twdValue }
    }

    /// Baseline for per-bucket target amounts (web: `sav_target_total` from cost ÷ rate).
    var targetFromSavings: Decimal? {
        guard let savings else { return nil }
        return SavingsMath.targetAmount(cost: savings.annualCost, annualRatePercent: savings.annualRatePercent)
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

    /// 0…1 how far this bucket is toward its slice of the long-term total.
    func achievement(for kind: AssetKind) -> Double {
        guard kind.countsTowardAllocation else { return 0 }
        let slice = effectiveTargetTotal * Decimal(targets.percent(for: kind) / 100)
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
        abs(actualPercent(for: kind) - targets.percent(for: kind))
    }

    /// 0 below 2% drift, 1 at 12% and beyond — used to tint the home glow.
    func driftFactor(for kind: AssetKind) -> Double {
        min(1, max(0, (drift(for: kind) - 2) / 10))
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
        return String(format: "與目標最多偏離約 %.0f%%，有空再平衡即可", maxAllocationDrift)
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
}
