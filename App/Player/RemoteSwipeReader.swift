#if os(tvOS)
import SwiftUI
import UIKit

/// Reports horizontal swipes on the Siri Remote's touch surface. SwiftUI only
/// exposes discrete moves, so this adds a UIKit pan recognizer to the window,
/// where it sees swipes regardless of which view has focus. A swipe counts only once it
/// has clearly gone sideways: a resting thumb or a swipe down drifts a little, and that
/// drift used to start a scrub.
struct RemoteSwipeReader: UIViewRepresentable {
    /// Horizontal travel since the swipe counted, as a fraction of a full swipe across the
    /// surface; negative is left.
    var onChanged: (Double) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        HostView(recognizer: context.coordinator.recognizer)
    }

    func updateUIView(_ view: HostView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let recognizer = UIPanGestureRecognizer()
        var onChanged: (Double) -> Void = { _ in }
        var onEnded: () -> Void = {}
        /// Where the swipe counted as horizontal, or nil until it has gone far enough to tell.
        private var origin: CGFloat?
        private var isVertical = false

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(handle))
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            // Presses and focus movement must keep working alongside the swipe.
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
        }

        /// The focus engine reads the same swipes with recognizers of its own, and by default
        /// one recognizer that wins a touch keeps the others from seeing it.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let width = max(recognizer.view?.bounds.width ?? 1920, 1)
            let travel = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .changed:
                guard !isVertical else { return }
                if let origin {
                    onChanged((travel.x - origin) / width)
                } else if hypot(travel.x, travel.y) > width * 0.08 {
                    if abs(travel.x) > abs(travel.y) * 2 {
                        origin = travel.x
                    } else {
                        isVertical = true
                    }
                }
            case .ended, .cancelled, .failed:
                if origin != nil { onEnded() }
                origin = nil
                isVertical = false
            default:
                break
            }
        }
    }

    final class HostView: UIView {
        private let recognizer: UIPanGestureRecognizer

        init(recognizer: UIPanGestureRecognizer) {
            self.recognizer = recognizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }
}
#endif
