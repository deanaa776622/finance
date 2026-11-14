import SwiftUI

/// Vertical join from the first group title down to the last open asset row.
struct StockLinkMark: View {
    var x: CGFloat
    var top: CGFloat
    var height: CGFloat
    var collapsed: Bool
    /// White when this group can still open into smaller groups. Gray at the leaf.
    var color: Color

    var body: some View {
        let length = max(height, 8)
        Capsule()
            .fill(color)
            .frame(width: 1.5, height: length)
            .scaleEffect(y: collapsed ? 0.001 : 1, anchor: .center)
            .opacity(collapsed ? 0 : 1)
            .position(x: x, y: top + length / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

/// White rail beside one group: from the title’s top through its last open row.
struct GroupRail: View {
    var title: CGRect?
    var bottom: CGFloat?
    var origin: CGPoint

    var body: some View {
        if let span {
            StockLinkMark(
                x: span.x,
                top: span.top,
                height: span.height,
                collapsed: false,
                color: Color.primary.opacity(0.85)
            )
            .allowsHitTesting(false)
        }
    }

    /// Same 16pt inset as the asset-group line.
    private var span: (x: CGFloat, top: CGFloat, height: CGFloat)? {
        guard let title, title.height > 1 else { return nil }
        let top = title.minY - origin.y
        let end = max(title.maxY, bottom ?? title.maxY) - origin.y
        let height = end - top
        guard height > 1 else { return nil }
        return (title.minX - origin.x - 16, top, height)
    }
}

extension View {
    /// Tap strip in the margin to the left of this view. `margin` is its width; it does not cover the view.
    func stockLinkHit(enabled: Bool, margin: CGFloat, action: @escaping () -> Void) -> some View {
        overlay(alignment: .leading) {
            if enabled {
                Color.clear
                    .frame(width: margin)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .offset(x: -margin)
                    .onTapGesture(perform: action)
                    .accessibilityHidden(true)
            }
        }
    }
}
