import SwiftUI

struct AssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: AssetKind
    @State private var amountText: String
    private let existingID: UUID?
    var onSave: (AssetItem) -> Void

    init(item: AssetItem?, onSave: @escaping (AssetItem) -> Void) {
        existingID = item?.id
        _name = State(initialValue: item?.name ?? "")
        _kind = State(initialValue: item?.kind ?? .investment)
        if let amount = item?.amount {
            _amountText = State(initialValue: NSDecimalNumber(decimal: amount).stringValue)
        } else {
            _amountText = State(initialValue: "")
        }
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
            }
        }
        .presentationDetents([.medium])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Decimal(string: amountText) != nil
    }

    private func save() {
        guard let amount = Decimal(string: amountText), amount >= 0 else { return }
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

    var body: some View {
        @Bindable var portfolio = portfolio
        NavigationStack {
            Form {
                Text("以長期配置為準。偏離約 10% 內可視為大致平衡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)

                ForEach(AssetKind.allCases.filter(\.countsTowardAllocation)) { kind in
                    HStack {
                        Text(kind.title)
                        Spacer()
                        TextField(
                            "％",
                            value: Binding(
                                get: { portfolio.targets.percent(for: kind) },
                                set: {
                                    portfolio.targets.setPercent($0, for: kind)
                                    portfolio.save()
                                }
                            ),
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("目標配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
