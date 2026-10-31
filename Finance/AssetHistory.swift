import Foundation

/// A past month filled in by hand. Amounts are TWD. Debt is the positive loan size.
struct MonthBackfill: Codable, Equatable {
    var month: String
    var original: Decimal
    var leverage: Decimal
    var cash: Decimal
    var realEstate: Decimal
    var debt: Decimal

    func amount(for kind: AssetKind) -> Decimal {
        switch kind {
        case .original: original
        case .leverage: leverage
        case .cash: cash
        case .realEstate: realEstate
        case .debt: debt
        }
    }
}
struct AssetMonthMark: Codable, Equatable {
    var month: String
    var native: Decimal
    var currency: AssetCurrency
    var twdPerUnit: Decimal
    /// Share count that month. Missing on marks saved before this was kept.
    var shares: Decimal?

    /// `native` in `display`, using this month's rates. Same currency needs no rate.
    func amount(in display: AssetCurrency, rates: [String: Decimal]) -> Decimal? {
        if display == currency { return native }
        let twd = native * twdPerUnit
        if display == .twd { return twd }
        guard let perUnit = rates[display.rawValue], perUnit > 0 else { return nil }
        return twd / perUnit
    }
}

struct AssetMarks: Codable, Equatable {
    var assetID: UUID
    var months: [AssetMonthMark]
}

/// Shared rates for a month. Keys are currency codes; values are TWD per one unit.
struct RateMonth: Codable, Equatable {
    var month: String
    var twdPerUnit: [String: Decimal]
}

enum AssetHistory {
    static func monthKey(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Rewrites this month's mark for each asset, and this month's rate board. Past months stay.
    static func stamp(
        items: [AssetItem],
        histories: inout [UUID: [AssetMonthMark]],
        rateMonths: inout [String: [String: Decimal]],
        book: [AssetCurrency: Decimal],
        date: Date = Date()
    ) -> Bool {
        let month = monthKey(date)
        var changed = false
        var board = rateMonths[month] ?? [:]
        if board[AssetCurrency.twd.rawValue] != 1 {
            board[AssetCurrency.twd.rawValue] = 1
            changed = true
        }
        for (code, rate) in book where board[code.rawValue] != rate {
            board[code.rawValue] = rate
            changed = true
        }
        for item in items {
            if board[item.currency.rawValue] != item.fxRate {
                board[item.currency.rawValue] = item.fxRate
                changed = true
            }
            var marks = histories[item.id] ?? []
            let mark = AssetMonthMark(
                month: month,
                native: item.nativeValue,
                currency: item.currency,
                twdPerUnit: item.fxRate,
                shares: item.shares
            )
            if let index = marks.lastIndex(where: { $0.month == month }) {
                if marks[index] != mark {
                    marks[index] = mark
                    changed = true
                }
            } else {
                marks.append(mark)
                changed = true
            }
            histories[item.id] = marks
        }
        if rateMonths[month] != board {
            rateMonths[month] = board
            changed = true
        }
        return changed
    }

    /// One point per recorded month. Debt is negative, including when it is the only kind in the group.
    static func months(
        kinds: [AssetKind],
        items: [AssetItem],
        histories: [UUID: [AssetMonthMark]],
        rateMonths: [String: [String: Decimal]],
        backfills: [MonthBackfill] = []
    ) -> [GroupMonthPoint] {
        let mine = items.filter { kinds.contains($0.kind) }
        var keys = Set(mine.flatMap { histories[$0.id]?.map(\.month) ?? [] })
        for row in backfills {
            keys.insert(row.month)
        }
        return keys.sorted().map { month in
            let rates = rateMonths[month] ?? [:]
            var total = mine.reduce(Decimal.zero) { partial, item in
                guard let mark = histories[item.id]?.last(where: { $0.month == month }),
                      let amount = mark.amount(in: .twd, rates: rates) else { return partial }
                if item.kind == .debt { return partial - amount }
                return partial + amount
            }
            if let row = backfills.first(where: { $0.month == month }) {
                for kind in kinds {
                    let value = row.amount(for: kind)
                    total += kind == .debt ? -value : value
                }
            }
            return GroupMonthPoint(month: month, amount: total)
        }
    }
}

struct GroupMonthPoint: Identifiable, Equatable {
    var month: String
    var amount: Decimal
    var id: String { month }
    var plot: Double { NSDecimalNumber(decimal: amount).doubleValue }
}
