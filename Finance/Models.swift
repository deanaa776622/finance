import Foundation
import Observation

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case investment, cash, realEstate, other, debt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .investment: "投資"
        case .cash: "現金"
        case .realEstate: "實體資產"
        case .other: "其他"
        case .debt: "負債"
        }
    }

    var countsTowardAllocation: Bool { self != .debt }
}

struct AssetItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: AssetKind
    var amount: Decimal

    init(id: UUID = UUID(), name: String, kind: AssetKind, amount: Decimal) {
        self.id = id
        self.name = name
        self.kind = kind
        self.amount = amount
    }
}

struct TargetWeights: Codable, Equatable {
    var investment: Double = 60
    var cash: Double = 20
    var realEstate: Double = 15
    var other: Double = 5

    func percent(for kind: AssetKind) -> Double {
        switch kind {
        case .investment: investment
        case .cash: cash
        case .realEstate: realEstate
        case .other: other
        case .debt: 0
        }
    }

    mutating func setPercent(_ value: Double, for kind: AssetKind) {
        switch kind {
        case .investment: investment = value
        case .cash: cash = value
        case .realEstate: realEstate = value
        case .other: other = value
        case .debt: break
        }
    }
}

struct Snapshot: Codable, Equatable {
    var items: [AssetItem]
    var targets: TargetWeights
}

enum MoneyFormat {
    static func string(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.maximumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
