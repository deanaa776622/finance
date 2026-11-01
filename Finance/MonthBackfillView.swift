import SwiftUI

/// Enter one past month's asset total and debt. A month already filled in here can be edited.
struct MonthBackfillView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var monthIndex: Int
    @State private var assetsText = ""
    @State private var debtText = ""
    @State private var confirmDelete = false

    init() {
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let parts = Calendar.current.dateComponents([.year, .month], from: previous)
        _year = State(initialValue: parts.year ?? 2020)
        _monthIndex = State(initialValue: parts.month ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("年", selection: $year) {
                        ForEach(years, id: \.self) { value in
                            Text(verbatim: "\(value)年").tag(value)
                        }
                    }
                    .tint(palette.ink)
                    .foregroundStyle(palette.ink)
                    .listRowBackground(palette.panel)
                    Picker("月", selection: $monthIndex) {
                        ForEach(months, id: \.self) { value in
                            Text("\(value)月").tag(value)
                        }
                    }
                    .tint(palette.ink)
                    .foregroundStyle(palette.ink)
                    .listRowBackground(palette.panel)
                } footer: {
                    if !portfolio.canBackfill(month) {
                        Text("這個月已有紀錄，不能補登")
                    }
                }
                .onChange(of: year) {
                    if !months.contains(monthIndex) { monthIndex = months.last ?? 1 }
                    loadMonth()
                }
                .onChange(of: monthIndex) { loadMonth() }
                Section {
                    amountRow("資產", text: $assetsText, debt: false)
                    amountRow("負債", text: $debtText, debt: true)
                }
                if hasBackfill {
                    Section {
                        Button("刪除", role: .destructive) { confirmDelete = true }
                            .listRowBackground(palette.panel)
                    }
                }
            }
            .palettePanel(palette)
            .scrollEdgeFade()
            .alert("刪除這個月的補登？", isPresented: $confirmDelete) {
                Button("刪除", role: .destructive) {
                    portfolio.removeBackfill(month)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後，這個月不再有補登金額。")
            }
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
        .onAppear { loadMonth() }
    }

    private var month: String { String(format: "%04d-%02d", year, monthIndex) }

    /// Past years only. The current year stops at last month.
    private var years: [Int] {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let thisYear = now.year ?? 2020
        let end = (now.month ?? 1) <= 1 ? thisYear - 1 : thisYear
        return Array((end - 40)...end).reversed()
    }

    private var months: [Int] {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let last = year == now.year ? max(1, (now.month ?? 1) - 1) : 12
        return Array(1...last)
    }

    private func amountRow(_ title: String, text: Binding<String>, debt: Bool) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                if debt {
                    Text("−")
                        .foregroundStyle(palette.quietInk)
                        .accessibilityHidden(true)
                }
                Text(MoneyFormat.currency.symbol)
                    .foregroundStyle(palette.quietInk)
                    .accessibilityHidden(true)
                TextField("", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } label: {
            Text(title)
                .foregroundStyle(portfolio.canBackfill(month) ? palette.ink : palette.quietInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(MoneyFormat.currency.rawValue)")
        .listRowBackground(palette.panel)
    }

    private func loadMonth() {
        guard let row = portfolio.backfills.first(where: { $0.month == month }) else {
            assetsText = ""
            debtText = ""
            return
        }
        assetsText = row.assets == 0 ? "" : NumberParse.display(row.assets)
        debtText = row.debt == 0 ? "" : NumberParse.display(row.debt)
    }

    private var hasBackfill: Bool {
        portfolio.backfills.contains { $0.month == month }
    }

    private var assets: Decimal? { amount(assetsText) }
    private var debt: Decimal? { amount(debtText) }

    private func amount(_ text: String) -> Decimal? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return 0 }
        guard let value = NumberParse.decimal(raw), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard portfolio.canBackfill(month), let assets, let debt else { return false }
        return assets > 0 || debt > 0
    }

    private func save() {
        guard canSave, let assets, let debt else { return }
        portfolio.addBackfill(MonthBackfill(month: month, assets: assets, debt: debt))
        dismiss()
    }
}
