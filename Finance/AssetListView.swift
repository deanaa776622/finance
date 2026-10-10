import SwiftUI

/// A group that was on screen when 流動／股票／現金 folded into 資產.
private struct AssetChild: Identifiable {
    var id: String
    var title: String
    var kinds: [AssetKind]
    var storageID: String
    var open: Bool
}

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
    @State private var stocksMerged = false
    @State private var liquidMerged = false
    @State private var collapsingLiquid = false
    @State private var assetMerged = false
    @State private var collapsingAsset = false
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
    /// Global maxY of asset rows under 原型 / 槓桿, so the line can run to the last one.
    @State private var linkRowMaxY: [String: CGFloat] = [:]
    /// Bumped when the pair merges or splits, so row bottoms are measured again after the list shifts.
    @State private var linkEpoch = 0
    @State private var linkRowEpoch: [String: Int] = [:]
    /// Groups on screen just before a merge, so expanding returns to that level.
    @State private var assetChildren: [AssetChild] = []
    @State private var assetHeldStocks = false
    @State private var assetHeldLiquid = false
    @State private var liquidChildren: [AssetChild] = []
    @State private var liquidHeadID = ""
    @State private var liquidHeldStocks = false
    @State private var stockChildren: [AssetChild] = []
    @State private var stockHeadID = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            ForEach(shownBuckets) { bucket in
                Section {
                    bucketItems(bucket)
                } header: {
                    bucketHeader(bucket)
                }
                .opacity(linkBucketFades(bucket.kinds) ? 0 : 1)
                .transition(
                    bucket.kinds == [.leverage] || bucket.kinds == [.cash] || bucket.kinds == [.realEstate]
                        ? .move(edge: .top).combined(with: .opacity)
                        : .identity
                )
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.bottom, showsChrome ? 64 : 0, for: .scrollContent)
        .onGeometryChange(for: CGPoint.self) {
            let frame = $0.frame(in: .global)
            return CGPoint(x: frame.minX, y: frame.minY)
        } action: { listGlobalOrigin = $0 }
        .overlay(alignment: .topLeading) { stockLinkLayer }
        .scrollEdgeFade(edges: .bottom)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: stocksMerged)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: liquidMerged)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: assetMerged)
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
            cancelMergeIfNeeded()
            if wasExposure { AssetListMemory.exposureKinds = expandedKinds }
            if isExposure { expandedKinds = AssetListMemory.exposureKinds }
        }
        .onChange(of: grouping) { _, _ in
            cancelMergeIfNeeded()
            stockChildren = []
            liquidChildren = []
            assetChildren = []
        }
        .onDisappear(perform: persistGroups)
    }

    private var baseBuckets: [AssetBucket] {
        if exposureOnly {
            [
                AssetBucket(id: "original", title: "原型", kinds: [.original]),
                AssetBucket(id: "leverage", title: "槓桿", kinds: [.leverage]),
                AssetBucket(id: "cash", title: "現金", kinds: [.cash]),
            ]
        } else {
            grouping.buckets
        }
    }

    private var shownBuckets: [AssetBucket] {
        if assetMerged { return bucketsMergingAssets(baseBuckets, merged: true) }
        if liquidMerged { return bucketsMergingLiquid(baseBuckets, merged: true) }
        return bucketsMergingStocks(baseBuckets, merged: stocksMerged)
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

    private func headerColor(open: Bool) -> Color {
        open ? .secondary : .white
    }

    @ViewBuilder
    private func bucketHeader(_ bucket: AssetBucket) -> some View {
        let header = groupHeader(bucket.title, open: isOpen(bucket), amount: amount(of: bucket), titleFrame: { trackTitle(bucket, $0) }) {
            toggleBucket(bucket)
        }
        .opacity(linkBucketFades(bucket.kinds) ? 0 : 1)
        .stockLinkHit(enabled: linkAction(for: bucket) != nil, margin: 24) { linkAction(for: bucket)?() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trackLink(bucket, frame: $0) }
        if let title = linkActionTitle(bucket) {
            headerChrome(header.accessibilityAction(named: Text(title)) { linkAction(for: bucket)?() })
        } else {
            headerChrome(header)
        }
    }

    @ViewBuilder
    private func bucketItems(_ bucket: AssetBucket) -> some View {
        if isOpen(bucket) {
            if assetMerged, bucket.kinds == [.original, .leverage, .cash, .realEstate] {
                assetLevel(assetChildren)
            } else if liquidMerged, bucket.kinds == [.original, .leverage, .cash] {
                liquidLevel(liquidChildren)
            } else if stocksMerged, bucket.kinds == [.original, .leverage] {
                stockLevel(stockChildren)
            } else {
                rowsOrEmpty(
                    items(in: bucket),
                    trackLink: tracksLinkRows(bucket) ? bucket.id : nil,
                    onLink: linkAction(for: bucket)
                )
            }
        }
    }

    private func toggleAssetChild(_ id: String) { toggle(&assetChildren, id) }
    private func toggleLiquidChild(_ id: String) { toggle(&liquidChildren, id) }
    private func toggleStockChild(_ id: String) { toggle(&stockChildren, id) }

    private func toggle(_ children: inout [AssetChild], _ id: String) {
        guard let index = children.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { children[index].open.toggle() }
    }

    /// Expanded merged group shows the groups that were on screen before that merge.
    @ViewBuilder
    private func assetLevel(_ children: [AssetChild]) -> some View {
        ForEach(children) { child in
            childHeader(child, mark: "asset") { toggleAssetChild(child.id) }
            if child.open { belowLiquid(child) }
        }
    }

    @ViewBuilder
    private func liquidLevel(_ children: [AssetChild]) -> some View {
        ForEach(children) { child in
            childHeader(child, mark: "liquid") { toggleLiquidChild(child.id) }
            if child.open { belowStock(child) }
        }
    }

    @ViewBuilder
    private func stockLevel(_ children: [AssetChild]) -> some View {
        ForEach(children) { child in
            childHeader(child, mark: "stock") { toggleStockChild(child.id) }
            if child.open {
                rowsOrEmpty(items(in: child.kinds), trackLink: child.id, onLink: nil)
            }
        }
    }

    @ViewBuilder
    private func belowLiquid(_ child: AssetChild) -> some View {
        if child.id == liquidHeadID, child.kinds == [.original, .leverage, .cash], liquidChildren.count > 1 {
            liquidLevel(liquidChildren)
        } else {
            belowStock(child)
        }
    }

    @ViewBuilder
    private func belowStock(_ child: AssetChild) -> some View {
        if child.id == stockHeadID, child.kinds == [.original, .leverage], stockChildren.count > 1 {
            stockLevel(stockChildren)
        } else {
            rowsOrEmpty(items(in: child.kinds), trackLink: child.id, onLink: nil)
        }
    }

    private func childHeader(_ child: AssetChild, mark: String, action: @escaping () -> Void) -> some View {
        headerChrome(
            groupHeader(child.title, open: child.open, amount: amount(of: child.kinds), action: action)
                .overlay(alignment: .bottom) { rowBottomTracker("\(mark)-\(child.id)") }
        )
    }

    private func items(in bucket: AssetBucket) -> [AssetItem] {
        items(in: bucket.kinds)
    }

    private func items(in kinds: [AssetKind]) -> [AssetItem] {
        kinds.flatMap { portfolio.items(for: $0) }
    }

    private func amount(of bucket: AssetBucket) -> Decimal {
        amount(of: bucket.kinds)
    }

    private func amount(of kinds: [AssetKind]) -> Decimal {
        kinds.reduce(0) { $0 + portfolio.amount(for: $1) }
    }

    private func groupHeader(
        _ title: String,
        open: Bool,
        amount: Decimal,
        titleFrame: ((CGRect) -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(headerColor(open: open))
                    .contentTransition(.interpolate)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { titleFrame?($0) }
                Spacer()
                Text(MoneyFormat.string(amount, hidden: hideAmounts))
                    .font(.system(size: titleSize))
                    .monospacedDigit()
                    .foregroundStyle(headerColor(open: open))
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(open ? "收合" : "展開")
    }

    private func headerChrome<V: View>(_ view: V) -> some View {
        view
            .listRowInsets(EdgeInsets(top: 18, leading: 32, bottom: 8, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(Color(.systemGroupedBackground))
            .textCase(nil)
    }

    @ViewBuilder
    private func rowsOrEmpty(_ rows: [AssetItem], trackLink bucketID: String? = nil, onLink: (() -> Void)? = nil) -> some View {
        if rows.isEmpty {
            Text("尚無紀錄")
                .foregroundStyle(.secondary)
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

    private func isOpen(_ bucket: AssetBucket) -> Bool {
        if exposureOnly {
            return bucket.kinds.contains { expandedKinds.contains($0) }
        }
        return openGroupIDs.contains(grouping.storageID(for: bucket))
    }

    private func toggleBucket(_ bucket: AssetBucket) {
        if exposureOnly {
            withAnimation {
                let open = isOpen(bucket)
                for kind in bucket.kinds {
                    if open { expandedKinds.remove(kind) } else { expandedKinds.insert(kind) }
                }
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
        if assetMerged { return bucket.kinds == [.original, .leverage, .cash, .realEstate] }
        if bucket.kinds == [.realEstate] { return assetJoinAvailable && !assetMerged }
        if liquidMerged { return bucket.kinds == [.original, .leverage, .cash] }
        if bucket.kinds == [.cash] { return cashJoinAvailable && !liquidMerged && !assetMerged }
        if isLinkBucket(bucket) { return true }
        if let above = bucketAboveReal, above.id == bucket.id { return assetJoinAvailable && !assetMerged }
        return false
    }

    private var bucketAboveReal: AssetBucket? {
        guard let index = shownBuckets.firstIndex(where: { $0.kinds == [.realEstate] }), index > 0 else { return nil }
        return shownBuckets[index - 1]
    }

    private func linkBucketFades(_ kinds: [AssetKind]) -> Bool {
        guard linkCollapsed else { return false }
        if kinds == [.leverage] { return true }
        if kinds == [.cash] { return collapsingLiquid || collapsingAsset }
        return collapsingAsset && kinds == [.realEstate]
    }

    private func linkAction(for bucket: AssetBucket) -> (() -> Void)? {
        if assetMerged {
            return bucket.kinds == [.original, .leverage, .cash, .realEstate] ? splitAssets : nil
        }
        if assetJoinAvailable, bucket.kinds == [.realEstate] { return mergeAssets }
        if liquidMerged {
            return bucket.kinds == [.original, .leverage, .cash] ? splitLiquid : nil
        }
        if isLinkBucket(bucket) { return tapStockLink }
        if cashJoinAvailable, !liquidMerged, bucket.kinds == [.cash] { return mergeLiquid }
        return nil
    }

    private func linkActionTitle(_ bucket: AssetBucket) -> String? {
        if assetMerged, bucket.kinds == [.original, .leverage, .cash, .realEstate] { return assetSplitTitle }
        if assetJoinAvailable, bucket.kinds == [.realEstate] { return "合併為資產" }
        if liquidMerged, bucket.kinds == [.original, .leverage, .cash] { return splitTitle(liquidChildren, fallback: "分開為原型、槓桿與現金") }
        if stocksMerged, bucket.kinds == [.original, .leverage] {
            return splitTitle(stockChildren, fallback: "分開為原型與槓桿")
        }
        if isLinkBucket(bucket) { return "合併為股票" }
        if cashJoinAvailable, !liquidMerged, bucket.kinds == [.cash] { return "合併為流動" }
        return nil
    }

    private var assetSplitTitle: String {
        splitTitle(assetChildren, fallback: "分開資產")
    }

    private func splitTitle(_ children: [AssetChild], fallback: String) -> String {
        let names = children.map(\.title).joined(separator: "、")
        return names.isEmpty ? fallback : "分開為\(names)"
    }

    private func trackLink(_ bucket: AssetBucket, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            // Collapse moves this header; keeping the resting frame lets the line return on split.
            guard !linkCollapsed, !stocksMerged, !liquidMerged, !assetMerged else { return }
            linkLeverage = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] || bucket.kinds == [.original, .leverage, .cash, .realEstate] {
            linkOriginal = frame
        }
    }

    private func trackTitle(_ bucket: AssetBucket, _ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            guard !linkCollapsed, !stocksMerged, !liquidMerged, !assetMerged else { return }
            linkLeverageTitle = frame
        } else if bucket.kinds == [.cash] {
            guard !linkCollapsed, !liquidMerged, !assetMerged else { return }
            linkCashTitle = frame
        } else if bucket.kinds == [.realEstate] {
            guard !linkCollapsed, !assetMerged else { return }
            linkRealTitle = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] || bucket.kinds == [.original, .leverage, .cash, .realEstate] {
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

    private var openLinkRowBottom: CGFloat? {
        measuredBottom(openLinkRowKeys)
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

    private var openLinkRowKeys: Set<String> {
        var keys: Set<String> = []
        for bucket in shownBuckets where isLinkBucket(bucket) && isOpen(bucket) {
            let rows = items(in: bucket)
            if rows.isEmpty {
                keys.insert("empty-\(bucket.id)")
            } else {
                keys.formUnion(rows.map(\.id.uuidString))
            }
        }
        return keys
    }

    /// True when the group at the bottom of the line is open, so the line runs past its title.
    private var endGroupIsOpen: Bool {
        if stocksMerged {
            return shownBuckets.contains { $0.kinds == [.original, .leverage] && isOpen($0) }
        }
        return shownBuckets.contains { $0.kinds == [.leverage] && isOpen($0) }
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
        guard stockPairAvailable, !stocksMerged, !liquidMerged, !assetMerged,
              let original = linkOriginal, let leverage = linkLeverage else { return nil }
        let rows = endGroupIsOpen ? openLinkRowBottom : nil
        return linkSpan(from: original, title: linkTitle, through: leverage, endTitle: linkLeverageTitle, rows: rows)
    }

    private var stockStub: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard stockPairAvailable, stocksMerged, let original = linkOriginal else { return nil }
        let rows = endGroupIsOpen ? measuredBottom(openChildKeys(stockChildren, mark: "stock")) : nil
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    /// Gray join from the group above 現金 down to 現金. Tap merges into 流動.
    private var cashLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard cashJoinAvailable, !liquidMerged, !assetMerged, !linkCollapsed || collapsingLiquid,
              let cashTitle = linkCashTitle else { return nil }
        let top = cashAnchorMaxY + 8
        guard top > 1 else { return nil }
        var bottom = cashTitle.maxY
        if let cash = shownBuckets.first(where: { $0.kinds == [.cash] }), isOpen(cash),
           let row = measuredBottom(rowKeys(for: cash)) {
            bottom = max(bottom, row)
        }
        let height = bottom - top
        guard height > 1 else { return nil }
        return (cashTitle.minX - listGlobalOrigin.x - 16, top - listGlobalOrigin.y, height)
    }

    /// Bottom of 槓桿, or of 股票 once that pair is merged.
    private var cashAnchorMaxY: CGFloat {
        if stocksMerged, let stockTitle = linkTitle {
            var top = stockTitle.maxY
            if let stock = shownBuckets.first(where: { $0.kinds == [.original, .leverage] }), isOpen(stock),
               let row = measuredBottom(openChildKeys(stockChildren, mark: "stock")) {
                top = max(top, row)
            }
            return top
        }
        guard let leverageTitle = linkLeverageTitle else { return 0 }
        var top = leverageTitle.maxY
        if let leverage = shownBuckets.first(where: { $0.kinds == [.leverage] }), isOpen(leverage),
           let row = measuredBottom(rowKeys(for: leverage)) {
            top = max(top, row)
        }
        return top
    }

    /// Gray join from the group above 實體 down through 實體. Tap merges them into 資產.
    private var realLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard assetJoinAvailable, !assetMerged, !linkCollapsed || collapsingAsset,
              let realTitle = linkRealTitle else { return nil }
        let top = realAnchorMaxY + 8
        guard top > 1 else { return nil }
        var bottom = realTitle.maxY
        if let real = shownBuckets.first(where: { $0.kinds == [.realEstate] }), isOpen(real),
           let row = measuredBottom(rowKeys(for: real)) {
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
        if isOpen(above), let row = measuredBottom(anchorKeys(for: above)) {
            top = max(top, row)
        }
        return top
    }

    private var assetLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard assetMerged, assetJoinAvailable, let original = linkOriginal else { return nil }
        let rows: CGFloat? = {
            guard let bucket = shownBuckets.first(where: { $0.kinds == [.original, .leverage, .cash, .realEstate] }),
                  isOpen(bucket) else { return nil }
            return measuredBottom(openChildKeys(assetChildren, mark: "asset"))
        }()
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    private var liquidLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard liquidMerged, cashJoinAvailable, let original = linkOriginal else { return nil }
        let rows: CGFloat? = {
            guard let bucket = shownBuckets.first(where: { $0.kinds == [.original, .leverage, .cash] }),
                  isOpen(bucket) else { return nil }
            return measuredBottom(openChildKeys(liquidChildren, mark: "liquid"))
        }()
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
            if assetMerged, let line = assetLine {
                linkMark(line, collapsed: false, color: .white.opacity(0.85))
            } else if liquidMerged, let line = liquidLine {
                linkMark(line, collapsed: false, color: .white.opacity(0.85))
                realLinkMark
            } else if stocksMerged, let stub = stockStub {
                linkMark(stub, collapsed: false, color: .white.opacity(0.85))
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
                realLinkMark
            } else {
                if let line = stockLine {
                    linkMark(line, collapsed: linkCollapsed, color: .secondary)
                }
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
                realLinkMark
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

    private func tapStockLink() {
        if stocksMerged { splitStocks() } else { mergeStocks() }
    }

    private func mergeStocks() {
        guard !linkCollapsed else { return }
        let joined = stockJoinBuckets()
        guard !joined.isEmpty else { return }
        stockChildren = snapshot(joined)
        stockHeadID = joined[0].id
        if reduceMotion {
            stocksMerged = true
            linkEpoch += 1
            syncShell(stockChildren, kinds: [.original, .leverage])
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
        } completion: {
            withAnimation(.smooth(duration: 0.45)) {
                stocksMerged = true
                linkCollapsed = false
                linkEpoch += 1
                syncShell(stockChildren, kinds: [.original, .leverage])
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
        guard !linkCollapsed, !liquidMerged, cashJoinAvailable else { return }
        let joined = liquidJoinBuckets()
        guard !joined.isEmpty else { return }
        liquidChildren = snapshot(joined)
        liquidHeadID = joined[0].id
        liquidHeldStocks = stocksMerged
        if reduceMotion {
            liquidMerged = true
            stocksMerged = false
            linkEpoch += 1
            syncShell(liquidChildren, kinds: [.original, .leverage, .cash])
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
            collapsingLiquid = true
        } completion: {
            guard collapsingLiquid else { return }
            withAnimation(.smooth(duration: 0.45)) {
                liquidMerged = true
                stocksMerged = false
                linkCollapsed = false
                collapsingLiquid = false
                linkEpoch += 1
                syncShell(liquidChildren, kinds: [.original, .leverage, .cash])
            }
        }
    }

    private func splitLiquid() {
        guard !linkCollapsed, liquidMerged else { return }
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

    private func mergeAssets() {
        guard !linkCollapsed, !assetMerged, assetJoinAvailable else { return }
        rememberAssetChildren()
        if reduceMotion {
            assetMerged = true
            stocksMerged = false
            liquidMerged = false
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
                assetMerged = true
                stocksMerged = false
                liquidMerged = false
                linkCollapsed = false
                collapsingAsset = false
                linkEpoch += 1
                syncAssetOpen()
            }
        }
    }

    private func splitAssets() {
        guard !linkCollapsed, assetMerged else { return }
        if reduceMotion {
            restoreAssetChildren()
            assetMerged = false
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            restoreAssetChildren()
            assetMerged = false
            linkEpoch += 1
        }
    }

    private func rememberAssetChildren() {
        let shown = shownBuckets
        guard let range = assetJoinRange(shown) else { return }
        assetHeldStocks = stocksMerged
        assetHeldLiquid = liquidMerged
        assetChildren = shown[range].map { bucket in
            AssetChild(
                id: bucket.id,
                title: bucket.title,
                kinds: bucket.kinds,
                storageID: grouping.storageID(for: bucket),
                open: isOpen(bucket)
            )
        }
    }

    private func restoreAssetChildren() {
        restore(assetChildren)
        stocksMerged = assetHeldStocks
        liquidMerged = assetHeldLiquid
    }

    private func syncAssetOpen() {
        syncShell(assetChildren, kinds: [.original, .leverage, .cash, .realEstate])
    }

    private func cancelMergeIfNeeded() {
        if assetMerged {
            restoreAssetChildren()
            assetMerged = false
            linkEpoch += 1
        } else if liquidMerged {
            undoLiquidMerge()
            linkEpoch += 1
        } else if stocksMerged {
            undoStockMerge()
            linkEpoch += 1
        }
        linkCollapsed = false
        collapsingLiquid = false
        collapsingAsset = false
    }

    private func undoStockMerge() {
        restore(stockChildren)
        stocksMerged = false
    }

    private func undoLiquidMerge() {
        restore(liquidChildren)
        stocksMerged = liquidHeldStocks
        liquidMerged = false
    }

    private func snapshot(_ buckets: [AssetBucket]) -> [AssetChild] {
        buckets.map { bucket in
            AssetChild(
                id: bucket.id,
                title: bucket.title,
                kinds: bucket.kinds,
                storageID: grouping.storageID(for: bucket),
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

    private func nestedSnapshot(of child: AssetChild) -> (children: [AssetChild], mark: String)? {
        if child.id == liquidHeadID, child.kinds == [.original, .leverage, .cash], liquidChildren.count > 1 {
            return (liquidChildren, "liquid")
        }
        if child.id == stockHeadID, child.kinds == [.original, .leverage], stockChildren.count > 1 {
            return (stockChildren, "stock")
        }
        return nil
    }

    private func openChildKeys(_ children: [AssetChild], mark: String) -> Set<String> {
        var keys = Set(children.map { "\(mark)-\($0.id)" })
        for child in children where child.open {
            if let nested = nestedSnapshot(of: child) {
                keys.formUnion(openChildKeys(nested.children, mark: nested.mark))
            } else {
                let rows = items(in: child.kinds)
                if rows.isEmpty {
                    keys.insert("empty-\(child.id)")
                } else {
                    keys.formUnion(rows.map(\.id.uuidString))
                }
            }
        }
        return keys
    }

    private func anchorKeys(for bucket: AssetBucket) -> Set<String> {
        let child = AssetChild(id: bucket.id, title: bucket.title, kinds: bucket.kinds, storageID: "", open: true)
        if let nested = nestedSnapshot(of: child) {
            return openChildKeys(nested.children, mark: nested.mark)
        }
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
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func syncShell(_ children: [AssetChild], kinds: [AssetKind]) {
        guard let head = children.first else { return }
        let open = children.contains(where: \.open)
        if exposureOnly {
            if open { expandedKinds.formUnion(kinds) } else { expandedKinds.subtract(kinds) }
            persistGroups()
            return
        }
        setOpen(head.storageID, open)
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func setExpanded(_ kind: AssetKind, _ open: Bool) {
        if open { expandedKinds.insert(kind) } else { expandedKinds.remove(kind) }
    }

    private func setOpen(_ id: String, _ open: Bool) {
        if open { openGroupIDs.insert(id) } else { openGroupIDs.remove(id) }
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
    /// Matches the group title's leading inset, so the card's left edge lines up with the first glyph.
    static let leading: CGFloat = 32

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
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.inset)
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
    }
    .preferredColorScheme(.dark)
}
