import SwiftUI
import UIKit

struct AssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Palette.self) private var palette
    @FocusState private var focus: Field?
    @State private var name: String
    @State private var symbol: String
    @State private var kind: AssetKind
    @State private var currency: AssetCurrency
    @State private var rateText: String
    /// Full rate and price. The fields show a shorter number; the total keeps these until edited.
    @State private var fullRate: Decimal
    @State private var fullPrice: Decimal
    @State private var usesSharePrice: Bool
    @State private var sharesText: String
    @State private var priceText: String
    @State private var amountText: String
    @State private var leverage: Double
    @State private var quoteState: QuoteState = .idle
    @State private var rateState: QuoteState = .idle
    @State private var isRefreshingTotal = false
    @State private var lumpShowsTwd = false
    @State private var labelWidth: CGFloat = 0
    @State private var confirmDelete = false
    /// "medium" or "large". Missing key stays full height.
    @AppStorage("assetSheetDetent") private var detentID = "large"
    private let existingID: UUID?
    var onSave: (AssetItem) -> Void
    var onDelete: (() -> Void)?

    private enum Field: Hashable { case symbol, name, shares, price, amount, rate }

    init(
        item: AssetItem?,
        defaultKind: AssetKind = .original,
        onSave: @escaping (AssetItem) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        existingID = item?.id
        let kind = item?.kind ?? defaultKind
        _name = State(initialValue: item?.name ?? "")
        _symbol = State(initialValue: item?.symbol ?? "")
        _kind = State(initialValue: kind)
        _currency = State(initialValue: item?.currency ?? .twd)
        let storedRate = item?.usdTwdRate ?? 32
        _rateText = State(initialValue: NumberParse.fx(storedRate))
        _fullRate = State(initialValue: storedRate)
        _usesSharePrice = State(initialValue: item?.usesSharePrice ?? kind.prefersSharePrice)
        _sharesText = State(initialValue: item?.shares.map(NumberParse.display) ?? "")
        _fullPrice = State(initialValue: item?.price ?? 0)
        _priceText = State(initialValue: item?.price.map(NumberParse.price) ?? "")
        _amountText = State(initialValue: item.map { NumberParse.display($0.amount) } ?? "")
        _leverage = State(initialValue: Self.clampedLeverage(kind: kind, value: item?.leverageMultiple))
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// Non-leverage is always 1×; leverage cannot be 1× (default 2×).
    private static func clampedLeverage(kind: AssetKind, value: Double?) -> Double {
        if kind == .leverage {
            let multiple = value ?? 2
            return multiple == 1 ? 2 : multiple
        }
        return 1
    }

    private static let leverageSteps: [(title: String, value: Double)] = [
        ("1×", 1), ("1.5×", 1.5), ("2×", 2), ("3×", 3)
    ]

    /// The selected kind's own color, with no drift mixed in.
    private var kindTint: Color { palette.glow(for: kind, factor: 0) }

    /// Black or white, so the title stays readable on the selected knob.
    private var knobInk: Color {
        kindTint.relativeLuminance(scheme: palette.colorScheme) > 0.179 ? .black : .white
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PaletteSegments(
                        titles: AssetKind.allCases.map(\.compactTitle),
                        index: AssetKind.allCases.firstIndex(of: kind) ?? 0,
                        enabled: true,
                        tint: UIColor(kindTint),
                        titleInk: UIColor(knobInk)
                    ) { index in
                        let new = AssetKind.allCases[index]
                        kind = new
                        if new.prefersSharePrice { usesSharePrice = true }
                        leverage = Self.clampedLeverage(kind: new, value: leverage)
                    }
                    .listRowSeparator(.hidden)
                    PaletteSegments(
                        titles: ["總金額", "股數與單價"],
                        index: usesSharePrice ? 1 : 0,
                        enabled: !kind.prefersSharePrice,
                        tint: kind.prefersSharePrice ? nil : UIColor(kindTint),
                        titleInk: kind.prefersSharePrice ? nil : UIColor(knobInk)
                    ) { index in
                        usesSharePrice = index == 1
                        lumpShowsTwd = false
                    }
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    LabeledContent {
                        TextField("", text: $symbol)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .symbol)
                            .onChange(of: symbol) { old, new in
                                if old.trimmingCharacters(in: .whitespacesAndNewlines)
                                    != new.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    quoteState = .idle
                                }
                            }
                    } label: {
                        alignedTitle("股票代號")
                    }
                    .editable(usesSharePrice)
                    .listRowSeparator(.hidden)
                    LabeledContent {
                        TextField("", text: $sharesText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .shares)
                    } label: {
                        alignedTitle(isPledge ? "質押股數" : "股數")
                    }
                    .editable(usesSharePrice)
                    .listRowSeparator(.hidden)
                    LabeledContent {
                        HStack {
                            TextField("", text: $priceText)
                                .keyboardType(.decimalPad)
                                .focused($focus, equals: .price)
                                .editable(usesSharePrice)
                            Button { Task { await lookup() } } label: {
                                if quoteState == .quoting {
                                    ProgressView()
                                } else {
                                    Text(quoteButtonTitle)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(canQuote ? kindTint : .primary)
                            .accessibilityLabel(quoteButtonTitle)
                            .disabled(!canQuote)
                        }
                    } label: {
                        alignedTitle("單價")
                            .foregroundStyle(usesSharePrice ? Color.primary : Color.secondary)
                    }
                    .listRowSeparator(.hidden)
                    LabeledContent {
                        PaletteSegments(
                            titles: Self.leverageSteps.map(\.title),
                            index: Self.leverageSteps.firstIndex { $0.value == leverage } ?? 2,
                            enabled: kind == .leverage,
                            off: kind == .leverage ? [0] : [],
                            tint: kind == .leverage ? UIColor(kindTint) : nil,
                            titleInk: kind == .leverage ? UIColor(knobInk) : nil
                        ) { leverage = Self.leverageSteps[$0].value }
                    } label: {
                        alignedTitle("槓桿倍數")
                    }
                    .editable(kind == .leverage)
                    .listRowSeparator(.hidden, edges: .top)
                    LabeledContent {
                        HStack {
                            TextField("", text: $name)
                                .focused($focus, equals: .name)
                            Button("使用股票代號") {
                                name = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .buttonStyle(.bordered)
                            .tint(canCopySymbol ? kindTint : .primary)
                            .disabled(!canCopySymbol)
                        }
                    } label: {
                        alignedTitle("資產名稱")
                    }
                    LabeledContent {
                        Menu {
                            ForEach(AssetCurrency.allCases) { option in
                                Button {
                                    currency = option
                                } label: {
                                    if option == currency {
                                        Label(option.title, systemImage: "checkmark")
                                    } else {
                                        Text(option.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(currency.rawValue)
                                Image(systemName: "chevron.up.chevron.down")
                                    .imageScale(.small)
                            }
                        }
                        .tint(kindTint)
                    } label: {
                        alignedTitle("幣別")
                    }
                    .onChange(of: currency) { _, new in
                        rateState = .idle
                        lumpShowsTwd = false
                        guard new != .twd, let rate = RateBook.rate(for: new) else { return }
                        fullRate = rate
                        rateText = NumberParse.fx(rate)
                    }
                    .listRowSeparator(.hidden)
                    LabeledContent {
                        HStack {
                            if currency == .twd {
                                Text("1")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                TextField("匯率", text: $rateText)
                                    .keyboardType(.decimalPad)
                                    .focused($focus, equals: .rate)
                            }
                            Button { Task { await lookupRate() } } label: {
                                if rateState == .quoting || isRefreshingTotal {
                                    ProgressView()
                                } else {
                                    Text(rateButtonTitle)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(canLookupRate && !isRefreshingTotal ? kindTint : .primary)
                            .accessibilityLabel(rateButtonTitle)
                            .disabled(!canLookupRate || isRefreshingTotal)
                        }
                    } label: {
                        alignedTitle("幣值")
                    }
                }
                .listRowBackground(palette.panel)

                LabeledContent {
                    HStack {
                        if valueFollowsShares || lumpShowsTwd {
                            Text(MoneyFormat.string(valueFollowsShares ? liveTotal : lumpTwd))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField("", text: $amountText)
                                .keyboardType(.decimalPad)
                                .focused($focus, equals: .amount)
                        }
                        Button { Task { await refreshTotal() } } label: {
                            if isRefreshingTotal {
                                ProgressView()
                            } else {
                                Text("更新總金額")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(canRefreshTotal ? kindTint : .primary)
                        .accessibilityLabel("更新總金額")
                        .disabled(!canRefreshTotal)
                    }
                } label: {
                    alignedTitle(isPledge ? "借款金額" : "總金額")
                }
                .listRowBackground(palette.panel)

                if existingID != nil, onDelete != nil {
                    Button("刪除", role: .destructive) { confirmDelete = true }
                        .listRowBackground(palette.panel)
                }
            }
            .palettePanel(palette)
            .alert(deleteTitle, isPresented: $confirmDelete) {
                Button("刪除", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後會從清單移除。")
            }
            .onPreferenceChange(LabelWidthKey.self) { width in
                if width != labelWidth { labelWidth = width }
            }
            .scrollEdgeFade()
            .navigationTitle(existingID == nil ? "新增資產與負債" : "編輯資產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                        .tint(canSave ? kindTint : .primary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                }
            }
        }
        .presentationBackground(palette.panel)
        .presentationDetents([.medium, .large], selection: sheetDetent)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private var deleteTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "刪除這筆資產？" : "刪除「\(trimmed)」？"
    }

    private var sheetDetent: Binding<PresentationDetent> {
        Binding {
            detentID == "medium" ? .medium : .large
        } set: { detentID = $0 == .medium ? "medium" : "large" }
    }

    /// Debt entered as shares records a pledge. The loan is typed; shares and price are collateral.
    private var isPledge: Bool { kind == .debt && usesSharePrice }

    /// Share-priced holdings. A pledge keeps the typed loan instead.
    private var valueFollowsShares: Bool { kind.valueFollowsShares(usesSharePrice) }

    /// TWD total from shares, price, and the currency rate. Pledged loans use `lumpTwd`.
    private var liveTotal: Decimal {
        let shares = NumberParse.decimal(sharesText) ?? 0
        return shares * priceValue * rateValue
    }

    /// TWD value of the hand-entered amount. The typed amount itself stays put.
    private var lumpTwd: Decimal {
        (NumberParse.decimal(amountText) ?? 0) * rateValue
    }

    /// Shown rate is rounded. Keep the stored rate while the field still shows that rounding.
    private var rateValue: Decimal {
        if currency == .twd { return 1 }
        if rateText == NumberParse.fx(fullRate) { return fullRate }
        return NumberParse.decimal(rateText) ?? 0
    }

    /// Shown price is rounded to two places. Keep the stored price while the field still shows that rounding.
    private var priceValue: Decimal {
        if priceText == NumberParse.price(fullPrice) { return fullPrice }
        return NumberParse.decimal(priceText) ?? 0
    }

    /// Disabled while a refresh is running, or when there is nothing to reprice.
    /// The rate is fetched by the button itself. A share price can also be fetched when a ticker is present.
    private var canRefreshTotal: Bool {
        if isRefreshingTotal { return false }
        if valueFollowsShares {
            guard NumberParse.decimal(sharesText) != nil else { return false }
            if NumberParse.decimal(priceText) != nil { return true }
            return !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isPledge, !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return NumberParse.decimal(amountText) != nil
    }

    private func refreshTotal() async {
        guard !isRefreshingTotal else { return }
        isRefreshingTotal = true
        defer { isRefreshingTotal = false }
        if usesSharePrice {
            let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ticker.isEmpty { await lookup(force: true) }
        }
        let rateUpdated = await lookupRate(force: true)
        if !valueFollowsShares, rateUpdated, NumberParse.decimal(amountText) != nil {
            lumpShowsTwd = true
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if currency != .twd, NumberParse.decimal(rateText) == nil { return false }
        let quoted = NumberParse.decimal(sharesText) != nil && NumberParse.decimal(priceText) != nil
        if isPledge { return quoted && NumberParse.decimal(amountText) != nil }
        if usesSharePrice { return quoted }
        return NumberParse.decimal(amountText) != nil
    }

    private func save() {
        let rate = currency == .twd ? 1 : rateValue
        let shares = NumberParse.decimal(sharesText)
        let price = priceValue
        let amount = valueFollowsShares ? 0 : (NumberParse.decimal(amountText) ?? 0)
        guard amount >= 0, (shares ?? 0) >= 0, price >= 0 else { return }
        onSave(AssetItem(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            amount: amount,
            currency: currency,
            usdTwdRate: rate,
            usesSharePrice: usesSharePrice,
            shares: usesSharePrice ? shares : nil,
            price: usesSharePrice ? price : nil,
            leverageMultiple: kind == .leverage ? leverage : nil
        ))
        dismiss()
    }

    private var quoteButtonTitle: String {
        switch quoteState {
        case .idle, .quoting: "查詢單價"
        case .found: "已查得價格"
        case .missing: "查無價格"
        }
    }

    private func alignedTitle(_ title: String) -> some View {
        Text(title)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: LabelWidthKey.self, value: proxy.size.width)
                }
            }
            .frame(width: labelWidth > 0 ? labelWidth : nil, alignment: .leading)
    }

    private var canCopySymbol: Bool {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return !ticker.isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines) != ticker
    }

    private var canQuote: Bool {
        usesSharePrice && quoteState == .idle && !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func lookup(force: Bool = false) async {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticker.isEmpty, force || canQuote else { return }
        quoteState = .quoting
        let quote = try? await QuoteClient.fetch(symbol: ticker)
        guard symbol.trimmingCharacters(in: .whitespacesAndNewlines) == ticker else { return }
        guard let quote else {
            quoteState = .missing
            return
        }
        fullPrice = quote.price
        priceText = NumberParse.price(quote.price)
        if let currency = quote.currency { self.currency = currency }
        quoteState = .found
    }

    private var rateButtonTitle: String {
        switch rateState {
        case .idle, .quoting: "查詢幣值"
        case .found: "已查得幣值"
        case .missing: "查無幣值"
        }
    }

    private var canLookupRate: Bool {
        currency != .twd && rateState == .idle
    }

    private func lookupRate(force: Bool = false) async -> Bool {
        let code = currency
        guard force || (code != .twd && rateState == .idle) else { return false }
        rateState = .quoting
        let rates = try? await QuoteClient.fetchTwdRates()
        guard currency == code else { return false }
        guard let rates else {
            rateState = .missing
            return false
        }
        RateBook.merge(rates)
        if code == .twd {
            rateState = .found
            return true
        }
        guard let rate = rates[code] else {
            rateState = .missing
            return false
        }
        fullRate = rate
        rateText = NumberParse.fx(rate)
        rateState = .found
        return true
    }
}

private struct LabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum QuoteState {
    case idle, quoting, found, missing
}

private extension View {
    /// Gray text when the row cannot be edited.
    func editable(_ isEditable: Bool) -> some View {
        foregroundStyle(isEditable ? Color.primary : Color.secondary)
            .disabled(!isEditable)
    }
}

/// Segmented choices. The selected knob uses the kind color only while the control can be changed.
private struct PaletteSegments: UIViewRepresentable {
    var titles: [String]
    var index: Int
    var enabled: Bool
    var off: Set<Int> = []
    var tint: UIColor?
    var titleInk: UIColor?
    var select: (Int) -> Void

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.apportionsSegmentWidthsByContent = false
        control.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel], for: .disabled)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.select = select
        if control.numberOfSegments != titles.count {
            control.removeAllSegments()
            for (offset, title) in titles.enumerated() {
                control.insertSegment(withTitle: title, at: offset, animated: false)
            }
        }
        for (offset, title) in titles.enumerated() where control.titleForSegment(at: offset) != title {
            control.setTitle(title, forSegmentAt: offset)
        }
        let selected = titles.indices.contains(index) ? index : UISegmentedControl.noSegment
        if control.selectedSegmentIndex != selected {
            control.selectedSegmentIndex = selected
        }
        control.isEnabled = enabled
        if enabled {
            for segment in 0..<control.numberOfSegments {
                control.setEnabled(!off.contains(segment), forSegmentAt: segment)
            }
        }
        control.selectedSegmentTintColor = enabled ? tint : nil
        if enabled, let titleInk {
            control.setTitleTextAttributes([.foregroundColor: titleInk], for: .selected)
        } else {
            control.setTitleTextAttributes(nil, for: .selected)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    final class Coordinator: NSObject {
        var select: (Int) -> Void
        init(select: @escaping (Int) -> Void) { self.select = select }
        @objc func changed(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard index >= 0 else { return }
            select(index)
        }
    }
}
