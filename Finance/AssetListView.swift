import SwiftUI
import UIKit

struct AssetListView: View {
    static let restingTopInset: CGFloat = 44
    var showsChrome = true
    var topInset = restingTopInset
    /// Exposure lens keeps 原／槓／現. Net worth groups by `grouping`.
    var exposureOnly = false
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage("assetNetGrouping") private var grouping: AssetGrouping = .overview
    @AppStorage("assetNetOpenGroups") private var openGroupsRaw = ""
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var addKind: AssetKind = .original
    @State private var showTargets = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var expandedKinds: Set<AssetKind>
    @ScaledMetric(relativeTo: .title3) private var collapsedTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var expandedTitleSize: CGFloat = 15

    init(showsChrome: Bool = true, topInset: CGFloat = restingTopInset, exposureOnly: Bool = false) {
        self.showsChrome = showsChrome
        self.topInset = topInset
        self.exposureOnly = exposureOnly
        _expandedKinds = State(initialValue: exposureOnly ? AssetListMemory.exposureKinds : [])
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
                ForEach(grouping.buckets) { bucketSection($0) }
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
            if wasExposure { AssetListMemory.exposureKinds = expandedKinds }
            if isExposure { expandedKinds = AssetListMemory.exposureKinds }
        }
        .onDisappear(perform: persistGroups)
    }

    private var visibleKinds: [AssetKind] { [.original, .leverage, .cash] }

    private var openGroups: Set<String> {
        Set(openGroupsRaw.split(separator: ",").map(String.init))
    }

    private func headerColor(open: Bool) -> Color {
        open ? .secondary : .white
    }

    private func headerLabelFont(open: Bool, weight: Font.Weight, anchor: UnitPoint) -> ScalingFont {
        ScalingFont(
            base: collapsedTitleSize,
            scale: open ? expandedTitleSize / collapsedTitleSize : 1,
            weight: weight,
            anchor: anchor
        )
    }

    private func bucketSection(_ bucket: AssetBucket) -> some View {
        let open = openGroups.contains(grouping.storageID(for: bucket))
        return Section {
            if open { rowsOrEmpty(items(in: bucket)) }
        } header: {
            groupHeader(bucket.title, open: open, amount: amount(of: bucket)) {
                toggle(bucket)
            }
        }
    }

    private func items(in bucket: AssetBucket) -> [AssetItem] {
        bucket.kinds.flatMap { portfolio.items(for: $0) }
    }

    private func amount(of bucket: AssetBucket) -> Decimal {
        bucket.kinds.reduce(0) { $0 + portfolio.amount(for: $1) }
    }

    private func kindSection(_ kind: AssetKind) -> some View {
        Section {
            kindItems(kind)
        } header: {
            kindHeader(kind)
        }
    }

    private func kindHeader(_ kind: AssetKind) -> some View {
        let open = expandedKinds.contains(kind)
        return groupHeader(kind.title, open: open, amount: portfolio.amount(for: kind)) {
            toggle(kind)
        }
    }

    private func groupHeader(
        _ title: String,
        open: Bool,
        amount: Decimal,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(title)
                    .modifier(headerLabelFont(open: open, weight: .semibold, anchor: .leading))
                    .foregroundStyle(headerColor(open: open))
                Spacer()
                Text(MoneyFormat.string(amount, hidden: hideAmounts))
                    .modifier(headerLabelFont(open: open, weight: .regular, anchor: .trailing))
                    .monospacedDigit()
                    .foregroundStyle(headerColor(open: open))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(open ? "收合" : "展開")
        .textCase(nil)
    }

    @ViewBuilder
    private func kindItems(_ kind: AssetKind) -> some View {
        if expandedKinds.contains(kind) {
            rowsOrEmpty(portfolio.items(for: kind))
        }
    }

    @ViewBuilder
    private func rowsOrEmpty(_ rows: [AssetItem]) -> some View {
        if rows.isEmpty {
            Text("尚無紀錄")
                .foregroundStyle(.secondary)
        } else {
            assetRows(rows)
        }
    }

    private func assetRows(_ rows: [AssetItem]) -> some View {
        ForEach(rows) { item in
            Button { editing = item } label: {
                AssetRow(item: item, hideAmounts: hideAmounts)
            }
            .foregroundStyle(.primary)
        }
        .onDelete { portfolio.delete(rows, at: $0) }
    }

    private var menuBar: some View {
        HStack {
            hideButton
            if !exposureOnly { groupingMenu }
            Spacer(minLength: 16)
            trailingCluster
        }
    }

    private var groupingMenu: some View {
        Menu {
            Picker("分組", selection: $grouping) {
                ForEach(AssetGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(grouping.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .modifier(CapsuleGlass())
        .accessibilityLabel("分組，\(grouping.title)")
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
        guard exposureOnly else { return }
        AssetListMemory.exposureKinds = expandedKinds
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

    private func toggle(_ bucket: AssetBucket) {
        let id = grouping.storageID(for: bucket)
        var next = openGroups
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        withAnimation { openGroupsRaw = next.sorted().joined(separator: ",") }
    }

    private func saveItem(_ item: AssetItem) {
        portfolio.upsert(item)
        if exposureOnly {
            expandedKinds.insert(item.kind)
            persistGroups()
            return
        }
        guard let bucket = grouping.buckets.first(where: { $0.kinds.contains(item.kind) }) else { return }
        var next = openGroups
        next.insert(grouping.storageID(for: bucket))
        openGroupsRaw = next.sorted().joined(separator: ",")
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
