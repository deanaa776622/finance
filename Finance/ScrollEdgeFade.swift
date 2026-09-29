import SwiftUI

enum ScrollFade {
    static let depth: CGFloat = 40

    static var top: some View {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            .frame(height: depth)
    }

    static var bottom: some View {
        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: depth)
    }
}

private struct ScrollEdgeFade: ViewModifier {
    var edges: Edge.Set

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                if edges.contains(.top) { ScrollFade.top }
                Color.black
                if edges.contains(.bottom) { ScrollFade.bottom }
            }
        }
    }
}

extension View {
    /// Default scroll-edge treatment: the same 40pt fade stays on the edges,
    /// whether or not the content currently runs past them.
    func scrollEdgeFade(edges: Edge.Set = .vertical) -> some View {
        modifier(ScrollEdgeFade(edges: edges))
    }
}
