import SwiftUI
import UIKit

/// Window x of each finger still down. The recognizer's view is wider than the plot.
func chartTouchXs(_ recognizer: UIGestureRecognizer, event: UIEvent?) -> [CGFloat] {
    guard let view = recognizer.view else { return [] }
    let space = view.window ?? view
    return (event?.allTouches ?? [])
        .filter { $0.phase != .ended && $0.phase != .cancelled }
        .map { $0.location(in: space).x }
        .sorted()
}

/// One finger scrubs. A second finger adds the other end without moving the first.
struct ChartTouchGesture: UIGestureRecognizerRepresentable {
    var onChange: ([CGFloat]) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> ChartTouchRecognizer {
        let recognizer = ChartTouchRecognizer(target: nil, action: nil)
        recognizer.onChange = onChange
        recognizer.onEnd = onEnd
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: ChartTouchRecognizer, context: Context) {
        recognizer.onChange = onChange
        recognizer.onEnd = onEnd
    }

    func handleUIGestureRecognizerAction(_ recognizer: ChartTouchRecognizer, context: Context) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}

final class ChartTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onChange: (([CGFloat]) -> Void)?
    var onEnd: (() -> Void)?
    private weak var lockedScroll: UIScrollView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard (event.allTouches?.count ?? 0) >= 1 else { return }
        if state == .possible { state = .began }
        lockScroll()
        report(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .began || state == .changed else { return }
        state = .changed
        report(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        let staying = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        if staying == 0 {
            unlockScroll()
            if state == .possible { state = .failed } else { state = .ended }
        } else if state == .began || state == .changed {
            report(event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        unlockScroll()
        if state == .possible { state = .failed } else { state = .cancelled }
    }

    /// The list keeps the page still while a finger is choosing a year.
    private func lockScroll() {
        guard lockedScroll == nil else { return }
        var current = view
        while let candidate = current {
            if let scroll = candidate as? UIScrollView {
                scroll.isScrollEnabled = false
                let pan = scroll.panGestureRecognizer
                pan.isEnabled = false
                pan.isEnabled = true
                lockedScroll = scroll
                return
            }
            current = candidate.superview
        }
    }

    private func unlockScroll() {
        lockedScroll?.isScrollEnabled = true
        lockedScroll = nil
    }

    /// Each live touch keeps its own window x. A new finger does not move the one already down.
    func report(_ event: UIEvent?) {
        guard let onChange else { return }
        let xs = chartTouchXs(self, event: event)
        guard let first = xs.first else { return }
        onChange(xs.count == 1 ? [first] : [first, xs[xs.count - 1]])
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        !(other is UIPanGestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        other is UIPanGestureRecognizer
    }
}

/// Two fingers on the trend chart. Reports the left and right touch as they move.
struct ChartRangeGesture: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> TwoFingerRangeRecognizer {
        let recognizer = TwoFingerRangeRecognizer(target: nil, action: nil)
        recognizer.onChange = onChange
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: TwoFingerRangeRecognizer, context: Context) {
        recognizer.onChange = onChange
    }

    func handleUIGestureRecognizerAction(_ recognizer: TwoFingerRangeRecognizer, context: Context) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}

final class TwoFingerRangeRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onChange: ((CGFloat, CGFloat) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard (event.allTouches?.count ?? 0) >= 2 else { return }
        if state == .possible { state = .began }
        report(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .began || state == .changed else { return }
        state = .changed
        report(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        let staying = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        if state == .possible {
            state = .failed
        } else if staying < 2, state == .began || state == .changed {
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .possible {
            state = .failed
        } else if state == .began || state == .changed {
            state = .cancelled
        }
    }

    /// Read each finger from the event. `location(ofTouch:)` shifts the first finger when the second lands.
    func report(_ event: UIEvent?) {
        let xs = chartTouchXs(self, event: event)
        guard xs.count >= 2, let onChange else { return }
        onChange(xs[0], xs[xs.count - 1])
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// A chart scrub can leave a recognizer in `.changed` after the app is suspended.
/// The net-worth card's drag never begins until that recognizer is back at `.possible`.
enum GestureReset {
    private static var observer: NSObjectProtocol?

    static func arm() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in reset() }
    }

    private static func reset() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        windows.forEach(reset)
    }

    private static func reset(_ view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] where recognizer.state != .possible {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
        view.subviews.forEach(reset)
    }
}
