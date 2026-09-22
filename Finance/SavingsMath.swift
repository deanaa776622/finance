import Foundation

struct SavingsPlan: Codable, Equatable {
    var annualCost: Decimal
    var annualRatePercent: Double
    var monthlyContribution: Decimal

    static let prototype = SavingsPlan(
        annualCost: 1_440_000, annualRatePercent: 7, monthlyContribution: 13_500
    )
}

struct SavingsPoint: Identifiable {
    var year: Int
    var amount: Double
    var id: Int { year }
}

struct SavingsOutlook {
    var targetAmount: Decimal?
    var months: Double?
    var progress: Double
    var points: [SavingsPoint]
    var alreadyReached: Bool
    var needsPositiveRate: Bool
    var unreachable: Bool

    var years: Double? { months.map { $0 / 12 } }

    var yearsText: String {
        if needsPositiveRate || unreachable { return "--" }
        if alreadyReached { return "0" }
        guard let years else { return "--" }
        return String(format: "%.1f", years)
    }

    var detailText: String {
        if needsPositiveRate { return "報酬率需大於 0" }
        if alreadyReached { return "已達成目標" }
        if unreachable { return "可提高月投資或報酬率" }
        guard let months else { return "" }
        return "約 \(Int(ceil(months))) 個月"
    }
}

enum SavingsMath {
    /// Nest egg that funds `annualCost` at `annualRatePercent` (web: cost ÷ rate).
    static func targetAmount(cost: Decimal, annualRatePercent: Double) -> Decimal? {
        guard annualRatePercent > 0 else { return nil }
        return cost / (Decimal(annualRatePercent) / 100)
    }

    static func outlook(plan: SavingsPlan, presentValue: Decimal) -> SavingsOutlook {
        let pv = NSDecimalNumber(decimal: presentValue).doubleValue
        let pmt = NSDecimalNumber(decimal: plan.monthlyContribution).doubleValue
        let annualRate = plan.annualRatePercent / 100
        let fvDec = targetAmount(cost: plan.annualCost, annualRatePercent: plan.annualRatePercent)
        let fv = fvDec.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        let needsRate = plan.annualRatePercent <= 0 && plan.annualCost > 0
        let reached = fv > 0 && pv >= fv
        let rawMonths: Double?
        if needsRate || fvDec == nil {
            rawMonths = nil
        } else if reached {
            rawMonths = 0
        } else if let n = nper(rate: annualRate / 12, pmt: -abs(pmt), pv: -abs(pv), fv: fv), n > 0 {
            rawMonths = n
        } else {
            rawMonths = nil
        }
        let unreachable = rawMonths == nil && !reached && !needsRate && fvDec != nil
        let yearSpan = max(Int(ceil((rawMonths ?? 0) / 12)) + 1, 5)
        let points = (fvDec == nil || unreachable) ? [] : projection(
            pv: pv, monthlyPmt: pmt, annualRate: annualRate, years: yearSpan
        )
        return SavingsOutlook(
            targetAmount: fvDec,
            months: rawMonths,
            progress: fv > 0 ? min(1, max(0, pv / fv)) : 0,
            points: points,
            alreadyReached: reached,
            needsPositiveRate: needsRate,
            unreachable: unreachable
        )
    }

    /// Excel NPER; `pmt` and `pv` are signed (outflows negative), matching `index.html`.
    static func nper(rate: Double, pmt: Double, pv: Double, fv: Double) -> Double? {
        if rate == 0 {
            guard pmt != 0 else { return nil }
            return -(pv + fv) / pmt
        }
        let num = pmt - fv * rate
        let den = pmt + pv * rate
        let ratio = num / den
        guard den != 0, ratio > 0 else { return nil }
        return log(ratio) / log(1 + rate)
    }

    static func projection(pv: Double, monthlyPmt: Double, annualRate: Double, years: Int) -> [SavingsPoint] {
        let monthlyRate = annualRate / 12
        var asset = pv
        return (0...years).map { year in
            let point = SavingsPoint(year: year, amount: asset)
            for _ in 0..<12 { asset = (asset + monthlyPmt) * (1 + monthlyRate) }
            return point
        }
    }
}
