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

    /// Fits a five-segment control; list headers still use `title`.
    var compactTitle: String {
        switch self {
        case .realEstate: "實體"
        default: title
        }
    }

    /// Only the three financial buckets carry target weights; property and debt sit outside.
    var countsTowardAllocation: Bool {
        switch self {
        case .original, .leverage, .cash: true
        case .realEstate, .debt: false
        }
    }

    var prefersSharePrice: Bool {
        switch self {
        case .original, .leverage: true
        case .cash, .realEstate, .debt: false
        }
    }
}

enum AssetCurrency: String, Codable, CaseIterable, Identifiable {
    case twd = "TWD"
    case usd = "USD"

    var id: String { rawValue }
}

struct AssetItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: AssetKind
    /// Native-currency lump sum when `usesSharePrice` is false.
    var amount: Decimal
    var currency: AssetCurrency
    var usdTwdRate: Decimal
    var usesSharePrice: Bool
    var shares: Decimal?
    var price: Decimal?
    var leverageMultiple: Double?

    init(
        id: UUID = UUID(),
        name: String,
        kind: AssetKind,
        amount: Decimal,
        currency: AssetCurrency = .twd,
        usdTwdRate: Decimal = 32,
        usesSharePrice: Bool = false,
        shares: Decimal? = nil,
        price: Decimal? = nil,
        leverageMultiple: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.usdTwdRate = usdTwdRate
        self.usesSharePrice = usesSharePrice
        self.shares = shares
        self.price = price
        self.leverageMultiple = leverageMultiple
    }

    var fxRate: Decimal { currency == .usd ? usdTwdRate : 1 }

    var twdValue: Decimal {
        let native = usesSharePrice ? (shares ?? 0) * (price ?? 0) : amount
        return native * fxRate
    }

    var canRefreshQuote: Bool {
        usesSharePrice && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, amount, currency, usdTwdRate, usesSharePrice, shares, price, leverageMultiple
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(AssetKind.self, forKey: .kind)
        amount = try c.decode(Decimal.self, forKey: .amount)
        currency = try c.decodeIfPresent(AssetCurrency.self, forKey: .currency) ?? .twd
        usdTwdRate = try c.decodeIfPresent(Decimal.self, forKey: .usdTwdRate) ?? 32
        usesSharePrice = try c.decodeIfPresent(Bool.self, forKey: .usesSharePrice) ?? false
        shares = try c.decodeIfPresent(Decimal.self, forKey: .shares)
        price = try c.decodeIfPresent(Decimal.self, forKey: .price)
        leverageMultiple = try c.decodeIfPresent(Double.self, forKey: .leverageMultiple)
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
        string(value, hidden: false)
    }

    static func string(_ value: Decimal, hidden: Bool) -> String {
        if hidden { return "••••" }
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

    /// FX rate shown in the editor: one decimal, dot separator.
    static func oneDecimal(_ value: Decimal) -> String {
        String(format: "%.1f", NSDecimalNumber(decimal: value).doubleValue)
    }

    /// Share price: at most two decimal places.
    static func price(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
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
