import SwiftUI

/// Free-tier limits. A purchase writes the same key StoreKit checks.
enum ProPreview {
    static let key = "previewPro"
    static let freshKey = "previewFresh"
    static let freeAssetLimit = 10

    static func canAddAsset(count: Int, isPro: Bool) -> Bool {
        isPro || count < freeAssetLimit
    }

    /// Target pile and how much of it is already held. Does not need a contribution plan.
    static func coverageLine(portfolio: Portfolio) -> (amount: Decimal, detail: String)? {
        guard let target = portfolio.goalAmount, target > 0 else { return nil }
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
    @AppStorage(ProPreview.key) private var isPro = false

    var body: some View {
        VStack(spacing: 6) {
            Text("距離目標")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
            if isPro, let outlook = portfolio.outlook {
                years(outlook)
            } else if let line = ProPreview.coverageLine(portfolio: portfolio) {
                amount(line)
            } else {
                unset
            }
        }
    }

    private func years(_ outlook: SavingsOutlook) -> some View {
        VStack(spacing: 6) {
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
        }
    }

    private func amount(_ line: (amount: Decimal, detail: String)) -> some View {
        VStack(spacing: 6) {
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
        }
    }

    private var unset: some View {
        Text("尚未設定")
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

/// Free plan stays on the title. It does not open into the years and monthly amount.
struct SavingsPlanLocked: View {
    var titleFrame: ((CGRect) -> Void)? = nil
    @Environment(Palette.self) private var palette
    @State private var showPaywall = false
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20

    var body: some View {
        Section {
            Button { showPaywall = true } label: {
                HStack {
                    Text("計畫")
                        .font(.system(size: titleSize, weight: .semibold))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { titleFrame?($0) }
                    Spacer()
                    Text("未解鎖")
                        .font(.system(size: titleSize))
                        .foregroundStyle(palette.quietInk)
                }
            }
            .buttonStyle(.plain)
            .groupHeaderChrome()
            .accessibilityHint("未解鎖")
        }
        .foregroundStyle(palette.ink)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

/// One-time purchase of the full record: unlimited assets, quotes, and the savings plan.
struct PaywallView: View {
    @Environment(Palette.self) private var palette
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProPreview.key) private var isPro = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    labeled("不限筆數", "免費版最多 \(ProPreview.freeAssetLimit) 筆")
                    labeled("自動更新股價", "不用每次手動填價格")
                    labeled("距離目標", "看還要幾年、每月該存多少")
                    labeled("補登過去月份", "把更早的資產補進趨勢")
                }
                .listRowBackground(palette.panel)
                Section {
                    Button(buyTitle) { Task { await buy() } }
                        .disabled(store.buying || isPro)
                    Button("恢復購買") { Task { await restore() } }
                        .disabled(store.buying)
                } footer: {
                    Text(store.note.isEmpty ? "一次買斷，沒有每月扣款。" : store.note)
                }
                .listRowBackground(palette.panel)
            }
            .tint(palette.ink)
            .listStyle(.insetGrouped)
            .listSectionSpacing(.default)
            .contentMargins(.all, nil, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .palettePanel(palette)
            .navigationTitle("完整記錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationBackground(palette.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await store.load() }
    }

    private var buyTitle: String {
        if isPro { return "已解鎖" }
        if let product = store.product { return "以 \(product.displayPrice) 買斷" }
        return "讀取價格"
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(palette.quietInk)
        }
    }

    private func buy() async {
        if store.product == nil { await store.load() }
        if await store.buy() { dismiss() }
    }

    private func restore() async {
        if await store.restore() { dismiss() }
    }
}
