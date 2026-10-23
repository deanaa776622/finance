import SwiftUI

struct AssetListView: View {
    /// Pulls the chart up into the lower edge of the 40pt top fade.
    static let restingTopInset: CGFloat = 32
    var showsChrome = true
    var topInset = restingTopInset
    /// Exposure lens keeps 原／槓／現. Net worth lists every kind.
    var exposureOnly = false
    var groups = AssetGroups()
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var addKind: AssetKind = .original
    @State private var showColors = false
    @State private var isRefreshing = false
    @State private var refreshConfirmed = false
    @State private var showQuoteError = false
    @State private var collapsingLiquid = false
    @State private var collapsingAsset = false
    @State private var collapsingNet = false
    @State private var linkCollapsed = false
    @State private var listGlobalOrigin: CGPoint = .zero
    @State private var linkOriginal: CGRect?
    @State private var linkLeverage: CGRect?
    /// Glyph box of the 原型 title, so the line can start at the top of those characters.
    @State private var linkTitle: CGRect?
    /// Glyph box of the 槓桿 title. A collapsed line ends on its bottom edge.
    @State private var linkLeverageTitle: CGRect?
    /// Glyph box of the 現金 title. The cash line ends on its bottom edge.
    @State private var linkCashTitle: CGRect?
    /// Glyph box of the 實體 title. The asset line ends on its bottom edge.
    @State private var linkRealTitle: CGRect?
    /// Glyph box of the 負債 title. The net-worth line ends on its bottom edge.
    @State private var linkDebtTitle: CGRect?
    /// Global maxY of asset rows under 原型 / 槓桿, so the line can run to the last one.
    @State private var linkRowMaxY: [String: CGFloat] = [:]
    /// Bumped when the pair merges or splits, so row bottoms are measured again after the list shifts.
    @State private var linkEpoch = 0
    @State private var linkRowEpoch: [String: Int] = [:]
    @State private var pendingDelete: [AssetItem] = []
    @AppStorage("assetSortKey") private var sortKey = "stored"
    @AppStorage("assetSortAscending") private var sortAscending = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        showsChrome: Bool = true,
        topInset: CGFloat = restingTopInset,
        exposureOnly: Bool = false,
        groups: AssetGroups = AssetGroups()
    ) {
        self.showsChrome = showsChrome
        self.topInset = topInset
        self.exposureOnly = exposureOnly
        self.groups = groups
    }

    var body: some View {
        List {
            if exposureOnly {
                TargetEditor()
                    .frame(height: GroupTrendChart.bandHeight, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 8, trailing: 32))
                    .listRowSeparator(.hidden)
                    .listRowBackground(palette.ground)
            } else if showsTrend {
                GroupTrendChart(buckets: shownBuckets)
                    .equatable()
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 8, trailing: 32))
                    .listRowSeparator(.hidden)
                    .listRowBackground(palette.ground)
            }
            ForEach(shownBuckets) { bucket in
                Section {
                    bucketItems(bucket)
                } header: {
                    bucketHeader(bucket)
                }
                .opacity(linkBucketFades(bucket.kinds) ? 0 : 1)
                .transition(
                    bucket.kinds == [.leverage] || bucket.kinds == [.cash] || bucket.kinds == [.realEstate] || bucket.kinds == [.debt]
                        ? .move(edge: .top).combined(with: .opacity)
                        : .identity
                )
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(palette.ground)
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.bottom, showsChrome ? 64 : 0, for: .scrollContent)
        .onGeometryChange(for: CGPoint.self) {
            let frame = $0.frame(in: .global)
            return CGPoint(x: frame.minX, y: frame.minY)
        } action: { listGlobalOrigin = $0 }
        .overlay(alignment: .topLeading) { stockLinkLayer }
        .scrollEdgeFade(edges: .bottom)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: groups.stocksMerged)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: groups.liquidMerged)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: groups.assetMerged)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: groups.netMerged)
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
        .sheet(isPresented: $showColors) {
            ColorSettingsView()
        }
        .alert(deleteTitle, isPresented: showDeleteConfirm) {
            Button("刪除", role: .destructive) {
                portfolio.delete(ids: pendingDelete.map(\.id))
                pendingDelete = []
            }
            Button("取消", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("刪除後會從清單移除。")
        }
        .alert("無法更新現值", isPresented: $showQuoteError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("報價暫時取不到，請稍後再試。")
        }
        .onDisappear(perform: persistGroups)
    }

    private var showDeleteConfirm: Binding<Bool> {
        Binding(
            get: { !pendingDelete.isEmpty },
            set: { if !$0 { pendingDelete = [] } }
        )
    }

    private var deleteTitle: String {
        guard pendingDelete.count == 1, let item = pendingDelete.first else {
            return "刪除這 \(pendingDelete.count) 筆？"
        }
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "刪除這筆資產？" : "刪除「\(name)」？"
    }

    private var baseBuckets: [AssetBucket] {
        let kinds: [AssetKind] = exposureOnly ? [.original, .leverage, .cash] : AssetKind.allCases
        return kinds.map { AssetBucket(id: $0.rawValue, title: $0.compactTitle, kinds: [$0]) }
    }

    private var showsTrend: Bool {
        shownBuckets.contains { bucket in
            portfolio.items.contains {
                bucket.kinds.contains($0.kind) && portfolio.histories[$0.id]?.isEmpty == false
            }
        }
    }

    private var shownBuckets: [AssetBucket] {
        if groups.netMerged, netJoinRange(baseBuckets) != nil {
            return bucketsMergingNetWorth(baseBuckets, merged: true)
        }
        if groups.assetMerged, assetJoinRange(baseBuckets) != nil {
            return bucketsMergingAssets(baseBuckets, merged: true)
        }
        if groups.liquidMerged, cashJoinAvailable {
            return bucketsMergingLiquid(baseBuckets, merged: true)
        }
        return bucketsMergingStocks(baseBuckets, merged: groups.stocksMerged)
    }

    /// 原型 sits directly above 槓桿, so a join line has somewhere to land.
    private var stockPairAvailable: Bool {
        let buckets = baseBuckets
        guard let original = buckets.firstIndex(where: { $0.kinds == [.original] }),
              let leverage = buckets.firstIndex(where: { $0.kinds == [.leverage] }) else { return false }
        return leverage == original + 1
    }

    /// 原型, 槓桿, then 現金, so the cash line can merge all three into 流動.
    private var cashJoinAvailable: Bool {
        let buckets = baseBuckets
        guard let original = buckets.firstIndex(where: { $0.kinds == [.original] }),
              let leverage = buckets.firstIndex(where: { $0.kinds == [.leverage] }),
              let cash = buckets.firstIndex(where: { $0.kinds == [.cash] }) else { return false }
        return leverage == original + 1 && cash == leverage + 1
    }

    /// 實體 sits under the original / leverage / cash groups, so they can fold into 資產.
    private var assetJoinAvailable: Bool {
        assetJoinRange(baseBuckets) != nil
    }

    /// 負債 sits under the asset groups, so they can fold into 總淨值.
    private var netJoinAvailable: Bool {
        netJoinRange(baseBuckets) != nil
    }

    @ViewBuilder
    private func bucketHeader(_ bucket: AssetBucket) -> some View {
        let header = GroupTitle(
            title: bucket.title,
            value: MoneyFormat.string(amount(of: bucket), hidden: hideAmounts),
            open: isOpen(bucket),
            titleFrame: { trackTitle(bucket, $0) }
        ) {
            toggleBucket(bucket)
        }
        .opacity(linkBucketFades(bucket.kinds) ? 0 : 1)
        .stockLinkHit(enabled: linkAction(for: bucket) != nil, margin: 24) { linkAction(for: bucket)?() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trackLink(bucket, frame: $0) }
        if let title = linkActionTitle(bucket) {
            header.accessibilityAction(named: Text(title)) { linkAction(for: bucket)?() }.groupHeaderChrome()
        } else {
            header.groupHeaderChrome()
        }
    }

    @ViewBuilder
    private func bucketItems(_ bucket: AssetBucket) -> some View {
        if isOpen(bucket) {
            rowsOrEmpty(
                items(in: bucket),
                trackLink: tracksLinkRows(bucket) ? bucket.id : nil,
                onLink: linkAction(for: bucket)
            )
        }
    }

    private func items(in bucket: AssetBucket) -> [AssetItem] {
        items(in: bucket.kinds)
    }

    private func items(in kinds: [AssetKind]) -> [AssetItem] {
        sorted(kinds.flatMap { portfolio.items(for: $0) })
    }

    /// Order within the group on screen. Share uses that group's total.
    private func sorted(_ rows: [AssetItem]) -> [AssetItem] {
        let total = rows.reduce(Decimal.zero) { $0 + $1.twdValue }
        let ordered: [AssetItem]
        switch sortKey {
        case "share":
            ordered = rows.sorted { portion($0.twdValue, of: total) < portion($1.twdValue, of: total) }
        case "currency":
            ordered = rows.sorted { $0.currency.rawValue < $1.currency.rawValue }
        case "name":
            ordered = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default:
            ordered = rows
        }
        return sortAscending ? ordered : ordered.reversed()
    }

    private func amount(of bucket: AssetBucket) -> Decimal {
        amount(of: bucket.kinds)
    }

    private func amount(of kinds: [AssetKind]) -> Decimal {
        kinds.reduce(0) { partial, kind in
            let value = portfolio.amount(for: kind)
            if kind == .debt { return partial - value }
            return partial + value
        }
    }

    @ViewBuilder
    private func rowsOrEmpty(_ rows: [AssetItem], trackLink bucketID: String? = nil, onLink: (() -> Void)? = nil) -> some View {
        if rows.isEmpty {
            Text("尚無紀錄")
                .foregroundStyle(palette.quietInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.rowPadding)
                .stockLinkHit(enabled: onLink != nil, margin: 24) { onLink?() }
                .overlay(alignment: .bottom) {
                    if let bucketID {
                        rowBottomTracker("empty-\(bucketID)")
                    }
                }
                .listRowInsets(Self.cardInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(GroupCardBackground(isFirst: true, isLast: true))
        } else {
            assetRows(rows, trackLink: bucketID != nil, onLink: onLink)
        }
    }

    private static let cardInsets = EdgeInsets(
        top: 0,
        leading: GroupCardBackground.leading,
        bottom: 0,
        trailing: GroupCardBackground.inset
    )
    private static let rowPadding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

    private func assetRows(_ rows: [AssetItem], trackLink: Bool, onLink: (() -> Void)?) -> some View {
        let total = rows.reduce(Decimal.zero) { $0 + $1.twdValue }
        return ForEach(rows) { item in
            let isFirst = item.id == rows.first?.id
            let isLast = item.id == rows.last?.id
            Button { editing = item } label: {
                AssetRow(item: item, share: portion(item.twdValue, of: total), hideAmounts: hideAmounts)
                    .padding(Self.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink)
            .stockLinkHit(enabled: onLink != nil, margin: 24) { onLink?() }
            .overlay(alignment: .bottom) {
                if trackLink {
                    rowBottomTracker(item.id.uuidString)
                }
            }
            .listRowInsets(Self.cardInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(GroupCardBackground(isFirst: isFirst, isLast: isLast))
        }
        .onDelete { pendingDelete = $0.map { rows[$0] } }
    }

    /// Share of the amounts listed in this group. Absolutes, so a merged net-worth group still sums to 1.
    private func portion(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        let ratio = (value as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
        return min(1, max(0, ratio))
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
            sortMenu
            Button {
                Task { await refreshQuotes() }
            } label: {
                Image(systemName: isRefreshing || !refreshConfirmed ? "arrow.clockwise" : "checkmark")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .symbolEffect(.rotate, options: .repeating, isActive: isRefreshing && !reduceMotion)
            }
            .disabled(isRefreshing || refreshConfirmed)
            .accessibilityLabel(isRefreshing ? "更新中" : refreshConfirmed ? "已更新" : "更新現值")
            .frame(width: 44, height: 44)
            Menu {
                Button("顏色設定") { showColors = true }
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("設定")
            .frame(width: 44, height: 44)
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

    private var sortMenu: some View {
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
        .frame(width: 44, height: 44)
    }

    private func persistGroups() {
        if exposureOnly {
            AssetListMemory.exposureKinds = groups.expandedKinds
        } else {
            AssetListMemory.netOpenGroups = groups.openGroupIDs
        }
    }

    private func isOpen(_ bucket: AssetBucket) -> Bool {
        if exposureOnly {
            return bucket.kinds.contains { groups.expandedKinds.contains($0) }
        }
        return groups.openGroupIDs.contains(bucket.id)
    }

    private func toggleBucket(_ bucket: AssetBucket) {
        if exposureOnly {
            withAnimation {
                let open = isOpen(bucket)
                var next = groups.expandedKinds
                for kind in bucket.kinds {
                    if open { next.remove(kind) } else { next.insert(kind) }
                }
                groups.expandedKinds = next
            }
            persistGroups()
            return
        }
        toggle(bucket)
    }

    private func isLinkBucket(_ bucket: AssetBucket) -> Bool {
        guard stockPairAvailable else { return false }
        return bucket.kinds == [.original]
            || bucket.kinds == [.leverage]
            || bucket.kinds == [.original, .leverage]
    }

    private func tracksLinkRows(_ bucket: AssetBucket) -> Bool {
        if groups.netMerged { return bucket.kinds == [.original, .leverage, .cash, .realEstate, .debt] }
        if bucket.kinds == [.debt] { return netJoinAvailable && !groups.netMerged }
        if groups.assetMerged { return bucket.kinds == [.original, .leverage, .cash, .realEstate] }
        if bucket.kinds == [.realEstate] { return assetJoinAvailable && !groups.assetMerged }
        if groups.liquidMerged { return bucket.kinds == [.original, .leverage, .cash] }
        if bucket.kinds == [.cash] { return cashJoinAvailable && !groups.liquidMerged && !groups.assetMerged }
        if isLinkBucket(bucket) { return true }
        if let above = bucketAboveReal, above.id == bucket.id { return assetJoinAvailable && !groups.assetMerged }
        return false
    }

    private var bucketAboveReal: AssetBucket? {
        guard let index = shownBuckets.firstIndex(where: { $0.kinds == [.realEstate] }), index > 0 else { return nil }
        return shownBuckets[index - 1]
    }

    private func linkBucketFades(_ kinds: [AssetKind]) -> Bool {
        guard linkCollapsed else { return false }
        if kinds == [.leverage] { return true }
        if kinds == [.cash] { return collapsingLiquid || collapsingAsset || collapsingNet }
        if kinds == [.realEstate] { return collapsingAsset || collapsingNet }
        return collapsingNet && kinds == [.debt]
    }

    private func linkAction(for bucket: AssetBucket) -> (() -> Void)? {
        if groups.netMerged {
            return bucket.kinds == [.original, .leverage, .cash, .realEstate, .debt] ? splitNet : nil
        }
        if netJoinAvailable, bucket.kinds == [.debt] { return mergeNet }
        if groups.assetMerged {
            return bucket.kinds == [.original, .leverage, .cash, .realEstate] ? splitAssets : nil
        }
        if assetJoinAvailable, bucket.kinds == [.realEstate] { return mergeAssets }
        if groups.liquidMerged {
            return bucket.kinds == [.original, .leverage, .cash] ? splitLiquid : nil
        }
        if isLinkBucket(bucket) { return tapStockLink }
        if cashJoinAvailable, !groups.liquidMerged, bucket.kinds == [.cash] { return mergeLiquid }
        return nil
    }

    private func linkActionTitle(_ bucket: AssetBucket) -> String? {
        if groups.netMerged, bucket.kinds == [.original, .leverage, .cash, .realEstate, .debt] {
            return splitTitle(groups.netChildren, fallback: "分開總淨值")
        }
        if netJoinAvailable, bucket.kinds == [.debt] { return "合併為總淨值" }
        if groups.assetMerged, bucket.kinds == [.original, .leverage, .cash, .realEstate] { return assetSplitTitle }
        if assetJoinAvailable, bucket.kinds == [.realEstate] { return "合併為資產" }
        if groups.liquidMerged, bucket.kinds == [.original, .leverage, .cash] { return splitTitle(groups.liquidChildren, fallback: "分開為原型、槓桿與現金") }
        if groups.stocksMerged, bucket.kinds == [.original, .leverage] {
            return splitTitle(groups.stockChildren, fallback: "分開為原型與槓桿")
        }
        if isLinkBucket(bucket) { return "合併為股票" }
        if cashJoinAvailable, !groups.liquidMerged, bucket.kinds == [.cash] { return "合併為流動" }
        return nil
    }

    private var assetSplitTitle: String {
        splitTitle(groups.assetChildren, fallback: "分開資產")
    }

    private func splitTitle(_ children: [AssetChild], fallback: String) -> String {
        let names = children.map(\.title).joined(separator: "、")
        return names.isEmpty ? fallback : "分開為\(names)"
    }

    private func trackLink(_ bucket: AssetBucket, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            // Collapse moves this header; keeping the resting frame lets the line return on split.
            guard !linkCollapsed, !groups.stocksMerged, !groups.liquidMerged, !groups.assetMerged, !groups.netMerged else { return }
            linkLeverage = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] || bucket.kinds == [.original, .leverage, .cash, .realEstate] || bucket.kinds == [.original, .leverage, .cash, .realEstate, .debt] {
            linkOriginal = frame
        }
    }

    private func trackTitle(_ bucket: AssetBucket, _ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            guard !linkCollapsed, !groups.stocksMerged, !groups.liquidMerged, !groups.assetMerged, !groups.netMerged else { return }
            linkLeverageTitle = frame
        } else if bucket.kinds == [.cash] {
            guard !linkCollapsed, !groups.liquidMerged, !groups.assetMerged, !groups.netMerged else { return }
            linkCashTitle = frame
        } else if bucket.kinds == [.realEstate] {
            guard !linkCollapsed, !groups.assetMerged, !groups.netMerged else { return }
            linkRealTitle = frame
        } else if bucket.kinds == [.debt] {
            guard !linkCollapsed, !groups.netMerged else { return }
            linkDebtTitle = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] || bucket.kinds == [.original, .leverage, .cash, .realEstate] || bucket.kinds == [.original, .leverage, .cash, .realEstate, .debt] {
            linkTitle = frame
        }
    }

    private func rememberRowBottom(_ id: String, _ y: CGFloat) {
        guard y > 1 else { return }
        guard linkRowMaxY[id] != y || linkRowEpoch[id] != linkEpoch else { return }
        linkRowMaxY[id] = y
        linkRowEpoch[id] = linkEpoch
    }

    /// Sits on the row's bottom edge. A new identity after merge or split reads that edge again.
    private func rowBottomTracker(_ id: String) -> some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { rememberRowBottom(id, $0) }
            .id(linkEpoch)
    }

    private func measuredBottom(_ keys: Set<String>) -> CGFloat? {
        var bottom: CGFloat?
        for key in keys {
            guard linkRowEpoch[key] == linkEpoch, let y = linkRowMaxY[key] else { continue }
            bottom = max(bottom ?? y, y)
        }
        return bottom
    }

    private func rowKeys(for bucket: AssetBucket) -> Set<String> {
        let rows = items(in: bucket)
        if rows.isEmpty { return ["empty-\(bucket.id)"] }
        return Set(rows.map(\.id.uuidString))
    }

    /// From the top of the 原型 title. A collapsed group ends at the bottom of its title.
    private func linkSpan(from header: CGRect, title: CGRect? = nil, through other: CGRect?, endTitle: CGRect? = nil, rows: CGFloat? = nil) -> (x: CGFloat, top: CGFloat, height: CGFloat)? {
        let anchor = title ?? header
        let top = anchor.minY - listGlobalOrigin.y
        let end = endTitle?.maxY ?? other?.maxY ?? header.maxY
        var bottom = end - listGlobalOrigin.y
        if let rows {
            bottom = max(bottom, rows - listGlobalOrigin.y)
        }
        let height = bottom - top
        guard height > 1 else { return nil }
        return (anchor.minX - listGlobalOrigin.x - 16, top, height)
    }

    private var stockLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard stockPairAvailable, !groups.stocksMerged, !groups.liquidMerged, !groups.assetMerged, !groups.netMerged,
              let original = linkOriginal, let leverage = linkLeverage else { return nil }
        let rows = shownBuckets.first { $0.kinds == [.leverage] }.flatMap { listedKeys(for: $0) }.flatMap(measuredBottom)
        return linkSpan(from: original, title: linkTitle, through: leverage, endTitle: linkLeverageTitle, rows: rows)
    }

    private var stockStub: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard stockPairAvailable, groups.stocksMerged, !groups.netMerged, !collapsingNet, let original = linkOriginal else { return nil }
        let rows = shownBuckets.first { $0.kinds == [.original, .leverage] }.flatMap { listedKeys(for: $0) }.flatMap(measuredBottom)
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    /// Gray join from the group above 現金 down to 現金. Tap merges into 流動.
    private var cashLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard cashJoinAvailable, !groups.liquidMerged, !groups.assetMerged, !groups.netMerged, !linkCollapsed || collapsingLiquid,
              let cashTitle = linkCashTitle else { return nil }
        let top = cashAnchorMaxY + 8
        guard top > 1 else { return nil }
        var bottom = cashTitle.maxY
        if let cash = shownBuckets.first(where: { $0.kinds == [.cash] }),
           let keys = listedKeys(for: cash),
           let row = measuredBottom(keys) {
            bottom = max(bottom, row)
        }
        let height = bottom - top
        guard height > 1 else { return nil }
        return (cashTitle.minX - listGlobalOrigin.x - 16, top - listGlobalOrigin.y, height)
    }

    /// Bottom of 槓桿, or of 股票 once that pair is merged.
    private var cashAnchorMaxY: CGFloat {
        if groups.stocksMerged, let stockTitle = linkTitle {
            var top = stockTitle.maxY
            if let stock = shownBuckets.first(where: { $0.kinds == [.original, .leverage] }),
               let keys = listedKeys(for: stock),
               let row = measuredBottom(keys) {
                top = max(top, row)
            }
            return top
        }
        guard let leverageTitle = linkLeverageTitle else { return 0 }
        var top = leverageTitle.maxY
        if let leverage = shownBuckets.first(where: { $0.kinds == [.leverage] }),
           let keys = listedKeys(for: leverage),
           let row = measuredBottom(keys) {
            top = max(top, row)
        }
        return top
    }

    /// Gray join from the group above 實體 down through 實體. Tap merges them into 資產.
    private var realLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard assetJoinAvailable, !groups.assetMerged, !groups.netMerged, !linkCollapsed || collapsingAsset,
              let realTitle = linkRealTitle else { return nil }
        let top = realAnchorMaxY + 8
        guard top > 1 else { return nil }
        var bottom = realTitle.maxY
        if let real = shownBuckets.first(where: { $0.kinds == [.realEstate] }),
           let keys = listedKeys(for: real),
           let row = measuredBottom(keys) {
            bottom = max(bottom, row)
        }
        let height = bottom - top
        guard height > 1 else { return nil }
        return (realTitle.minX - listGlobalOrigin.x - 16, top - listGlobalOrigin.y, height)
    }

    private var realAnchorMaxY: CGFloat {
        guard let above = bucketAboveReal else { return 0 }
        let titleBottom = above.kinds == [.cash] ? (linkCashTitle?.maxY ?? 0) : (linkTitle?.maxY ?? 0)
        var top = titleBottom
        if let keys = listedKeys(for: above), let row = measuredBottom(keys) {
            top = max(top, row)
        }
        return top
    }

    private var assetLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard groups.assetMerged, !groups.netMerged, !collapsingNet, assetJoinAvailable, let original = linkOriginal else { return nil }
        let rows = shownBuckets.first { $0.kinds == [.original, .leverage, .cash, .realEstate] }.flatMap { listedKeys(for: $0) }.flatMap(measuredBottom)
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    private var liquidLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard groups.liquidMerged, !groups.netMerged, !collapsingNet, cashJoinAvailable, let original = linkOriginal else { return nil }
        let rows = shownBuckets.first { $0.kinds == [.original, .leverage, .cash] }.flatMap { listedKeys(for: $0) }.flatMap(measuredBottom)
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    /// Gray join from the group above 負債 down through 負債. Tap merges them into 總淨值.
    private var debtLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard netJoinAvailable, !groups.netMerged, !linkCollapsed || collapsingNet,
              let debtTitle = linkDebtTitle else { return nil }
        let top = debtAnchorMaxY + 8
        guard top > 1 else { return nil }
        var bottom = debtTitle.maxY
        if let debt = shownBuckets.first(where: { $0.kinds == [.debt] }),
           let keys = listedKeys(for: debt),
           let row = measuredBottom(keys) {
            bottom = max(bottom, row)
        }
        let height = bottom - top
        guard height > 1 else { return nil }
        return (debtTitle.minX - listGlobalOrigin.x - 16, top - listGlobalOrigin.y, height)
    }

    private var debtAnchorMaxY: CGFloat {
        guard let above = bucketAboveDebt else { return 0 }
        let titleBottom: CGFloat
        if above.kinds == [.cash] {
            titleBottom = linkCashTitle?.maxY ?? 0
        } else if above.kinds == [.realEstate] {
            titleBottom = linkRealTitle?.maxY ?? 0
        } else {
            titleBottom = linkTitle?.maxY ?? 0
        }
        var top = titleBottom
        if let keys = listedKeys(for: above), let row = measuredBottom(keys) {
            top = max(top, row)
        }
        return top
    }

    private var bucketAboveDebt: AssetBucket? {
        guard let index = shownBuckets.firstIndex(where: { $0.kinds == [.debt] }), index > 0 else { return nil }
        return shownBuckets[index - 1]
    }

    private var netLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard groups.netMerged, netJoinAvailable, let original = linkOriginal else { return nil }
        let rows = shownBuckets.first { $0.kinds == [.original, .leverage, .cash, .realEstate, .debt] }
            .flatMap { listedKeys(for: $0) }
            .flatMap(measuredBottom)
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    private func linkMark(_ line: (x: CGFloat, top: CGFloat, height: CGFloat), collapsed: Bool, color: Color) -> some View {
        StockLinkMark(x: line.x, top: line.top, height: line.height, collapsed: collapsed, color: color)
            .allowsHitTesting(false)
    }

    private var stockLinkLayer: some View {
        ZStack(alignment: .topLeading) {
            if groups.netMerged, let line = netLine {
                linkMark(line, collapsed: false, color: Color.primary.opacity(0.85))
            } else if collapsingNet {
                debtLinkMark
            } else if groups.assetMerged, let line = assetLine {
                linkMark(line, collapsed: false, color: Color.primary.opacity(0.85))
                debtLinkMark
            } else if groups.liquidMerged, let line = liquidLine {
                linkMark(line, collapsed: false, color: Color.primary.opacity(0.85))
                realLinkMark
                debtLinkMark
            } else if groups.stocksMerged, let stub = stockStub {
                linkMark(stub, collapsed: false, color: Color.primary.opacity(0.85))
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
                realLinkMark
                debtLinkMark
            } else {
                if let line = stockLine {
                    linkMark(line, collapsed: linkCollapsed, color: .secondary)
                }
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
                realLinkMark
                debtLinkMark
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var realLinkMark: some View {
        if let real = realLine {
            linkMark(real, collapsed: collapsingAsset && linkCollapsed, color: .secondary)
        }
    }

    @ViewBuilder
    private var debtLinkMark: some View {
        if let debt = debtLine {
            linkMark(debt, collapsed: collapsingNet && linkCollapsed, color: .secondary)
        }
    }

    private func tapStockLink() {
        if groups.stocksMerged { splitStocks() } else { mergeStocks() }
    }

    private func mergeStocks() {
        guard !linkCollapsed else { return }
        let joined = stockJoinBuckets()
        guard !joined.isEmpty else { return }
        groups.stockChildren = snapshot(joined)
        if reduceMotion {
            groups.stocksMerged = true
            linkEpoch += 1
            syncShell(groups.stockChildren, kinds: [.original, .leverage])
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
        } completion: {
            withAnimation(.smooth(duration: 0.45)) {
                groups.stocksMerged = true
                linkCollapsed = false
                linkEpoch += 1
                syncShell(groups.stockChildren, kinds: [.original, .leverage])
            }
        }
    }

    private func splitStocks() {
        guard !linkCollapsed else { return }
        if reduceMotion {
            undoStockMerge()
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            undoStockMerge()
            linkEpoch += 1
        }
    }

    private func mergeLiquid() {
        guard !linkCollapsed, !groups.liquidMerged, cashJoinAvailable else { return }
        let joined = liquidJoinBuckets()
        guard !joined.isEmpty else { return }
        groups.liquidChildren = snapshot(joined)
        groups.liquidHeldStocks = groups.stocksMerged
        if reduceMotion {
            groups.liquidMerged = true
            groups.stocksMerged = false
            linkEpoch += 1
            syncShell(groups.liquidChildren, kinds: [.original, .leverage, .cash])
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
            collapsingLiquid = true
        } completion: {
            guard collapsingLiquid else { return }
            withAnimation(.smooth(duration: 0.45)) {
                groups.liquidMerged = true
                groups.stocksMerged = false
                linkCollapsed = false
                collapsingLiquid = false
                linkEpoch += 1
                syncShell(groups.liquidChildren, kinds: [.original, .leverage, .cash])
            }
        }
    }

    private func splitLiquid() {
        guard !linkCollapsed, groups.liquidMerged else { return }
        if reduceMotion {
            undoLiquidMerge()
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            undoLiquidMerge()
            linkEpoch += 1
        }
    }

    private func mergeNet() {
        guard !linkCollapsed, !groups.netMerged, netJoinAvailable else { return }
        rememberNetChildren()
        if reduceMotion {
            finishNetMerge()
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
            collapsingNet = true
        } completion: {
            guard collapsingNet else { return }
            withAnimation(.smooth(duration: 0.45)) {
                finishNetMerge()
                linkCollapsed = false
                collapsingNet = false
            }
        }
    }

    private func finishNetMerge() {
        groups.netMerged = true
        groups.stocksMerged = false
        groups.liquidMerged = false
        groups.assetMerged = false
        linkEpoch += 1
        syncShell(groups.netChildren, kinds: [.original, .leverage, .cash, .realEstate, .debt])
    }

    private func splitNet() {
        guard !linkCollapsed, groups.netMerged else { return }
        if reduceMotion {
            restoreNetChildren()
            groups.netMerged = false
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            restoreNetChildren()
            groups.netMerged = false
            linkEpoch += 1
        }
    }

    private func rememberNetChildren() {
        let shown = shownBuckets
        guard let range = netJoinRange(shown) else { return }
        groups.netHeldStocks = groups.stocksMerged
        groups.netHeldLiquid = groups.liquidMerged
        groups.netHeldAsset = groups.assetMerged
        groups.netChildren = snapshot(Array(shown[range]))
    }

    private func restoreNetChildren() {
        restore(groups.netChildren)
        groups.stocksMerged = groups.netHeldStocks
        groups.liquidMerged = groups.netHeldLiquid
        groups.assetMerged = groups.netHeldAsset
    }

    private func mergeAssets() {
        guard !linkCollapsed, !groups.assetMerged, assetJoinAvailable else { return }
        rememberAssetChildren()
        if reduceMotion {
            groups.assetMerged = true
            groups.stocksMerged = false
            groups.liquidMerged = false
            linkEpoch += 1
            syncAssetOpen()
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
            collapsingAsset = true
        } completion: {
            guard collapsingAsset else { return }
            withAnimation(.smooth(duration: 0.45)) {
                groups.assetMerged = true
                groups.stocksMerged = false
                groups.liquidMerged = false
                linkCollapsed = false
                collapsingAsset = false
                linkEpoch += 1
                syncAssetOpen()
            }
        }
    }

    private func splitAssets() {
        guard !linkCollapsed, groups.assetMerged else { return }
        if reduceMotion {
            restoreAssetChildren()
            groups.assetMerged = false
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            restoreAssetChildren()
            groups.assetMerged = false
            linkEpoch += 1
        }
    }

    private func rememberAssetChildren() {
        let shown = shownBuckets
        guard let range = assetJoinRange(shown) else { return }
        groups.assetHeldStocks = groups.stocksMerged
        groups.assetHeldLiquid = groups.liquidMerged
        groups.assetChildren = shown[range].map { bucket in
            AssetChild(
                id: bucket.id,
                title: bucket.title,
                kinds: bucket.kinds,
                storageID: bucket.id,
                open: isOpen(bucket)
            )
        }
    }

    private func restoreAssetChildren() {
        restore(groups.assetChildren)
        groups.stocksMerged = groups.assetHeldStocks
        groups.liquidMerged = groups.assetHeldLiquid
    }

    private func syncAssetOpen() {
        syncShell(groups.assetChildren, kinds: [.original, .leverage, .cash, .realEstate])
    }

    private func undoStockMerge() {
        restore(groups.stockChildren)
        groups.stocksMerged = false
    }

    private func undoLiquidMerge() {
        restore(groups.liquidChildren)
        groups.stocksMerged = groups.liquidHeldStocks
        groups.liquidMerged = false
    }

    private func snapshot(_ buckets: [AssetBucket]) -> [AssetChild] {
        buckets.map { bucket in
            AssetChild(
                id: bucket.id,
                title: bucket.title,
                kinds: bucket.kinds,
                storageID: bucket.id,
                open: isOpen(bucket)
            )
        }
    }

    private func stockJoinBuckets() -> [AssetBucket] {
        let shown = shownBuckets
        guard let original = shown.firstIndex(where: { $0.kinds == [.original] }),
              let leverage = shown.firstIndex(where: { $0.kinds == [.leverage] }),
              leverage == original + 1 else { return [] }
        return Array(shown[original...leverage])
    }

    private func liquidJoinBuckets() -> [AssetBucket] {
        let shown = shownBuckets
        guard let cash = shown.firstIndex(where: { $0.kinds == [.cash] }) else { return [] }
        let cluster: Set<AssetKind> = [.original, .leverage]
        var head = cash
        while head > 0 {
            let kinds = shown[head - 1].kinds
            guard !kinds.isEmpty, kinds.allSatisfy(cluster.contains) else { break }
            head -= 1
        }
        guard head < cash else { return [] }
        return Array(shown[head...cash])
    }

    /// Rows on screen under an open group. A merged group lists every asset it folded in.
    private func listedKeys(for bucket: AssetBucket) -> Set<String>? {
        guard isOpen(bucket) else { return nil }
        return rowKeys(for: bucket)
    }

    private func restore(_ children: [AssetChild]) {
        if exposureOnly {
            for child in children {
                for kind in child.kinds { setExpanded(kind, child.open) }
            }
            persistGroups()
            return
        }
        for child in children { setOpen(child.storageID, child.open) }
        AssetListMemory.netOpenGroups = groups.openGroupIDs
    }

    private func syncShell(_ children: [AssetChild], kinds: [AssetKind]) {
        guard let head = children.first else { return }
        let open = children.contains(where: \.open)
        if exposureOnly {
            var next = groups.expandedKinds
            if open { next.formUnion(kinds) } else { next.subtract(kinds) }
            groups.expandedKinds = next
            persistGroups()
            return
        }
        setOpen(head.storageID, open)
        AssetListMemory.netOpenGroups = groups.openGroupIDs
    }

    private func setExpanded(_ kind: AssetKind, _ open: Bool) {
        var next = groups.expandedKinds
        if open { next.insert(kind) } else { next.remove(kind) }
        groups.expandedKinds = next
        AssetListMemory.exposureKinds = next
    }

    private func setOpen(_ id: String, _ open: Bool) {
        var ids = groups.openGroupIDs
        if open { ids.insert(id) } else { ids.remove(id) }
        groups.openGroupIDs = ids
        AssetListMemory.netOpenGroups = ids
    }

    private func toggle(_ bucket: AssetBucket) {
        let id = bucket.id
        var ids = groups.openGroupIDs
        withAnimation {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            groups.openGroupIDs = ids
            AssetListMemory.netOpenGroups = ids
        }
    }

    private func saveItem(_ item: AssetItem) {
        portfolio.upsert(item)
        if exposureOnly {
            withAnimation {
                var next = groups.expandedKinds
                next.insert(item.kind)
                groups.expandedKinds = next
            }
            persistGroups()
            return
        }
        guard let bucket = shownBuckets.first(where: { $0.kinds.contains(item.kind) }) else { return }
        withAnimation {
            var ids = groups.openGroupIDs
            ids.insert(bucket.id)
            groups.openGroupIDs = ids
        }
    }

    private func refreshQuotes() async {
        let targets = portfolio.items.filter(\.canRefreshQuote)
        let hasUsd = portfolio.items.contains { $0.currency == .usd }
        guard !targets.isEmpty || hasUsd else { return }
        isRefreshing = true
        let quotes = targets.isEmpty ? [:] : await QuoteClient.fetchAll(
            symbols: Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.symbol) })
        )
        portfolio.applyQuotes(quotes)
        let rate = hasUsd ? try? await QuoteClient.fetchUsdTwd() : nil
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

private struct AssetRow: View {
    @Environment(Palette.self) private var palette
    let item: AssetItem
    var share: Double = 0
    var hideAmounts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(item.name)
                    Text(item.currency.rawValue)
                        .font(.caption2)
                        .foregroundStyle(palette.quietInk)
                    if item.kind == .leverage, let multiple = item.leverageMultiple {
                        Text(String(format: "%g×", multiple))
                            .font(.caption2)
                            .foregroundStyle(palette.quietInk)
                    }
                }
                Spacer()
                Text(MoneyFormat.string(item.kind == .debt ? -item.twdValue : item.twdValue, hidden: hideAmounts))
                    .monospacedDigit()
                    .foregroundStyle(item.kind == .debt ? palette.quietInk : palette.ink)
            }
            shareBar
        }
    }

    private var shareBar: some View {
        GeometryReader { row in
            HStack(alignment: .center, spacing: 6) {
                Text("100%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .hidden()
                    .accessibilityHidden(true)
                    .overlay(alignment: .leading) {
                        Text(shareLabel)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.quietInk)
                            .accessibilityLabel("佔該群組 \(shareLabel)")
                    }
                let lane = row.size.width * 0.5
                let filled = lane * min(1, max(0, share))
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 2,
                    topTrailingRadius: 2
                )
                shape
                    .fill(trackColor)
                    .frame(width: lane, height: 1)
                    .overlay(alignment: .leading) {
                        shape
                            .fill(barColor)
                            .frame(width: filled, height: 3)
                    }
                    .frame(width: lane, height: 3, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 14)
    }

    private var shareLabel: String {
        "\(Int((min(1, max(0, share)) * 100).rounded()))%"
    }

    /// Pure swatch from 顏色. Drift stays on the orbs and the target page.
    private var barColor: Color {
        palette.glow(for: item.kind, factor: 0)
    }

    /// A small step off the page. Only the background color moves it.
    private var trackColor: Color {
        let ink: Color = palette.colorScheme == .dark ? .white : .black
        return palette.ground.mix(with: ink, by: 0.14)
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
            .environment(Palette())
    }
}

#Preview("曝險連線") {
    NavigationStack {
        AssetListView(exposureOnly: true)
            .environment(Portfolio(items: [
                AssetItem(
                    name: "0050",
                    kind: .original,
                    amount: 0,
                    usesSharePrice: true,
                    shares: 20_000,
                    price: 190
                ),
                AssetItem(name: "00631L", kind: .leverage, amount: 600_000, leverageMultiple: 2),
                AssetItem(name: "活存", kind: .cash, amount: 300_000),
            ]))
            .environment(Palette())
    }
    .preferredColorScheme(.dark)
}
