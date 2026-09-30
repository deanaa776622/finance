import SwiftUI

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
    private let existingID: UUID?
    var onSave: (AssetItem) -> Void
    var onDelete: (() -> Void)?

    private enum Field: Hashable { case symbol, shares, price, amount, rate }

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
                Section("類別") {
                    Picker("類別", selection: $kind) {
                        ForEach(AssetKind.allCases) { Text($0.compactTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onChange(of: kind) { _, new in
                        if new.prefersSharePrice { usesSharePrice = true }
                        leverage = Self.clampedLeverage(kind: new, value: leverage)
                    }
                }

                Section("輸入方式") {
                    Picker("輸入方式", selection: $usesSharePrice) {
                        Text("總金額").tag(false)
                        Text("股數與單價").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(kind.prefersSharePrice)
                    HStack {
                        TextField("股票代號", text: $symbol)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .symbol)
                            .onChange(of: symbol) { old, new in
                                if old.trimmingCharacters(in: .whitespacesAndNewlines)
                                    != new.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    quoteState = .idle
                                }
                            }
                            .disabled(!usesSharePrice)
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
                    HStack {
                        TextField("資產名稱", text: $name)
                        Button("使用股票代號") {
                            name = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Picker("幣別", selection: $currency) {
                        ForEach(AssetCurrency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    TextField("\(currency.rawValue) → TWD 匯率", text: $rateText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .rate)
                        .disabled(currency == .twd)
                }

                Section("槓桿倍數") {
                    Picker("槓桿倍數", selection: $leverage) {
                        Text("1×").tag(1.0)
                        Text("1.5×").tag(1.5)
                        Text("2×").tag(2.0)
                        Text("3×").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(kind != .leverage)
                    .onChange(of: leverage) { old, new in
                        if kind == .leverage, new == 1 {
                            leverage = old == 1 ? 2 : old
                        }
                    }
                }

                TextField("股數", text: $sharesText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .shares)
                    .disabled(!usesSharePrice)
                TextField("單價", text: $priceText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .price)
                    .disabled(!usesSharePrice)
                TextField("總金額", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .disabled(usesSharePrice)

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
        case .idle, .quoting: "查價"
        case .found: "已查得價格"
        case .missing: "查無價格"
        }
    }

    private var canQuote: Bool {
        usesSharePrice && quoteState == .idle && !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func lookup() async {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canQuote else { return }
        quoteState = .quoting
        let quote = try? await QuoteClient.fetch(symbol: ticker)
        guard symbol.trimmingCharacters(in: .whitespacesAndNewlines) == ticker else { return }
        guard let quote else {
            quoteState = .missing
            return
        }
        priceText = NumberParse.price(quote.price)
        if let currency = quote.currency { self.currency = currency }
        if self.currency == .usd {
            var rate = quote.usdTwdRate
            if rate == nil { rate = try? await QuoteClient.fetchUsdTwd() }
            guard symbol.trimmingCharacters(in: .whitespacesAndNewlines) == ticker else { return }
            if let rate { rateText = NumberParse.oneDecimal(rate) }
        }
        quoteState = .found
    }
}

private enum QuoteState {
    case idle, quoting, found, missing
}
