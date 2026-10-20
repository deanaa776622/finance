import Foundation

/// One month of one asset: the native amount, and what one unit of that currency bought in TWD then.
struct AssetMonthMark: Codable, Equatable {
    var month: String
    var native: Decimal
    var currency: AssetCurrency
    var twdPerUnit: Decimal

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
                twdPerUnit: item.fxRate
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
}
