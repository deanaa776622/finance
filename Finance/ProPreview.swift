import SwiftUI

/// Simulator switch for the paid savings answer. Replace with StoreKit when charging is real.
enum ProPreview {
    static let key = "previewPro"
    static let freeAssetLimit = 10

    static func canAddAsset(count: Int, isPro: Bool) -> Bool {
        isPro || count < freeAssetLimit
    }

    /// Target pile and how much of it is already held. Does not need a contribution plan.
    static func coverageLine(portfolio: Portfolio) -> (amount: Decimal, detail: String)? {
        guard let target = portfolio.targetFromSavings, target > 0 else { return nil }
        let present = NSDecimalNumber(decimal: portfolio.allocableTotal).doubleValue
        let future = NSDecimalNumber(decimal: target).doubleValue
        guard future > 0 else { return nil }
        let percent = Int((min(1, present / future) * 100).rounded())
        let detail = percent >= 100 ? "已達成目標" : "已達成 \(percent)%"
        return (target, detail)
    }
}

struct GoalDistanceCopy: View {
    let portfolio: Portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage(ProPreview.key) private var isPro = true

    var body: some View {
        VStack(spacing: 6) {
            Text("距離目標")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
            if isPro {
                paid
            } else {
                free
            }
        }
    }

    @ViewBuilder private var paid: some View {
        if let outlook = portfolio.outlook {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(outlook.yearsText)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text("年")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(outlook.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        } else {
            unset
        }
    }

    @ViewBuilder private var free: some View {
        if let line = ProPreview.coverageLine(portfolio: portfolio) {
            Text(MoneyFormat.string(line.amount, hidden: hideAmounts))
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
            Text(line.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            unset
        }
    }

    private var unset: some View {
        Text("尚未設定")
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

/// Plan, years, monthly amount, and the curve stay behind this row.
struct SavingsPlanLocked: View {
    @Environment(Palette.self) private var palette
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20

    var body: some View {
        Section {
            HStack {
                Text("計畫")
                    .font(.system(size: titleSize, weight: .semibold))
                Spacer()
                Text("未解鎖")
                    .font(.system(size: titleSize))
                    .foregroundStyle(palette.quietInk)
            }
            .groupHeaderChrome()
            Text("解鎖後可看還要幾年、每月該存多少")
                .font(.footnote)
                .foregroundStyle(palette.quietInk)
                .groupCardRow(isFirst: true, isLast: true)
        }
        .foregroundStyle(palette.ink)
    }
}
