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
    @State private var stocksMerged = false
    @State private var liquidMerged = false
    @State private var collapsingLiquid = false
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
    /// Global maxY of asset rows under 原型 / 槓桿, so the line can run to the last one.
    @State private var linkRowMaxY: [String: CGFloat] = [:]
    /// Bumped when the pair merges or splits, so row bottoms are measured again after the list shifts.
    @State private var linkEpoch = 0
    @State private var linkRowEpoch: [String: Int] = [:]
    /// Open state of 原型 / 槓桿 just before a merge, restored on split or when leaving this list.
    @State private var mergedWasExposure = false
    @State private var mergedOriginalOpen = false
    @State private var mergedLeverageOpen = false
    @State private var mergedOriginalID: String?
    @State private var mergedLeverageID: String?
    @State private var mergedCashOpen = false
    @State private var mergedCashID: String?
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
                    bucket.kinds == [.leverage] || bucket.kinds == [.cash]
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
            rowsOrEmpty(
                items(in: bucket),
                trackLink: tracksLinkRows(bucket) ? bucket.id : nil,
                onLink: linkAction(for: bucket)
            )
        }
    }

    private func items(in bucket: AssetBucket) -> [AssetItem] {
        bucket.kinds.flatMap { portfolio.items(for: $0) }
    }

    private func amount(of bucket: AssetBucket) -> Decimal {
        bucket.kinds.reduce(0) { $0 + portfolio.amount(for: $1) }
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
        if liquidMerged { return bucket.kinds == [.original, .leverage, .cash] }
        if bucket.kinds == [.cash] { return cashJoinAvailable && !liquidMerged }
        return isLinkBucket(bucket)
    }

    private func linkBucketFades(_ kinds: [AssetKind]) -> Bool {
        guard linkCollapsed else { return false }
        if kinds == [.leverage] { return true }
        return collapsingLiquid && kinds == [.cash]
    }

    private func linkAction(for bucket: AssetBucket) -> (() -> Void)? {
        if liquidMerged {
            return bucket.kinds == [.original, .leverage, .cash] ? splitLiquid : nil
        }
        if isLinkBucket(bucket) { return tapStockLink }
        if cashJoinAvailable, !liquidMerged, bucket.kinds == [.cash] { return mergeLiquid }
        return nil
    }

    private func linkActionTitle(_ bucket: AssetBucket) -> String? {
        if liquidMerged, bucket.kinds == [.original, .leverage, .cash] { return "分開為原型、槓桿與現金" }
        if isLinkBucket(bucket) { return stocksMerged ? "分開為原型與槓桿" : "合併為股票" }
        if cashJoinAvailable, !liquidMerged, bucket.kinds == [.cash] { return "合併為流動" }
        return nil
    }

    private func trackLink(_ bucket: AssetBucket, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            // Collapse moves this header; keeping the resting frame lets the line return on split.
            guard !linkCollapsed, !stocksMerged, !liquidMerged else { return }
            linkLeverage = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] {
            linkOriginal = frame
        }
    }

    private func trackTitle(_ bucket: AssetBucket, _ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if bucket.kinds == [.leverage] {
            guard !linkCollapsed, !stocksMerged, !liquidMerged else { return }
            linkLeverageTitle = frame
        } else if bucket.kinds == [.cash] {
            guard !linkCollapsed, !liquidMerged else { return }
            linkCashTitle = frame
        } else if bucket.kinds == [.original] || bucket.kinds == [.original, .leverage] || bucket.kinds == [.original, .leverage, .cash] {
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
        guard stockPairAvailable, !stocksMerged, !liquidMerged,
              let original = linkOriginal, let leverage = linkLeverage else { return nil }
        let rows = endGroupIsOpen ? openLinkRowBottom : nil
        return linkSpan(from: original, title: linkTitle, through: leverage, endTitle: linkLeverageTitle, rows: rows)
    }

    private var stockStub: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard stockPairAvailable, stocksMerged, let original = linkOriginal else { return nil }
        let rows = endGroupIsOpen ? openLinkRowBottom : nil
        if let span = linkSpan(from: original, title: linkTitle, through: nil, endTitle: linkTitle, rows: rows) {
            return span
        }
        let x = original.minX - listGlobalOrigin.x - 16
        return (x, original.midY - listGlobalOrigin.y - 14, 28)
    }

    /// Gray join from the group above 現金 down to 現金. Tap merges into 流動.
    private var cashLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard cashJoinAvailable, !liquidMerged, !linkCollapsed || collapsingLiquid,
              let cashTitle = linkCashTitle else { return nil }
        let top = cashAnchorMaxY
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
               let row = measuredBottom(rowKeys(for: stock)) {
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

    private var liquidLine: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard liquidMerged, cashJoinAvailable, let original = linkOriginal else { return nil }
        let rows: CGFloat? = {
            guard let bucket = shownBuckets.first(where: { $0.kinds == [.original, .leverage, .cash] }),
                  isOpen(bucket) else { return nil }
            return measuredBottom(rowKeys(for: bucket))
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
            if liquidMerged, let line = liquidLine {
                linkMark(line, collapsed: false, color: .white.opacity(0.85))
            } else if stocksMerged, let stub = stockStub {
                linkMark(stub, collapsed: false, color: .white.opacity(0.85))
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
            } else {
                if let line = stockLine {
                    linkMark(line, collapsed: linkCollapsed, color: .secondary)
                }
                if let cash = cashLine {
                    linkMark(cash, collapsed: collapsingLiquid && linkCollapsed, color: .secondary)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func tapStockLink() {
        if stocksMerged { splitStocks() } else { mergeStocks() }
    }

    private func mergeStocks() {
        guard !linkCollapsed else { return }
        rememberOpenBeforeMerge()
        if reduceMotion {
            stocksMerged = true
            linkEpoch += 1
            syncOpenForMerge()
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            linkCollapsed = true
        } completion: {
            withAnimation(.smooth(duration: 0.45)) {
                stocksMerged = true
                linkCollapsed = false
                linkEpoch += 1
                syncOpenForMerge()
            }
        }
    }

    private func splitStocks() {
        guard !linkCollapsed else { return }
        if reduceMotion {
            restoreOpenAfterSplit()
            stocksMerged = false
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            restoreOpenAfterSplit()
            stocksMerged = false
            linkEpoch += 1
        }
    }

    private func mergeLiquid() {
        guard !linkCollapsed, !liquidMerged, cashJoinAvailable else { return }
        rememberLiquidOpen()
        if reduceMotion {
            liquidMerged = true
            stocksMerged = false
            linkEpoch += 1
            syncLiquidOpen()
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
                syncLiquidOpen()
            }
        }
    }

    private func splitLiquid() {
        guard !linkCollapsed, liquidMerged else { return }
        if reduceMotion {
            restoreLiquidOpen()
            liquidMerged = false
            linkEpoch += 1
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            restoreLiquidOpen()
            liquidMerged = false
            linkEpoch += 1
        }
    }

    private func cancelMergeIfNeeded() {
        if liquidMerged {
            restoreLiquidOpen()
            liquidMerged = false
            linkEpoch += 1
        } else if stocksMerged {
            restoreOpenAfterSplit()
            stocksMerged = false
            linkEpoch += 1
        }
        linkCollapsed = false
        collapsingLiquid = false
    }

    private func rememberLiquidOpen() {
        mergedWasExposure = exposureOnly
        if exposureOnly {
            mergedOriginalOpen = expandedKinds.contains(.original)
            mergedLeverageOpen = expandedKinds.contains(.leverage)
            mergedCashOpen = expandedKinds.contains(.cash)
            return
        }
        guard let original = baseBuckets.first(where: { $0.kinds == [.original] }),
              let leverage = baseBuckets.first(where: { $0.kinds == [.leverage] }),
              let cash = baseBuckets.first(where: { $0.kinds == [.cash] }) else { return }
        mergedOriginalID = grouping.storageID(for: original)
        mergedLeverageID = grouping.storageID(for: leverage)
        mergedCashID = grouping.storageID(for: cash)
        mergedOriginalOpen = openGroupIDs.contains(mergedOriginalID ?? "")
        mergedLeverageOpen = openGroupIDs.contains(mergedLeverageID ?? "")
        mergedCashOpen = openGroupIDs.contains(mergedCashID ?? "")
    }

    private func restoreLiquidOpen() {
        if mergedWasExposure {
            setExpanded(.original, mergedOriginalOpen)
            setExpanded(.leverage, mergedLeverageOpen)
            setExpanded(.cash, mergedCashOpen)
            persistGroups()
            return
        }
        if let id = mergedOriginalID { setOpen(id, mergedOriginalOpen) }
        if let id = mergedLeverageID { setOpen(id, mergedLeverageOpen) }
        if let id = mergedCashID { setOpen(id, mergedCashOpen) }
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func syncLiquidOpen() {
        if exposureOnly {
            let open = expandedKinds.contains(.original) || expandedKinds.contains(.leverage) || expandedKinds.contains(.cash)
            if open {
                expandedKinds.formUnion([.original, .leverage, .cash])
            } else {
                expandedKinds.subtract([.original, .leverage, .cash])
            }
            persistGroups()
            return
        }
        guard let original = baseBuckets.first(where: { $0.kinds == [.original] }),
              let leverage = baseBuckets.first(where: { $0.kinds == [.leverage] }),
              let cash = baseBuckets.first(where: { $0.kinds == [.cash] }) else { return }
        let origID = grouping.storageID(for: original)
        let open = openGroupIDs.contains(origID)
            || openGroupIDs.contains(grouping.storageID(for: leverage))
            || openGroupIDs.contains(grouping.storageID(for: cash))
        setOpen(origID, open)
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func rememberOpenBeforeMerge() {
        mergedWasExposure = exposureOnly
        if exposureOnly {
            mergedOriginalOpen = expandedKinds.contains(.original)
            mergedLeverageOpen = expandedKinds.contains(.leverage)
            return
        }
        guard let original = baseBuckets.first(where: { $0.kinds == [.original] }),
              let leverage = baseBuckets.first(where: { $0.kinds == [.leverage] }) else { return }
        mergedOriginalID = grouping.storageID(for: original)
        mergedLeverageID = grouping.storageID(for: leverage)
        mergedOriginalOpen = openGroupIDs.contains(mergedOriginalID ?? "")
        mergedLeverageOpen = openGroupIDs.contains(mergedLeverageID ?? "")
    }

    private func restoreOpenAfterSplit() {
        if mergedWasExposure {
            setExpanded(.original, mergedOriginalOpen)
            setExpanded(.leverage, mergedLeverageOpen)
            persistGroups()
            return
        }
        if let id = mergedOriginalID { setOpen(id, mergedOriginalOpen) }
        if let id = mergedLeverageID { setOpen(id, mergedLeverageOpen) }
        AssetListMemory.netOpenGroups = openGroupIDs
    }

    private func setExpanded(_ kind: AssetKind, _ open: Bool) {
        if open { expandedKinds.insert(kind) } else { expandedKinds.remove(kind) }
    }

    private func setOpen(_ id: String, _ open: Bool) {
        if open { openGroupIDs.insert(id) } else { openGroupIDs.remove(id) }
    }

    private func syncOpenForMerge() {
        if exposureOnly {
            let open = expandedKinds.contains(.original) || expandedKinds.contains(.leverage)
            if open {
                expandedKinds.formUnion([.original, .leverage])
            } else {
                expandedKinds.subtract([.original, .leverage])
            }
            persistGroups()
            return
        }
        guard let original = baseBuckets.first(where: { $0.kinds == [.original] }),
              let leverage = baseBuckets.first(where: { $0.kinds == [.leverage] }) else { return }
        let origID = grouping.storageID(for: original)
        let levID = grouping.storageID(for: leverage)
        if openGroupIDs.contains(origID) || openGroupIDs.contains(levID) {
            openGroupIDs.insert(origID)
        } else {
            openGroupIDs.remove(origID)
        }
        AssetListMemory.netOpenGroups = openGroupIDs
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
