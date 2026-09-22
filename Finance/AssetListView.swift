import SwiftUI

struct AssetListView: View {
    var showsChrome = true
    @Environment(Portfolio.self) private var portfolio
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var addKind: AssetKind = .original
    @State private var showTargets = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?

    var body: some View {
        List {
            if let refreshMessage {
                Text(refreshMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(AssetKind.allCases) { kind in
                let rows = portfolio.items(for: kind)
                Section {
                    if rows.isEmpty {
                        Text("尚無紀錄").foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { item in
                            Button { editing = item } label: {
                                AssetRow(item: item, hideAmounts: hideAmounts)
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { portfolio.delete(rows, at: $0) }
                    }
                } header: {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Text(MoneyFormat.string(portfolio.amount(for: kind), hidden: hideAmounts))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if showsChrome {
                            Button("新增") {
                                addKind = kind
                                showAdd = true
                            }
                            .font(.subheadline)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .navigationTitle(showsChrome ? "資產" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsChrome {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        hideAmounts.toggle()
                    } label: {
                        Image(systemName: hideAmounts ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(hideAmounts ? "顯示金額" : "隱藏金額")
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("目標配置") { showTargets = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addKind = .original
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增資產")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AssetEditor(item: nil, defaultKind: addKind) { portfolio.upsert($0) }
        }
        .sheet(item: $editing) { item in
            AssetEditor(item: item, onSave: { portfolio.upsert($0) }, onDelete: {
                portfolio.delete(ids: [item.id])
            })
        }
        .sheet(isPresented: $showTargets) {
            TargetEditor()
        }
    }

    private func refreshQuotes() async {
        let targets = portfolio.items.filter(\.canRefreshQuote)
        guard !targets.isEmpty else {
            refreshMessage = "沒有可更新的持股"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let quotes = await QuoteClient.fetchAll(
            symbols: Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.name) })
        )
        portfolio.applyQuotes(quotes)
        refreshMessage = quotes.isEmpty ? "更新失敗，現值未改" : "已更新 \(quotes.count) 筆現值"
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
                    Text(hideAmounts ? "••••" : "\(NumberParse.grouped(shares)) 股 · \(NumberParse.display(price))")
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
