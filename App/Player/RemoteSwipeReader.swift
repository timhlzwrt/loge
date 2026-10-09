#if os(tvOS)
import SwiftUI
import UIKit

/// Reports horizontal swipes on the Siri Remote's touch surface. SwiftUI only
/// exposes discrete moves, so this adds a UIKit pan recognizer to the window,
/// where it sees swipes regardless of which view has focus.
struct RemoteSwipeReader: UIViewRepresentable {
    /// Horizontal travel as a fraction of a full swipe across the surface; negative is left.
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
    final class Coordinator: NSObject {
        let recognizer = UIPanGestureRecognizer()
        var onChanged: (Double) -> Void = { _ in }
        var onEnded: () -> Void = {}

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(handle))
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            // Presses and focus movement must keep working alongside the swipe.
            recognizer.cancelsTouchesInView = false
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                let width = recognizer.view?.bounds.width ?? 1920
                onChanged(recognizer.translation(in: recognizer.view).x / max(width, 1))
            case .ended, .cancelled, .failed:
                onEnded()
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
