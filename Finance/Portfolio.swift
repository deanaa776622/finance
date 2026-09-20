import Foundation
import Observation

@Observable
final class Portfolio {
    var items: [AssetItem]
    var targets: TargetWeights

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("portfolio.json")
    }

    init(items: [AssetItem] = [], targets: TargetWeights = TargetWeights()) {
        self.items = items
        self.targets = targets
    }

    static func load() -> Portfolio {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Portfolio() }
        return Portfolio(items: snap.items, targets: snap.targets)
    }

    func save() {
        let snap = Snapshot(items: items, targets: targets)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic])
    }

    var netWorth: Decimal {
        items.reduce(0) { partial, item in
            item.kind == .debt ? partial - item.amount : partial + item.amount
        }
    }

    var allocableTotal: Decimal {
        items.filter(\.kind.countsTowardAllocation).reduce(0) { $0 + $1.amount }
    }

    func actualPercent(for kind: AssetKind) -> Double {
        guard kind.countsTowardAllocation, allocableTotal > 0 else { return 0 }
        let sum = items.filter { $0.kind == kind }.reduce(Decimal(0)) { $0 + $1.amount }
        return NSDecimalNumber(decimal: sum).doubleValue
            / NSDecimalNumber(decimal: allocableTotal).doubleValue * 100
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

    func delete(ids: IndexSet) {
        for index in ids.sorted(by: >) { items.remove(at: index) }
        save()
    }
}
