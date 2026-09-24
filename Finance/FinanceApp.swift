import SwiftUI

@main
struct FinanceApp: App {
    @State private var portfolio = Portfolio.load()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .background(ScrollFitLock())
                .environment(portfolio)
                .preferredColorScheme(.dark)
        }
    }
}

/// Turns vertical scrolling off while the content fits. Form and List still allow a drag by default.
struct ScrollFitLock: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.scan()
    }

    final class Probe: UIView {
        private var watches: [ObjectIdentifier: Watch] = [:]
        private var forcedOff: Set<ObjectIdentifier> = []
        private var applying = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scan()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scan()
        }

        func scan() {
            guard let window else { return }
            var seen: Set<ObjectIdentifier> = []
            collect(window, seen: &seen)
            watches = watches.filter { seen.contains($0.key) }
        }

        private func collect(_ view: UIView, seen: inout Set<ObjectIdentifier>) {
            if let scroll = view as? UIScrollView {
                let id = ObjectIdentifier(scroll)
                seen.insert(id)
                if watches[id] == nil {
                    watches[id] = Watch(scroll) { [weak self] in self?.apply($0) }
                }
                apply(scroll)
            }
            for subview in view.subviews {
                collect(subview, seen: &seen)
            }
        }

        private func apply(_ scroll: UIScrollView) {
            guard !applying, scroll.bounds.height > 1, scroll.contentSize.height > 0 else { return }
            let content = scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom
            let horizontalOnly = scroll.contentSize.width > scroll.bounds.width + 1 && content <= scroll.bounds.height + 1
            guard !horizontalOnly else { return }
            applying = true
            defer { applying = false }
            // A few points past the safe area is not enough to need a scroll.
            let fits = content <= scroll.bounds.height + 16
            let id = ObjectIdentifier(scroll)
            if fits {
                scroll.bounces = false
                if scroll.isScrollEnabled {
                    scroll.isScrollEnabled = false
                    forcedOff.insert(id)
                }
            } else {
                scroll.bounces = true
                if forcedOff.remove(id) != nil {
                    scroll.isScrollEnabled = true
                }
            }
        }
    }

    private final class Watch {
        init(_ scroll: UIScrollView, apply: @escaping (UIScrollView) -> Void) {
            size = scroll.observe(\.contentSize) { scroll, _ in apply(scroll) }
            bounds = scroll.observe(\.bounds) { scroll, _ in apply(scroll) }
        }

        private var size: NSKeyValueObservation
        private var bounds: NSKeyValueObservation
    }
}
