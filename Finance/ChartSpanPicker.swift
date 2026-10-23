import SwiftUI

enum ChartSpan: String, CaseIterable, Identifiable {
    case thisYear, year, all, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisYear: "今年"
        case .year: "年"
        case .all: "全部"
        case .custom: "自訂"
        }
    }
}

/// Range labels on the chart's month row. The highlight slides, like the Stocks app.
struct ChartSpanPicker: View {
    @Binding var span: ChartSpan
    var onEditCustom: () -> Void
    @Environment(Palette.self) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    @State private var width: CGFloat = 1

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartSpan.allCases) { item in
                Button {
                    span = item
                    if item == .custom { onEditCustom() }
                } label: {
                    Text(item.title)
                        .font(.footnote)
                        .foregroundStyle(span == item ? palette.ink : palette.quietInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if span == item {
                                Capsule()
                                    .fill(palette.ink.opacity(0.12))
                                    .matchedGeometryEffect(id: "span", in: pill)
                            }
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(span == item ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: span)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(slide)
        .accessibilityLabel("時間範圍")
    }

    /// A horizontal slide moves the selection. A vertical flick still scrolls the list.
    private var slide: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                let count = ChartSpan.allCases.count
                let slot = width / CGFloat(count)
                guard slot > 0 else { return }
                let index = min(count - 1, max(0, Int(drag.location.x / slot)))
                let next = ChartSpan.allCases[index]
                if next != span { span = next }
            }
    }
}

/// Start and end of a custom window. The chart keeps the months those dates fall in.
struct ChartSpanEditor: View {
    @Binding var start: Date
    @Binding var end: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("開始", selection: $start, displayedComponents: .date)
                DatePicker("結束", selection: $end, displayedComponents: .date)
            }
            .navigationTitle("自訂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
