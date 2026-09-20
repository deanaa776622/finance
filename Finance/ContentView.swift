import SwiftUI

struct ContentView: View {
    @Environment(Portfolio.self) private var portfolio
    @State private var editing: AssetItem?
    @State private var showAdd = false
    @State private var showTargets = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("總淨值")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(MoneyFormat.string(portfolio.netWorth))
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text(portfolio.allocationStatus)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section("資產") {
                    if portfolio.items.isEmpty {
                        Text("還沒有記錄。先加一筆你長期持有的資產。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(portfolio.items) { item in
                            Button { editing = item } label: { AssetRow(item: item) }
                                .foregroundStyle(.primary)
                        }
                        .onDelete(perform: portfolio.delete)
                    }
                }
            }
            .navigationTitle("資產")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("目標配置") { showTargets = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增資產")
                }
            }
            .sheet(isPresented: $showAdd) {
                AssetEditor(item: nil) { portfolio.upsert($0) }
            }
            .sheet(item: $editing) { item in
                AssetEditor(item: item) { portfolio.upsert($0) }
            }
            .sheet(isPresented: $showTargets) {
                TargetEditor()
            }
        }
    }
}

private struct AssetRow: View {
    let item: AssetItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormat.string(item.amount))
                .monospacedDigit()
                .foregroundStyle(item.kind == .debt ? .secondary : .primary)
        }
    }
}

#Preview {
    ContentView()
        .environment(Portfolio(items: [
            AssetItem(name: "全球股票 ETF", kind: .investment, amount: 1_200_000),
            AssetItem(name: "活存", kind: .cash, amount: 300_000),
        ]))
}
