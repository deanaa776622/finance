import Foundation
import Observation

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case original, leverage, cash, realEstate, debt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原型"
        case .leverage: "槓桿"
        case .cash: "現金"
        case .realEstate: "實體資產"
        case .debt: "負債"
        }
    }

    /// Only the three financial buckets carry target weights; property and debt sit outside.
    var countsTowardAllocation: Bool {
        switch self {
        case .original, .leverage, .cash: true
        case .realEstate, .debt: false
        }
    }
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
    var original: Double = 50
    var leverage: Double = 30
    var cash: Double = 20

    func percent(for kind: AssetKind) -> Double {
        switch kind {
        case .original: original
        case .leverage: leverage
        case .cash: cash
        case .realEstate, .debt: 0
        }
    }

    mutating func setPercent(_ value: Double, for kind: AssetKind) {
        switch kind {
        case .original: original = value
        case .leverage: leverage = value
        case .cash: cash = value
        case .realEstate, .debt: break
        }
    }
}

struct Snapshot: Codable, Equatable {
    var items: [AssetItem]
    var targets: TargetWeights
    /// Long-term total to grow toward; nil means size orbs against current holdings.
    var targetTotal: Decimal?
    var savings: SavingsPlan?
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

enum NumberParse {
    static func display(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func grouped(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? display(value)
    }

    static func grouped(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty, let value = Decimal(string: digits) else { return "" }
        return grouped(value)
    }

    static func displayPercent(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(value)
    }

    static func decimal(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned)
    }

    static func double(_ text: String) -> Double? {
        decimal(text).map { NSDecimalNumber(decimal: $0).doubleValue }
    }
}
