import SwiftUI

struct AssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var name: String
    @State private var kind: AssetKind
    @State private var currency: AssetCurrency
    @State private var rateText: String
    @State private var usesSharePrice: Bool
    @State private var sharesText: String
    @State private var priceText: String
    @State private var amountText: String
    @State private var leverage: Double
    @State private var quoteHint: String?
    @State private var isQuoting = false
    private let existingID: UUID?
    var onSave: (AssetItem) -> Void
    var onDelete: (() -> Void)?

    private enum Field: Hashable { case name, shares, price, amount, rate }

    init(
        item: AssetItem?,
        defaultKind: AssetKind = .original,
        onSave: @escaping (AssetItem) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        existingID = item?.id
        let kind = item?.kind ?? defaultKind
        _name = State(initialValue: item?.name ?? "")
        _kind = State(initialValue: kind)
        _currency = State(initialValue: item?.currency ?? .twd)
        _rateText = State(initialValue: NumberParse.display(item?.usdTwdRate ?? 32))
        _usesSharePrice = State(initialValue: item?.usesSharePrice ?? kind.prefersSharePrice)
        _sharesText = State(initialValue: item?.shares.map(NumberParse.display) ?? "")
        _priceText = State(initialValue: item?.price.map(NumberParse.display) ?? "")
        _amountText = State(initialValue: item.map { NumberParse.display($0.amount) } ?? "")
        _leverage = State(initialValue: item?.leverageMultiple ?? 2)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("類別", selection: $kind) {
                    ForEach(AssetKind.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: kind) { _, new in
                    if new.prefersSharePrice { usesSharePrice = true }
                }

                Picker("輸入方式", selection: $usesSharePrice) {
                    Text("總金額").tag(false)
                    Text("股數與單價").tag(true)
                }
                .disabled(kind.prefersSharePrice && usesSharePrice)

                TextField("名稱 / 代號", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                    .onChange(of: focus) { _, new in
                        if new != .name { Task { await lookup() } }
                    }

                if usesSharePrice {
                    Button("查價") { Task { await lookup() } }
                        .disabled(isQuoting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isQuoting {
                        Text("正在查詢現值…").font(.footnote).foregroundStyle(.secondary)
                    } else if let quoteHint {
                        Text(quoteHint).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Picker("幣別", selection: $currency) {
                    ForEach(AssetCurrency.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if currency == .usd {
                    TextField("USD → TWD 匯率", text: $rateText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .rate)
                }

                if kind == .leverage {
                    Picker("槓桿倍數", selection: $leverage) {
                        Text("1.5×").tag(1.5)
                        Text("2×").tag(2.0)
                        Text("3×").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                }

                if usesSharePrice {
                    TextField("股數", text: $sharesText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .shares)
                    TextField("單價", text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .price)
                } else {
                    TextField("總金額", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .amount)
                }

                if existingID != nil, onDelete != nil {
                    Button("刪除", role: .destructive) {
                        onDelete?()
                        dismiss()
                    }
                }
            }
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
        if currency == .usd, NumberParse.decimal(rateText) == nil { return false }
        if usesSharePrice {
            return NumberParse.decimal(sharesText) != nil && NumberParse.decimal(priceText) != nil
        }
        return NumberParse.decimal(amountText) != nil
    }

    private func save() {
        let rate = currency == .usd ? (NumberParse.decimal(rateText) ?? 32) : 1
        let shares = NumberParse.decimal(sharesText)
        let price = NumberParse.decimal(priceText)
        let amount = usesSharePrice ? 0 : (NumberParse.decimal(amountText) ?? 0)
        guard amount >= 0, (shares ?? 0) >= 0, (price ?? 0) >= 0 else { return }
        onSave(AssetItem(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func lookup() async {
        let symbol = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard usesSharePrice, !symbol.isEmpty else { return }
        isQuoting = true
        quoteHint = nil
        defer { isQuoting = false }
        do {
            let quote = try await QuoteClient.fetch(symbol: symbol)
            priceText = NumberParse.display(quote.price)
            if let currency = quote.currency { self.currency = currency }
            if let rate = quote.usdTwdRate { rateText = NumberParse.display(rate) }
            quoteHint = "已填入現值"
        } catch {
            quoteHint = "查不到，請手動輸入單價"
        }
    }
}
