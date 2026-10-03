import SwiftUI
import UIKit

struct AssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var name: String
    @State private var symbol: String
    @State private var kind: AssetKind
    @State private var currency: AssetCurrency
    @State private var rateText: String
    @State private var usesSharePrice: Bool
    @State private var sharesText: String
    @State private var priceText: String
    @State private var amountText: String
    @State private var leverage: Double
    @State private var quoteState: QuoteState = .idle
    @State private var rateState: QuoteState = .idle
    @State private var isRefreshingTotal = false
    @State private var lumpShowsTwd = false
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
        _rateText = State(initialValue: NumberParse.oneDecimal(item?.usdTwdRate ?? 32))
        _usesSharePrice = State(initialValue: item?.usesSharePrice ?? kind.prefersSharePrice)
        _sharesText = State(initialValue: item?.shares.map(NumberParse.display) ?? "")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("輸入方式") {
                    Picker("類別", selection: $kind) {
                        ForEach(AssetKind.allCases) { Text($0.compactTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowSeparator(.hidden)
                    .onChange(of: kind) { _, new in
                        if new.prefersSharePrice { usesSharePrice = true }
                        leverage = Self.clampedLeverage(kind: new, value: leverage)
                    }
                    Picker("輸入方式", selection: $usesSharePrice) {
                        Text("總金額").tag(false)
                        Text("股數與單價").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .editable(!kind.prefersSharePrice)
                    .onChange(of: usesSharePrice) { _, _ in
                        lumpShowsTwd = false
                    }
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    LabeledContent("股票代號") {
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
                    }
                    .editable(usesSharePrice)
                    .listRowSeparator(.hidden)
                    LabeledContent("股數") {
                        TextField("", text: $sharesText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .shares)
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
                            .tint(.white)
                            .accessibilityLabel(quoteButtonTitle)
                            .disabled(!canQuote)
                        }
                    } label: {
                        Text("單價")
                            .foregroundStyle(usesSharePrice ? .primary : .secondary)
                    }
                    .listRowSeparator(.hidden)
                    LabeledContent("槓桿倍數") {
                        LeveragePicker(leverage: $leverage, oneTimesEnabled: kind != .leverage)
                    }
                    .editable(kind == .leverage)
                    .listRowSeparator(.hidden, edges: .top)
                    LabeledContent("資產名稱") {
                        HStack {
                            TextField("", text: $name)
                                .focused($focus, equals: .name)
                            Button("使用股票代號") {
                                name = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .disabled(symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    LabeledContent("幣別") {
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
                        .tint(.white)
                    }
                    .onChange(of: currency) { _, new in
                        rateState = .idle
                        lumpShowsTwd = false
                        guard new != .twd, let rate = RateBook.rate(for: new) else { return }
                        rateText = NumberParse.fx(rate)
                    }
                    .listRowSeparator(.hidden)
                    LabeledContent("幣值") {
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
                                if rateState == .quoting {
                                    ProgressView()
                                } else {
                                    Text(rateButtonTitle)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityLabel(rateButtonTitle)
                            .disabled(!canLookupRate)
                        }
                    }
                }

                LabeledContent("總金額") {
                    HStack {
                        if usesSharePrice || lumpShowsTwd {
                            Text(MoneyFormat.string(usesSharePrice ? liveTotal : lumpTwd))
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
                        .tint(.white)
                        .accessibilityLabel("更新總金額")
                        .disabled(!canRefreshTotal)
                    }
                }

                if existingID != nil, onDelete != nil {
                    Button("刪除", role: .destructive) {
                        onDelete?()
                        dismiss()
                    }
                }
            }
            .scrollEdgeFade()
            .navigationTitle(existingID == nil ? "新增資產" : "編輯資產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// TWD total from shares, price, and the currency rate. Matches `AssetItem.twdValue`.
    private var liveTotal: Decimal {
        let shares = NumberParse.decimal(sharesText) ?? 0
        let price = NumberParse.decimal(priceText) ?? 0
        return shares * price * rateValue
    }

    /// TWD value of the hand-entered amount. The typed amount itself stays put.
    private var lumpTwd: Decimal {
        (NumberParse.decimal(amountText) ?? 0) * rateValue
    }

    private var rateValue: Decimal {
        currency == .twd ? 1 : (NumberParse.decimal(rateText) ?? 0)
    }

    private var canRefreshTotal: Bool {
        if isRefreshingTotal { return false }
        if usesSharePrice {
            let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return !ticker.isEmpty || currency != .twd
        }
        guard NumberParse.decimal(amountText) != nil else { return false }
        return currency == .twd || NumberParse.decimal(rateText) != nil
    }

    private func refreshTotal() async {
        guard canRefreshTotal else { return }
        if !usesSharePrice {
            lumpShowsTwd = true
            return
        }
        isRefreshingTotal = true
        defer { isRefreshingTotal = false }
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ticker.isEmpty { await lookup(force: true) }
        if currency != .twd { await lookupRate(force: true) }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if currency != .twd, NumberParse.decimal(rateText) == nil { return false }
        if usesSharePrice {
            return NumberParse.decimal(sharesText) != nil && NumberParse.decimal(priceText) != nil
        }
        return NumberParse.decimal(amountText) != nil
    }

    private func save() {
        let rate = currency == .twd ? 1 : (NumberParse.decimal(rateText) ?? 32)
        let shares = NumberParse.decimal(sharesText)
        let price = NumberParse.decimal(priceText)
        let amount = usesSharePrice ? 0 : (NumberParse.decimal(amountText) ?? 0)
        guard amount >= 0, (shares ?? 0) >= 0, (price ?? 0) >= 0 else { return }
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

    private func lookupRate(force: Bool = false) async {
        let code = currency
        guard code != .twd, force || rateState == .idle else { return }
        rateState = .quoting
        let rates = try? await QuoteClient.fetchTwdRates()
        guard currency == code else { return }
        guard let rates, let rate = rates[code] else {
            rateState = .missing
            return
        }
        RateBook.merge(rates)
        rateText = NumberParse.fx(rate)
        rateState = .found
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

/// Segmented leverage choices. 1× is disabled, and therefore gray, for leverage assets.
private struct LeveragePicker: UIViewRepresentable {
    @Binding var leverage: Double
    var oneTimesEnabled: Bool

    private static let choices: [Double] = [1, 1.5, 2, 3]

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: Self.choices.map(Self.title))
        control.apportionsSegmentWidthsByContent = false
        control.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel], for: .disabled)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.leverage = $leverage
        let index = Self.choices.firstIndex(of: leverage) ?? 2
        if control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
        control.setEnabled(oneTimesEnabled, forSegmentAt: 0)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(leverage: $leverage)
    }

    private static func title(_ value: Double) -> String {
        value == 1.5 ? "1.5×" : "\(Int(value))×"
    }

    final class Coordinator: NSObject {
        var leverage: Binding<Double>

        init(leverage: Binding<Double>) {
            self.leverage = leverage
        }

        @objc func changed(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard choices.indices.contains(index) else { return }
            leverage.wrappedValue = choices[index]
        }

        private var choices: [Double] { LeveragePicker.choices }
    }
}
