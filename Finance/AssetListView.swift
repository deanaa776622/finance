import SwiftUI
import UIKit

struct AssetListView: View {
    static let restingTopInset: CGFloat = 44
    var showsChrome = true
    var topInset = restingTopInset
    /// Exposure lens keeps 原／槓／現. Net worth keeps every kind.
    var exposureOnly = false
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var addKind: AssetKind = .original
    @State private var showTargets = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var expandedKinds: Set<AssetKind>
    @State private var assetsOpen: Bool
    @State private var liquidOpen: Bool
    @State private var stocksOpen: Bool
    @ScaledMetric(relativeTo: .title3) private var collapsedTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var nestedTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var expandedTitleSize: CGFloat = 15

    init(showsChrome: Bool = true, topInset: CGFloat = restingTopInset, exposureOnly: Bool = false) {
        self.showsChrome = showsChrome
        self.topInset = topInset
        self.exposureOnly = exposureOnly
        let saved = AssetListMemory.groups(exposure: exposureOnly)
        _expandedKinds = State(initialValue: saved.kinds)
        _assetsOpen = State(initialValue: saved.assetsOpen)
        _liquidOpen = State(initialValue: saved.liquidOpen)
        _stocksOpen = State(initialValue: saved.stocksOpen)
    }

    var body: some View {
        List {
            if let refreshMessage {
                Text(refreshMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if exposureOnly {
                ForEach(visibleKinds) { kindSection($0) }
            } else {
                Section {
                    if assetsOpen {
                        liquidGroup
                        kindBlock(.realEstate, depth: 1)
                    }
                } header: {
                    groupHeader("資產", open: assetsOpen, amount: assetTotal, depth: 0) {
                        withAnimation { assetsOpen.toggle() }
                        persistGroups()
                    }
                }
                kindSection(.debt)
            }
        }
        .contentMargins(.top, topInset, for: .scrollContent)
        .scrollEdgeFade(edges: .bottom)
        .navigationTitle(showsChrome ? "資產" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(AssetMenuBar(isShown: showsChrome) { menuBar })
        .sheet(isPresented: $showAdd) {
            AssetEditor(item: nil, defaultKind: addKind, onSave: saveItem)
        }
        .sheet(item: $editing) { item in
            AssetEditor(item: item, onSave: saveItem, onDelete: {
                portfolio.delete(ids: [item.id])
            })
        }
        .sheet(isPresented: $showTargets) {
            TargetEditor()
        }
        .onChange(of: exposureOnly) { wasExposure, isExposure in
            AssetListMemory.save(
                exposure: wasExposure,
                assetsOpen: assetsOpen,
                liquidOpen: liquidOpen,
                stocksOpen: stocksOpen,
                kinds: expandedKinds
            )
            let next = AssetListMemory.groups(exposure: isExposure)
            assetsOpen = next.assetsOpen
            liquidOpen = next.liquidOpen
            stocksOpen = next.stocksOpen
            expandedKinds = next.kinds
        }
        .onDisappear(perform: persistGroups)
    }

    private var visibleKinds: [AssetKind] { [.original, .leverage, .cash] }

    private var assetKinds: [AssetKind] { [.original, .leverage, .cash, .realEstate] }

    private var assetTotal: Decimal {
        assetKinds.reduce(0) { $0 + portfolio.amount(for: $1) }
    }

    private var stockTotal: Decimal {
        portfolio.amount(for: .original) + portfolio.amount(for: .leverage)
    }

    private var liquidTotal: Decimal {
        stockTotal + portfolio.amount(for: .cash)
    }

    private func headerColor(open: Bool) -> Color {
        open ? .secondary : .white
    }

    private func headerLabelFont(open: Bool, nested: Bool, weight: Font.Weight, anchor: UnitPoint) -> ScalingFont {
        let base = nested ? nestedTitleSize : collapsedTitleSize
        return ScalingFont(base: base, scale: open ? expandedTitleSize / base : 1, weight: weight, anchor: anchor)
    }

    @ViewBuilder
    private var liquidGroup: some View {
        groupHeader("流動資產", open: liquidOpen, amount: liquidTotal, depth: 1) {
            withAnimation { liquidOpen.toggle() }
            persistGroups()
        }
        if liquidOpen {
            stockGroup
            kindBlock(.cash, depth: 2)
        }
    }

    @ViewBuilder
    private var stockGroup: some View {
        groupHeader("股票", open: stocksOpen, amount: stockTotal, depth: 2) {
            withAnimation { stocksOpen.toggle() }
            persistGroups()
        }
        if stocksOpen {
            kindBlock(.original, depth: 3)
            kindBlock(.leverage, depth: 3)
        }
    }

    private func kindSection(_ kind: AssetKind) -> some View {
        Section {
            kindItems(kind, depth: 0)
        } header: {
            kindHeader(kind, depth: 0)
        }
    }

    @ViewBuilder
    private func kindBlock(_ kind: AssetKind, depth: Int) -> some View {
        kindHeader(kind, depth: depth)
        kindItems(kind, depth: depth)
    }

    private func kindHeader(_ kind: AssetKind, depth: Int) -> some View {
        let open = expandedKinds.contains(kind)
        return groupHeader(kind.title, open: open, amount: portfolio.amount(for: kind), depth: depth) {
            toggle(kind)
        }
    }

    private func groupHeader(
        _ title: String,
        open: Bool,
        amount: Decimal,
        depth: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(title)
                    .modifier(headerLabelFont(open: open, nested: depth > 0, weight: .semibold, anchor: .leading))
                    .foregroundStyle(headerColor(open: open))
                Spacer()
                Text(MoneyFormat.string(amount, hidden: hideAmounts))
                    .modifier(headerLabelFont(open: open, nested: depth > 0, weight: .regular, anchor: .trailing))
                    .monospacedDigit()
                    .foregroundStyle(headerColor(open: open))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(depth) * 12)
        .accessibilityLabel(title)
        .accessibilityHint(open ? "收合" : "展開")
        .textCase(nil)
    }

    @ViewBuilder
    private func kindItems(_ kind: AssetKind, depth: Int) -> some View {
        let rows = portfolio.items(for: kind)
        if expandedKinds.contains(kind) {
            let inset: CGFloat = depth == 0 ? 0 : CGFloat(depth) * 12 + 16
            if rows.isEmpty {
                Text("尚無紀錄")
                    .foregroundStyle(.secondary)
                    .padding(.leading, inset)
            } else {
                ForEach(rows) { item in
                    Button { editing = item } label: {
                        AssetRow(item: item, hideAmounts: hideAmounts)
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, inset)
                }
                .onDelete { portfolio.delete(rows, at: $0) }
            }
        }
    }

    private var menuBar: some View {
        HStack {
            hideButton
            Spacer(minLength: 16)
            trailingCluster
        }
    }

    private var hideButton: some View {
        Button {
            hideAmounts.toggle()
        } label: {
            Image(systemName: hideAmounts ? "eye.slash" : "eye")
        }
        .accessibilityLabel(hideAmounts ? "顯示金額" : "隱藏金額")
        .modifier(CircleGlass())
    }

    private var trailingCluster: some View {
        HStack(spacing: 0) {
            Group {
                if isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task { await refreshQuotes() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("更新現值")
                }
            }
            .frame(width: 44, height: 44)
            Button("目標配置") { showTargets = true }
                .padding(.horizontal, 4)
            Button {
                addKind = .original
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新增資產與負債")
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .modifier(CapsuleGlass())
    }

    private func persistGroups() {
        AssetListMemory.save(
            exposure: exposureOnly,
            assetsOpen: assetsOpen,
            liquidOpen: liquidOpen,
            stocksOpen: stocksOpen,
            kinds: expandedKinds
        )
    }

    private func toggle(_ kind: AssetKind) {
        withAnimation {
            if expandedKinds.contains(kind) {
                expandedKinds.remove(kind)
            } else {
                expandedKinds.insert(kind)
            }
        }
        persistGroups()
    }

    private func saveItem(_ item: AssetItem) {
        portfolio.upsert(item)
        expandedKinds.insert(item.kind)
        switch item.kind {
        case .original, .leverage:
            assetsOpen = true
            liquidOpen = true
            stocksOpen = true
        case .cash:
            assetsOpen = true
            liquidOpen = true
        case .realEstate:
            assetsOpen = true
        case .debt:
            break
        }
        persistGroups()
    }

    private func refreshQuotes() async {
        let targets = portfolio.items.filter(\.canRefreshQuote)
        let hasUsd = portfolio.items.contains { $0.currency == .usd }
        guard !targets.isEmpty || hasUsd else {
            refreshMessage = "沒有可更新的持股"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let quotes = targets.isEmpty ? [:] : await QuoteClient.fetchAll(
            symbols: Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.symbol) })
        )
        portfolio.applyQuotes(quotes)
        let rate = hasUsd ? try? await QuoteClient.fetchUsdTwd() : nil
        if let rate { portfolio.applyUsdTwd(rate) }
        refreshMessage = statusAfterRefresh(quoteCount: quotes.count, attemptedQuotes: !targets.isEmpty, rateUpdated: rate != nil)
    }

    private func statusAfterRefresh(quoteCount: Int, attemptedQuotes: Bool, rateUpdated: Bool) -> String {
        if quoteCount > 0, rateUpdated { return "已更新 \(quoteCount) 筆現值與匯率" }
        if quoteCount > 0 { return "已更新 \(quoteCount) 筆現值" }
        if rateUpdated { return attemptedQuotes ? "現值未改，已更新匯率" : "已更新匯率" }
        return attemptedQuotes ? "更新失敗，現值未改" : "匯率更新失敗"
    }
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

/// Scales a fixed line box. Animating `Font` re-anchors the baseline when the spring ends.
private struct ScalingFont: ViewModifier {
    var base: CGFloat
    var scale: CGFloat
    var weight: Font.Weight
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .font(.system(size: base, weight: weight))
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(scale, anchor: anchor)
            .frame(height: lineHeight * scale, alignment: .center)
    }

    private var lineHeight: CGFloat {
        UIFont.systemFont(ofSize: base, weight: weight == .semibold ? .semibold : .regular).lineHeight
    }
}

private struct AssetRow: View {
    let item: AssetItem
    var hideAmounts = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                    Text(item.currency.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.kind == .leverage, let multiple = item.leverageMultiple {
                        Text(String(format: "%g×", multiple))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if item.usesSharePrice, let shares = item.shares, let price = item.price {
                    Text(hideAmounts ? "••••" : "\(NumberParse.grouped(shares)) 股 · \(NumberParse.price(price))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(MoneyFormat.string(item.twdValue, hidden: hideAmounts))
                .monospacedDigit()
                .foregroundStyle(item.kind == .debt ? .secondary : .primary)
        }
    }
}

#Preview {
    NavigationStack {
        AssetListView()
            .environment(Portfolio(items: [
                AssetItem(
                    name: "0050",
                    kind: .original,
                    amount: 0,
                    usesSharePrice: true,
                    shares: 20_000,
                    price: 190
                ),
                AssetItem(name: "活存", kind: .cash, amount: 300_000),
            ]))
    }
}
