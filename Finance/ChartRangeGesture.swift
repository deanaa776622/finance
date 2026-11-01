import SwiftUI
import UIKit

/// Two fingers on the trend chart. Reports the left and right touch as they move.
struct ChartRangeGesture: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> TwoFingerRangeRecognizer {
        TwoFingerRangeRecognizer(target: nil, action: nil)
    }

    func handleUIGestureRecognizerAction(_ recognizer: TwoFingerRangeRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            guard recognizer.numberOfTouches >= 2, let view = recognizer.view else { return }
            let first = recognizer.location(ofTouch: 0, in: view)
            let second = recognizer.location(ofTouch: 1, in: view)
            onChange(min(first.x, second.x), max(first.x, second.x))
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}

final class TwoFingerRangeRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard (event.allTouches?.count ?? 0) >= 2 else { return }
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .began || state == .changed else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        let staying = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        if staying < 2, state == .began || state == .changed { state = .ended }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .began || state == .changed { state = .cancelled }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
