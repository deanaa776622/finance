import SwiftUI

/// Bottom bar on a phone, and the same controls in the Duo side column.
struct PortfolioMenu: ViewModifier {
    var showsChrome: Bool
    var sideColumn: Bool
    var bottomBar: Bool
    var showsSort: Bool
    var groups: AssetGroups
    var exposureOnly: Bool

    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage(ProPreview.key) private var isPro = false
    @AppStorage(ProPreview.freshKey) private var isFresh = false
    @AppStorage("assetSortKey") private var sortKey = "stored"
    @AppStorage("assetSortAscending") private var sortAscending = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAdd = false
    @State private var showAssetLimit = false
    @State private var showQuoteLocked = false
    @State private var showBackfillLocked = false
    @State private var showColors = false
    @State private var showBackup = false
    @State private var showPaywall = false
    @State private var showBackfill = false
    @State private var isRefreshing = false
    @State private var refreshConfirmed = false
    @State private var showQuoteError = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsChrome, sideColumn {
                    ToolbarItem(placement: .topBarTrailing) { hideControl }.preferSideColumn()
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing).preferSideColumn()
                    }
                    if showsSort {
                        ToolbarItem(placement: .topBarTrailing) { sortControl }.preferSideColumn()
                    }
                    ToolbarItem(placement: .topBarTrailing) { refreshControl }.preferSideColumn()
                    ToolbarItem(placement: .topBarTrailing) { addControl }.preferSideColumn()
                    ToolbarItem(placement: .topBarTrailing) { settingsMenu }.preferSideColumn()
                }
            }
            .modifier(AssetMenuBar(isShown: showsChrome && bottomBar && !sideColumn) { menuBar })
            .sheet(isPresented: $showAdd) {
                AssetEditor(item: nil, defaultKind: .original, onSave: save)
            }
            .sheet(isPresented: $showColors) { ColorSettingsView() }
            .sheet(isPresented: $showBackup) { BackupSettingsView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showBackfill) { MonthBackfillView() }
            .alert("無法更新現值", isPresented: $showQuoteError) {
                Button("好", role: .cancel) {}
            } message: {
                Text("報價暫時取不到，請稍後再試。")
            }
            .alert("已記滿 \(ProPreview.freeAssetLimit) 筆", isPresented: $showAssetLimit) {
                Button("解鎖") { showPaywall = true }
                Button("好", role: .cancel) {}
            } message: {
                Text("免費版最多記 \(ProPreview.freeAssetLimit) 筆。")
            }
            .alert("不支援股價自動更新", isPresented: $showQuoteLocked) {
                Button("解鎖") { showPaywall = true }
                Button("好", role: .cancel) {}
            } message: {
                Text("免費版請手動填價格。")
            }
            .alert("不支援補登過去月份", isPresented: $showBackfillLocked) {
                Button("解鎖") { showPaywall = true }
                Button("好", role: .cancel) {}
            } message: {
                Text("免費版不能補上過去的月份。")
            }
    }

    private var menuBar: some View {
        HStack {
            hideControl.modifier(CircleGlass())
            Spacer(minLength: 16)
            trailingCluster
        }
    }

    private var trailingCluster: some View {
        HStack(spacing: 0) {
            if showsSort {
                sortControl.frame(width: 44, height: 44)
            }
            refreshControl.frame(width: 44, height: 44)
            addControl.frame(width: 44, height: 44)
            settingsMenu.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .modifier(CapsuleGlass())
    }

    private var hideControl: some View {
        Button {
            hideAmounts.toggle()
        } label: {
            Image(systemName: hideAmounts ? "eye.slash" : "eye")
        }
        .accessibilityLabel(hideAmounts ? "顯示金額" : "隱藏金額")
    }

    private var refreshControl: some View {
        Button {
            guard isPro else {
                showQuoteLocked = true
                return
            }
            Task { await refreshQuotes() }
        } label: {
            Image(systemName: isRefreshing || !refreshConfirmed ? "arrow.clockwise" : "checkmark")
                .foregroundStyle(isPro ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .symbolEffect(.rotate, options: .repeating, isActive: isRefreshing && !reduceMotion)
        }
        .disabled(isPro && (isRefreshing || refreshConfirmed))
        .accessibilityLabel(isPro ? (isRefreshing ? "更新中" : refreshConfirmed ? "已更新" : "更新現值") : "不支援股價自動更新")
    }

    private var addControl: some View {
        Button {
            if ProPreview.canAddAsset(count: portfolio.items.count, isPro: isPro) {
                showAdd = true
            } else {
                showAssetLimit = true
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(canAdd ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        .accessibilityLabel(canAdd ? "新增資產與負債" : "已記滿 \(ProPreview.freeAssetLimit) 筆")
    }

    private var canAdd: Bool {
        ProPreview.canAddAsset(count: portfolio.items.count, isPro: isPro)
    }

    private var settingsMenu: some View {
        Menu {
            previewChoice("付費版", chosen: !isFresh && isPro) { selectStored(pro: true) }
            previewChoice("免費版", chosen: !isFresh && !isPro) { selectStored(pro: false) }
            previewChoice("第一次使用", chosen: isFresh) { selectFirstUse() }
            Button("完整記錄") { showPaywall = true }
            Button("顏色設定") { showColors = true }
            Button("iCloud 備份") { showBackup = true }
            Button("補登過去月份") {
                guard isPro else {
                    showBackfillLocked = true
                    return
                }
                showBackfill = true
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("設定")
    }

    private var sortControl: some View {
        Menu {
            Picker("依據", selection: $sortKey) {
                Text("佔比").tag("share")
                Text("幣別").tag("currency")
                Text("名稱").tag("name")
                Text("預設").tag("stored")
            }
            Picker("方向", selection: $sortAscending) {
                Text("順序").tag(true)
                Text("逆序").tag(false)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("排序")
    }

    private func previewChoice(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if chosen {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func selectStored(pro: Bool) {
        if !isFresh, isPro == pro { return }
        if isFresh {
            portfolio.endFirstUse()
            isFresh = false
        }
        isPro = pro
    }

    private func selectFirstUse() {
        guard !isFresh else { return }
        portfolio.beginFirstUse()
        isFresh = true
    }

    private func save(_ item: AssetItem) {
        saveAsset(item, portfolio: portfolio, groups: groups, exposureOnly: exposureOnly, isPro: isPro)
    }

    private func refreshQuotes() async {
        guard isPro else { return }
        let targets = portfolio.items.filter(\.canRefreshQuote)
        let hasUsd = portfolio.items.contains { $0.currency == .usd }
        guard !targets.isEmpty || hasUsd else { return }
        isRefreshing = true
        let symbolMap = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.symbol) })
        async let fetchedQuotes = QuoteClient.fetchAll(symbols: symbolMap)
        async let fetchedRate: Decimal? = hasUsd ? try? await QuoteClient.fetchUsdTwd() : nil
        let quotes = await fetchedQuotes
        let rate = await fetchedRate
        portfolio.applyQuotes(quotes)
        if let rate { portfolio.applyUsdTwd(rate) }
        isRefreshing = false
        let quotesOk = targets.isEmpty || quotes.count == targets.count
        let rateOk = !hasUsd || rate != nil
        guard quotesOk && rateOk else {
            showQuoteError = true
            return
        }
        refreshConfirmed = true
        try? await Task.sleep(for: .seconds(3))
        refreshConfirmed = false
    }
}

func saveAsset(
    _ item: AssetItem,
    portfolio: Portfolio,
    groups: AssetGroups,
    exposureOnly: Bool,
    isPro: Bool
) {
    let isNew = !portfolio.items.contains { $0.id == item.id }
    if isNew, !ProPreview.canAddAsset(count: portfolio.items.count, isPro: isPro) { return }
    portfolio.upsert(item)
    withAnimation {
        if exposureOnly {
            groups.expandedKinds.insert(item.kind)
            AssetListMemory.exposureKinds = groups.expandedKinds
            return
        }
        groups.openGroupIDs.insert(assetGroupID(item.kind, groups: groups))
    }
}

/// Bucket id the list is showing this kind under, including a merged header.
private func assetGroupID(_ kind: AssetKind, groups: AssetGroups) -> String {
    if groups.netMerged { return AssetKind.original.rawValue }
    if groups.assetMerged, kind != .debt { return AssetKind.original.rawValue }
    let pooled = kind == .original || kind == .leverage || kind == .cash
    if groups.liquidMerged, pooled { return AssetKind.original.rawValue }
    if groups.stocksMerged, kind == .original || kind == .leverage { return AssetKind.original.rawValue }
    return kind.rawValue
}

private struct CircleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct CapsuleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func preferSideColumn() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            self.axisBehavior(.verticalPreferred)
        } else {
            self
        }
    }
}

private struct AssetMenuBar<Bar: View>: ViewModifier {
    var isShown: Bool
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isShown {
                bar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
}
