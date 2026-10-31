import SwiftUI

/// Enter one past month's five totals. The month must have no records yet.
struct MonthBackfillView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var amounts: [AssetKind: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("月份", selection: $date, displayedComponents: .date)
                        .listRowBackground(palette.panel)
                } footer: {
                    Text(note)
                }
                Section {
                    ForEach(AssetKind.allCases) { kind in
                        TextField(kind.compactTitle, text: text(for: kind))
                            .keyboardType(.decimalPad)
                            .listRowBackground(palette.panel)
                    }
                } footer: {
                    Text("金額為台幣。空白視為 0，負債填正數。")
                }
            }
            .palettePanel(palette)
            .scrollEdgeFade()
            .navigationTitle("補登")
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
        .presentationBackground(palette.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var month: String { AssetHistory.monthKey(date) }

    private var note: String {
        if month >= AssetHistory.monthKey() { return "只能補登過去的月份" }
        if !portfolio.canBackfill(month) { return "這個月已有紀錄，不能補登" }
        return "以所選日期的月份為準。五類都還沒有紀錄才能補。"
    }

    private var parsed: [AssetKind: Decimal]? {
        var out: [AssetKind: Decimal] = [:]
        for kind in AssetKind.allCases {
            let raw = (amounts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                out[kind] = 0
                continue
            }
            guard let value = NumberParse.decimal(raw), value >= 0 else { return nil }
            out[kind] = value
        }
        return out
    }

    private var canSave: Bool {
        guard portfolio.canBackfill(month), let parsed else { return false }
        return parsed.values.contains { $0 > 0 }
    }

    private func text(for kind: AssetKind) -> Binding<String> {
        Binding(
            get: { amounts[kind, default: ""] },
            set: { amounts[kind] = $0 }
        )
    }

    private func save() {
        guard canSave, let parsed else { return }
        portfolio.addBackfill(MonthBackfill(
            month: month,
            original: parsed[.original] ?? 0,
            leverage: parsed[.leverage] ?? 0,
            cash: parsed[.cash] ?? 0,
            realEstate: parsed[.realEstate] ?? 0,
            debt: parsed[.debt] ?? 0
        ))
        dismiss()
    }
}
