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
    /// Keep the top fade even when the scroll view is at rest, as under the status bar.
    var pinsTop: Bool
    @State private var fadeTop: Bool
    @State private var fadeBottom = false

    init(edges: Edge.Set, pinsTop: Bool) {
        self.edges = edges
        self.pinsTop = pinsTop
        _fadeTop = State(initialValue: pinsTop && edges.contains(.top))
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: EdgeFades.self) { geo in
                EdgeFades(
                    top: edges.contains(.top) && (pinsTop || geo.visibleRect.minY > 1),
                    bottom: edges.contains(.bottom) && geo.contentSize.height - geo.visibleRect.maxY > 1
                )
            } action: { _, fades in
                fadeTop = fades.top
                fadeBottom = fades.bottom
            }
            .onChange(of: pinsTop) { _, pin in
                if pin, edges.contains(.top) { fadeTop = true }
            }
            .mask {
                VStack(spacing: 0) {
                    if fadeTop { ScrollFade.top }
                    Color.black
                    if fadeBottom { ScrollFade.bottom }
                }
            }
    }
}

private struct EdgeFades: Equatable {
    var top: Bool
    var bottom: Bool
}

extension View {
    /// Default scroll-edge treatment: the same 40pt fade as the asset list.
    /// A bottom fade appears only while content runs past that edge.
    func scrollEdgeFade(edges: Edge.Set = .vertical, pinsTop: Bool = false) -> some View {
        modifier(ScrollEdgeFade(edges: edges, pinsTop: pinsTop))
    }
}
