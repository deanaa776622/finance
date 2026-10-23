import SwiftUI
import UIKit

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

/// Same glass segments as the asset editor's five kinds, so the knob moves at that speed.
struct ChartSpanPicker: View {
    @Binding var span: ChartSpan
    var onEditCustom: () -> Void

    var body: some View {
        SpanSegments(
            titles: ChartSpan.allCases.map(\.title),
            index: ChartSpan.allCases.firstIndex(of: span) ?? 0,
            select: { index in
                guard ChartSpan.allCases.indices.contains(index) else { return }
                span = ChartSpan.allCases[index]
            },
            editCustom: onEditCustom
        )
    }
}

/// System segmented control. Its selected knob is the glass slider.
private struct SpanSegments: UIViewRepresentable {
    var titles: [String]
    var index: Int
    var select: (Int) -> Void
    var editCustom: () -> Void

    func makeUIView(context: Context) -> SpanControl {
        let control = SpanControl(items: titles)
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentIndex = index
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        context.coordinator.editCustom = editCustom
        control.onReselect = { [weak coordinator = context.coordinator] index in
            guard ChartSpan.allCases.indices.contains(index), ChartSpan.allCases[index] == .custom else { return }
            coordinator?.editCustom()
        }
        return control
    }

    func updateUIView(_ control: SpanControl, context: Context) {
        context.coordinator.select = select
        context.coordinator.editCustom = editCustom
        guard !control.isTracking else { return }
        let selected = titles.indices.contains(index) ? index : UISegmentedControl.noSegment
        if control.selectedSegmentIndex != selected {
            control.selectedSegmentIndex = selected
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SpanControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(select: select, editCustom: editCustom) }

    final class Coordinator: NSObject {
        var select: (Int) -> Void
        var editCustom: () -> Void
        init(select: @escaping (Int) -> Void, editCustom: @escaping () -> Void) {
            self.select = select
            self.editCustom = editCustom
        }

        @objc func changed(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard index >= 0 else { return }
            select(index)
            // A drag keeps tracking until the finger lifts, so the editor waits for a tap.
            guard !sender.isTracking, ChartSpan.allCases.indices.contains(index), ChartSpan.allCases[index] == .custom else { return }
            editCustom()
        }
    }
}

private final class SpanControl: UISegmentedControl, UIGestureRecognizerDelegate {
    var onReselect: ((Int) -> Void)?

    override init(items: [Any]?) {
        super.init(items: items)
        let claim = TouchClaim()
        claim.cancelsTouchesInView = false
        claim.delaysTouchesBegan = false
        claim.delaysTouchesEnded = false
        claim.delegate = self
        addGestureRecognizer(claim)
    }

    required init?(coder: NSCoder) { return nil }

    /// The home screen's drag starts on any touch and would cancel this control.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        guard let view = other.view else { return false }
        return view !== self && !view.isDescendant(of: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let before = selectedSegmentIndex
        super.touchesEnded(touches, with: event)
        guard let point = touches.first?.location(in: self), numberOfSegments > 0, bounds.width > 0 else { return }
        let index = Int(point.x / (bounds.width / CGFloat(numberOfSegments)))
        guard index == before, index == selectedSegmentIndex else { return }
        onReselect?(index)
    }
}

/// Holds the touch so an ancestor drag cannot cancel the glass knob.
private final class TouchClaim: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .began
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}

/// Start and end of a custom window. The chart keeps the months those dates fall in.
struct ChartSpanEditor: View {
    @Binding var start: Date
    @Binding var end: Date
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("開始", selection: $start, displayedComponents: .date)
                    .listRowBackground(palette.panel)
                DatePicker("結束", selection: $end, displayedComponents: .date)
                    .listRowBackground(palette.panel)
            }
            .palettePanel(palette)
            .scrollEdgeFade()
            .navigationTitle("自訂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationBackground(palette.panel)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
