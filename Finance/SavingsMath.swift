import Foundation

struct SavingsPlan: Equatable {
    var annualCost: Decimal
    var annualRatePercent: Double
    /// Safe withdrawal rate. The target is annual cost divided by this, not by the return.
    var withdrawalRatePercent: Double = 4
    var monthlyContribution: Decimal
    /// When set, monthly contribution is solved so this horizon still holds as assets change.
    var retirementYears: Double? = nil

    static let prototype = SavingsPlan(
        annualCost: 1_440_000, annualRatePercent: 7, withdrawalRatePercent: 4, monthlyContribution: 13_500
    )

    /// Keeps `retirementYears` fixed by replacing the contribution. No horizon leaves the plan unchanged.
    func solving(presentValue: Decimal) -> SavingsPlan {
        guard let years = retirementYears, years >= 0,
              let future = SavingsMath.targetAmount(cost: annualCost, withdrawalRatePercent: withdrawalRatePercent),
              let payment = SavingsMath.monthlyContribution(
                years: years,
                annualRatePercent: annualRatePercent,
                presentValue: presentValue,
                futureValue: future
              )
        else { return self }
        var copy = self
        copy.monthlyContribution = payment
        return copy
    }
}

extension SavingsPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case annualCost, annualRatePercent, withdrawalRatePercent, monthlyContribution, retirementYears
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        annualCost = try c.decode(Decimal.self, forKey: .annualCost)
        annualRatePercent = try c.decode(Double.self, forKey: .annualRatePercent)
        // Old saves used the return as the divisor. Keep that number until a withdrawal rate is stored.
        withdrawalRatePercent = try c.decodeIfPresent(Double.self, forKey: .withdrawalRatePercent) ?? annualRatePercent
        monthlyContribution = try c.decode(Decimal.self, forKey: .monthlyContribution)
        retirementYears = try c.decodeIfPresent(Double.self, forKey: .retirementYears)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(annualCost, forKey: .annualCost)
        try c.encode(annualRatePercent, forKey: .annualRatePercent)
        try c.encode(withdrawalRatePercent, forKey: .withdrawalRatePercent)
        try c.encode(monthlyContribution, forKey: .monthlyContribution)
        try c.encodeIfPresent(retirementYears, forKey: .retirementYears)
    }
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
    /// Horizon is exactly now. The contribution is the lump that makes the distance 0.
    var retiresNow = false

    var years: Double? { months.map { $0 / 12 } }

    var yearsText: String {
        if needsPositiveRate || unreachable { return "--" }
        if retiresNow || alreadyReached { return "0" }
        guard let years else { return "--" }
        return String(format: "%.1f", years)
    }

    var detailText: String {
        if needsPositiveRate { return "提領率需大於 0" }
        if alreadyReached || retiresNow { return "已達成目標" }
        if unreachable { return "可提高月投資或報酬率" }
        guard let months else { return "" }
        return "約 \(Int(ceil(months))) 個月"
    }
}

enum SavingsMath {
    /// Nest egg that funds `annualCost` at the withdrawal rate (年花費 ÷ 提領率).
    static func targetAmount(cost: Decimal, withdrawalRatePercent: Double) -> Decimal? {
        guard withdrawalRatePercent > 0 else { return nil }
        return cost / (Decimal(withdrawalRatePercent) / 100)
    }

    /// Monthly amount that reaches `futureValue` in `years`, using the same monthly compounding as `nper`.
    static func monthlyContribution(
        years: Double,
        annualRatePercent: Double,
        presentValue: Decimal,
        futureValue: Decimal
    ) -> Decimal? {
        guard years >= 0, futureValue > 0 else { return nil }
        if years == 0 {
            let gap = NSDecimalNumber(decimal: futureValue - presentValue).doubleValue
            guard gap.isFinite else { return nil }
            return Decimal(Int(gap.rounded()))
        }
        let present = abs(NSDecimalNumber(decimal: presentValue).doubleValue)
        let future = NSDecimalNumber(decimal: futureValue).doubleValue
        let periods = years * 12
        let rate = annualRatePercent / 100 / 12
        let raw: Double
        if rate == 0 {
            raw = (future - present) / periods
        } else {
            let growth = pow(1 + rate, periods)
            guard growth.isFinite, growth != 1 else { return nil }
            raw = (future - present * growth) * rate / (growth - 1)
        }
        guard raw.isFinite else { return nil }
        return Decimal(Int(raw.rounded()))
    }

    static func outlook(plan: SavingsPlan, presentValue: Decimal) -> SavingsOutlook {
        let plan = plan.solving(presentValue: presentValue)
        if plan.retirementYears == 0 {
            return retiringNow(plan: plan, presentValue: presentValue)
        }
        let pv = NSDecimalNumber(decimal: presentValue).doubleValue
        let pmt = NSDecimalNumber(decimal: plan.monthlyContribution).doubleValue
        let annualRate = plan.annualRatePercent / 100
        let fvDec = targetAmount(cost: plan.annualCost, withdrawalRatePercent: plan.withdrawalRatePercent)
        let fv = fvDec.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        let needsRate = plan.withdrawalRatePercent <= 0 && plan.annualCost > 0
        let reached = fv > 0 && pv >= fv
        let rawMonths: Double?
        if needsRate || fvDec == nil {
            rawMonths = nil
        } else if reached {
            rawMonths = 0
        } else if let n = nper(rate: annualRate / 12, pmt: -pmt, pv: -abs(pv), fv: fv), n > 0 {
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

    /// Zero years means the cash that makes the distance 0 today. A shortfall is that lump.
    private static func retiringNow(plan: SavingsPlan, presentValue: Decimal) -> SavingsOutlook {
        let fvDec = targetAmount(cost: plan.annualCost, withdrawalRatePercent: plan.withdrawalRatePercent)
        let pv = NSDecimalNumber(decimal: presentValue).doubleValue
        let fv = fvDec.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        let needsRate = plan.withdrawalRatePercent <= 0 && plan.annualCost > 0
        let reached = fv > 0 && pv >= fv
        return SavingsOutlook(
            targetAmount: fvDec,
            months: 0,
            progress: fv > 0 ? min(1, max(0, pv / fv)) : 0,
            points: [],
            alreadyReached: reached,
            needsPositiveRate: needsRate,
            unreachable: false,
            retiresNow: !needsRate && fvDec != nil && !reached
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
