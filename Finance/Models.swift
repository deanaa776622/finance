import Foundation
import Observation
import SwiftUI

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

    /// Holdings are valued as shares times price. A debt using that entry stores collateral; the loan is `amount`.
    func valueFollowsShares(_ usesSharePrice: Bool) -> Bool {
        usesSharePrice && self != .debt
    }
}

enum AssetCurrency: String, Codable, CaseIterable, Identifiable {
    case twd = "TWD"
    case usd = "USD"
    case hkd = "HKD"
    case cny = "CNY"
    case jpy = "JPY"
    case eur = "EUR"
    case gbp = "GBP"
    case aud = "AUD"
    case sgd = "SGD"
    case krw = "KRW"
    case cad = "CAD"
    case chf = "CHF"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twd: "TWD 新台幣"
        case .usd: "USD 美元"
        case .hkd: "HKD 港幣"
        case .cny: "CNY 人民幣"
        case .jpy: "JPY 日圓"
        case .eur: "EUR 歐元"
        case .gbp: "GBP 英鎊"
        case .aud: "AUD 澳幣"
        case .sgd: "SGD 新加坡幣"
        case .krw: "KRW 韓元"
        case .cad: "CAD 加幣"
        case .chf: "CHF 瑞士法郎"
        }
    }

    /// Shown beside an amount. TWD uses the fullwidth dollar.
    var symbol: String {
        switch self {
        case .twd: "＄"
        case .usd: "$"
        case .hkd: "HK$"
        case .cny: "￥"
        case .jpy: "¥"
        case .eur: "€"
        case .gbp: "£"
        case .aud: "A$"
        case .sgd: "S$"
        case .krw: "₩"
        case .cad: "C$"
        case .chf: "Fr"
        }
    }
}

struct AssetItem: Identifiable, Codable, Hashable {
    var id: UUID
    /// Display name. Every kind can have one.
    var name: String
    /// Ticker used for quotes. Empty for assets that are not priced by symbol.
    var symbol: String
    var kind: AssetKind
    /// Native-currency amount. Share-priced holdings leave this at 0.
    /// A pledged debt stores the loan here; shares and price are the collateral.
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
        symbol: String = "",
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
        self.symbol = symbol
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.usdTwdRate = usdTwdRate
        self.usesSharePrice = usesSharePrice
        self.shares = shares
        self.price = price
        self.leverageMultiple = leverageMultiple
    }

    /// Rate of this currency into TWD. TWD itself is 1.
    var fxRate: Decimal { currency == .twd ? 1 : usdTwdRate }

    /// Amount in `currency`, before any conversion.
    var nativeValue: Decimal {
        kind.valueFollowsShares(usesSharePrice) ? (shares ?? 0) * (price ?? 0) : amount
    }

    var twdValue: Decimal { nativeValue * fxRate }

    var canRefreshQuote: Bool {
        usesSharePrice && !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, kind, amount, currency, usdTwdRate, usesSharePrice, shares, price, leverageMultiple
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? name
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
    var original: Double
    var leverage: Double
    var cash: Double

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
    var targets: TargetWeights?
    /// Long-term total to grow toward; nil means size orbs against current holdings.
    var targetTotal: Decimal?
    var savings: SavingsPlan?
    /// One row per asset. Old files omit it.
    var marks: [AssetMarks] = []
    /// TWD-per-unit rates for each month, so a later display currency can cross.
    var rateMonths: [RateMonth] = []
    /// Hand-entered months. Old files omit it.
    var backfills: [MonthBackfill] = []

    enum CodingKeys: String, CodingKey {
        case items, targets, targetsChosen, targetTotal, savings, marks, rateMonths, backfills
    }

    init(
        items: [AssetItem],
        targets: TargetWeights?,
        targetTotal: Decimal?,
        savings: SavingsPlan?,
        marks: [AssetMarks] = [],
        rateMonths: [RateMonth] = [],
        backfills: [MonthBackfill] = []
    ) {
        self.items = items
        self.targets = targets
        self.targetTotal = targetTotal
        self.savings = savings
        self.marks = marks
        self.rateMonths = rateMonths
        self.backfills = backfills
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([AssetItem].self, forKey: .items)
        let stored = try c.decodeIfPresent(TargetWeights.self, forKey: .targets)
        if let chosen = try c.decodeIfPresent(Bool.self, forKey: .targetsChosen) {
            targets = chosen ? stored : nil
        } else if let stored, stored != Self.retiredDefault {
            targets = stored
        } else {
            targets = nil
        }
        targetTotal = try c.decodeIfPresent(Decimal.self, forKey: .targetTotal)
        savings = try c.decodeIfPresent(SavingsPlan.self, forKey: .savings)
        marks = try c.decodeIfPresent([AssetMarks].self, forKey: .marks) ?? []
        rateMonths = try c.decodeIfPresent([RateMonth].self, forKey: .rateMonths) ?? []
        backfills = try c.decodeIfPresent([MonthBackfill].self, forKey: .backfills) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encode(targets != nil, forKey: .targetsChosen)
        try c.encodeIfPresent(targets, forKey: .targets)
        try c.encodeIfPresent(targetTotal, forKey: .targetTotal)
        try c.encodeIfPresent(savings, forKey: .savings)
        try c.encode(marks, forKey: .marks)
        try c.encode(rateMonths, forKey: .rateMonths)
        try c.encode(backfills, forKey: .backfills)
    }

    /// Written automatically before a mix could be chosen. A later explicit 50 / 30 / 20 is kept.
    private static let retiredDefault = TargetWeights(original: 50, leverage: 30, cash: 20)
}

enum MoneyFormat {
    /// Currency every on-screen amount uses.
    /// ponytail: fixed TWD until a display-currency setting exists; point this at that setting.
    static var currency: AssetCurrency { .twd }

    static func string(_ value: Decimal) -> String {
        string(value, hidden: false)
    }

    static func string(_ value: Decimal, hidden: Bool) -> String {
        if hidden { return "••••" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency.rawValue
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

    /// Same as `oneDecimal` for rates ≥ 1. Smaller rates (JPY, KRW) keep four places.
    static func fx(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        if number >= 1 { return grouped(oneDecimal(value), fractionDigits: 1) }
        return grouped(String(format: "%.4f", number), fractionDigits: 4)
    }

    /// Share price: at most two decimal places, with thousands separators.
    static func price(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return grouped(NSDecimalNumber(decimal: rounded).stringValue, fractionDigits: 2)
    }

    static func grouped(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? display(value)
    }

    /// Thousands separators on each keystroke. A decimal point stays so the next digit can follow it.
    static func grouped(_ text: String, fractionDigits: Int = 0) -> String {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return "" }
        var intDigits = ""
        var fraction: String?
        for character in cleaned {
            if character.isNumber {
                if var part = fraction {
                    guard part.count < fractionDigits else { continue }
                    part.append(character)
                    fraction = part
                } else {
                    intDigits.append(character)
                }
            } else if character == ".", fractionDigits > 0, fraction == nil {
                fraction = ""
            }
        }
        guard !intDigits.isEmpty || fraction != nil else { return "" }
        let whole = grouped(Decimal(string: intDigits.isEmpty ? "0" : intDigits) ?? 0)
        guard let fraction else { return whole }
        return whole + "." + fraction
    }

    /// Amount field. Formats the text as it changes.
    static func money(_ text: Binding<String>, fractionDigits: Int = 2) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = grouped($0, fractionDigits: fractionDigits) }
        )
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
