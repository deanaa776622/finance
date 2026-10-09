import SwiftUI

struct AssetListView: View {
    static let restingTopInset: CGFloat = 44
    var showsChrome = true
    var topInset = restingTopInset
    /// Exposure lens keeps 原／槓／現. Net worth groups by `grouping`.
    var exposureOnly = false
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage("assetNetGrouping") private var grouping: AssetGrouping = .overview
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var addKind: AssetKind = .original
    @State private var showTargets = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var expandedKinds: Set<AssetKind>
    @State private var openGroupIDs: Set<String>
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20

    init(showsChrome: Bool = true, topInset: CGFloat = restingTopInset, exposureOnly: Bool = false) {
        self.showsChrome = showsChrome
        self.topInset = topInset
        self.exposureOnly = exposureOnly
        _expandedKinds = State(initialValue: exposureOnly ? AssetListMemory.exposureKinds : [])
        _openGroupIDs = State(initialValue: AssetListMemory.netOpenGroups)
    }

    var body: some View {
        List {
            if let refreshMessage {
                Text(refreshMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if exposureOnly {
                ForEach(visibleKinds) { kind in
                    Section {
                        kindItems(kind)
                    } header: {
                        kindHeader(kind)
                    }
                }
            } else {
                ForEach(grouping.buckets) { bucket in
                    Section {
                        bucketItems(bucket)
                    } header: {
                        bucketHeader(bucket)
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.bottom, showsChrome ? 64 : 0, for: .scrollContent)
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

    private func headerColor(open: Bool) -> Color {
        open ? .secondary : .white
    }

    private func bucketHeader(_ bucket: AssetBucket) -> some View {
        let open = openGroupIDs.contains(grouping.storageID(for: bucket))
        return groupHeader(bucket.title, open: open, amount: amount(of: bucket)) {
            toggle(bucket)
        }
    }

    @ViewBuilder
    private func bucketItems(_ bucket: AssetBucket) -> some View {
        if openGroupIDs.contains(grouping.storageID(for: bucket)) {
            rowsOrEmpty(items(in: bucket))
        }
    }

    private func items(in bucket: AssetBucket) -> [AssetItem] {
        bucket.kinds.flatMap { portfolio.items(for: $0) }
    }

    private func amount(of bucket: AssetBucket) -> Decimal {
        bucket.kinds.reduce(0) { $0 + portfolio.amount(for: $1) }
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
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(headerColor(open: open))
                Spacer()
                Text(MoneyFormat.string(amount, hidden: hideAmounts))
                    .font(.system(size: titleSize))
                    .monospacedDigit()
                    .foregroundStyle(headerColor(open: open))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 18, leading: 32, bottom: 8, trailing: 32))
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemGroupedBackground))
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.rowPadding)
                .listRowInsets(Self.cardInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(GroupCardBackground(isFirst: true, isLast: true))
        } else {
            assetRows(rows)
        }
    }

    private static let cardInsets = EdgeInsets(
        top: 0,
        leading: GroupCardBackground.inset,
        bottom: 0,
        trailing: GroupCardBackground.inset
    )
    private static let rowPadding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

    private func assetRows(_ rows: [AssetItem]) -> some View {
        ForEach(rows) { item in
            let isFirst = item.id == rows.first?.id
            let isLast = item.id == rows.last?.id
            Button { editing = item } label: {
                AssetRow(item: item, hideAmounts: hideAmounts)
                    .padding(Self.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .listRowInsets(Self.cardInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(GroupCardBackground(isFirst: isFirst, isLast: isLast))
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
        withAnimation {
            if openGroupIDs.contains(id) {
                openGroupIDs.remove(id)
            } else {
                openGroupIDs.insert(id)
            }
        }
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func saveItem(_ item: AssetItem) {
        portfolio.upsert(item)
        if exposureOnly {
            withAnimation { _ = expandedKinds.insert(item.kind) }
            persistGroups()
            return
        }
        guard let bucket = grouping.buckets.first(where: { $0.kinds.contains(item.kind) }) else { return }
        withAnimation { _ = openGroupIDs.insert(grouping.storageID(for: bucket)) }
        AssetListMemory.netOpenGroups = openGroupIDs
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

private struct GroupCardBackground: View {
    var isFirst: Bool
    var isLast: Bool
    static let radius: CGFloat = 26
    static let inset: CGFloat = 16

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Self.radius : 0,
            bottomLeadingRadius: isLast ? Self.radius : 0,
            bottomTrailingRadius: isLast ? Self.radius : 0,
            topTrailingRadius: isFirst ? Self.radius : 0,
            style: .continuous
        )
        .fill(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .padding(.leading, Self.inset)
            }
        }
        .padding(.horizontal, Self.inset)
        .allowsHitTesting(false)
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
