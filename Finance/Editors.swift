import SwiftUI

struct AssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var name: String
    @State private var kind: AssetKind
    @State private var amountText: String
    private let existingID: UUID?
    var onSave: (AssetItem) -> Void

    init(item: AssetItem?, onSave: @escaping (AssetItem) -> Void) {
        existingID = item?.id
        _name = State(initialValue: item?.name ?? "")
        _kind = State(initialValue: item?.kind ?? .original)
        _amountText = State(initialValue: item.map { NumberParse.display($0.amount) } ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $name)
                Picker("類別", selection: $kind) {
                    ForEach(AssetKind.allCases) { Text($0.title).tag($0) }
                }
                TextField("金額", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                    Button("完成") { amountFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && NumberParse.decimal(amountText) != nil
    }

    private func save() {
        guard let amount = NumberParse.decimal(amountText), amount >= 0 else { return }
        onSave(AssetItem(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            amount: amount
        ))
        dismiss()
    }
}

struct TargetEditor: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(\.dismiss) private var dismiss
    @FocusState private var field: Field?

    @State private var totalText = ""
    @State private var originalText = ""
    @State private var leverageText = ""
    @State private var cashText = ""

    private enum Field: Hashable { case total, original, leverage, cash }

    var body: some View {
        NavigationStack {
            Form {
                Text("以長期配置為準。偏離約 10% 內可視為大致平衡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)

                Section {
                    if portfolio.savings != nil {
                        LabeledContent("目標總額") {
                            Text(portfolio.targetFromSavings.map(MoneyFormat.string) ?? "—")
                        }
                    } else {
                        HStack {
                            Text("目標總額")
                            Spacer()
                            TextField("選填", text: $totalText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($field, equals: .total)
                                .frame(minWidth: 120)
                        }
                    }
                } footer: {
                    Text(
                        portfolio.savings == nil
                            ? "光球依達成率長大。留空則以目前持有總額為基準。"
                            : "由儲蓄目標的年花費 ÷ 報酬率推算。"
                    )
                }

                Section("目標比例") {
                    percentRow("原型", text: $originalText, field: .original)
                    percentRow("槓桿", text: $leverageText, field: .leverage)
                    percentRow("現金", text: $cashText, field: .cash)
                }
            }
            .navigationTitle("目標配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { field = nil }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func percentRow(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("％", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($field, equals: field)
                .frame(width: 72)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private func load() {
        totalText = portfolio.targetTotal.map(NumberParse.display) ?? ""
        originalText = NumberParse.displayPercent(portfolio.targets.original)
        leverageText = NumberParse.displayPercent(portfolio.targets.leverage)
        cashText = NumberParse.displayPercent(portfolio.targets.cash)
    }

    private func commit() {
        if portfolio.savings == nil {
            if totalText.trimmingCharacters(in: .whitespaces).isEmpty {
                portfolio.targetTotal = nil
            } else if let total = NumberParse.decimal(totalText), total > 0 {
                portfolio.targetTotal = total
            }
        }
        if let v = NumberParse.double(originalText) { portfolio.targets.original = v }
        if let v = NumberParse.double(leverageText) { portfolio.targets.leverage = v }
        if let v = NumberParse.double(cashText) { portfolio.targets.cash = v }
        portfolio.save()
    }
}
