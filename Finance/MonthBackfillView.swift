import SwiftUI

/// Enter one past month's asset total and debt. The month must have no records yet.
struct MonthBackfillView: View {
    @Environment(Portfolio.self) private var portfolio
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var monthIndex: Int
    @State private var assetsText = ""
    @State private var debtText = ""

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
                    .listRowBackground(palette.panel)
                    Picker("月", selection: $monthIndex) {
                        ForEach(months, id: \.self) { value in
                            Text("\(value)月").tag(value)
                        }
                    }
                    .listRowBackground(palette.panel)
                } footer: {
                    if !portfolio.canBackfill(month) {
                        Text("這個月已有紀錄，不能補登")
                    }
                }
                .onChange(of: year) {
                    if !months.contains(monthIndex) { monthIndex = months.last ?? 1 }
                }
                Section {
                    TextField("資產", text: $assetsText)
                        .keyboardType(.decimalPad)
                        .listRowBackground(palette.panel)
                    HStack(spacing: 2) {
                        Text("−")
                            .foregroundStyle(palette.quietInk)
                            .accessibilityHidden(true)
                        TextField("負債", text: $debtText)
                            .keyboardType(.decimalPad)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("負債")
                    .listRowBackground(palette.panel)
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
