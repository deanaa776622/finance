import SwiftUI

/// Vertical join from the first group title down to the last open asset row.
struct StockLinkMark: View {
    var x: CGFloat
    var top: CGFloat
    var height: CGFloat
    var collapsed: Bool

    var body: some View {
        let length = max(height, 8)
        Capsule()
            .fill(Color.white.opacity(0.85))
            .frame(width: 1.5, height: length)
            .scaleEffect(y: collapsed ? 0.001 : 1, anchor: .center)
            .opacity(collapsed ? 0 : 1)
            .position(x: x, y: top + length / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
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
