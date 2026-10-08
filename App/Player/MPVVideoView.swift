import QuartzCore
import SwiftUI

/// Hosts an `MPVPlayer`'s Metal layer and keeps its drawable sized to the view.
struct MPVVideoView {
    let player: MPVPlayer
}

private func resizeVideoLayer(_ layer: CAMetalLayer, to bounds: CGRect, scale: CGFloat) {
    // The layer is resized during SwiftUI layout; implicit animations would make it lag behind.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.frame = bounds
    layer.contentsScale = scale
    layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    CATransaction.commit()
}

#if os(macOS)
import AppKit

extension MPVVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView(videoLayer: player.layer) }
    func updateNSView(_ view: HostView, context: Context) {}

    final class HostView: NSView {
        private let videoLayer: CAMetalLayer

        init(videoLayer: CAMetalLayer) {
            self.videoLayer = videoLayer
            super.init(frame: .zero)
            videoLayer.backgroundColor = NSColor.black.cgColor
            // Assigning the layer before `wantsLayer` makes this a layer-hosting view.
            layer = videoLayer
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            resizeVideoLayer(videoLayer, to: bounds, scale: window?.backingScaleFactor ?? 2)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            needsLayout = true
        }
    }
}
#else
import UIKit

extension MPVVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView { HostView(videoLayer: player.layer) }
    func updateUIView(_ view: HostView, context: Context) {}

    final class HostView: UIView {
        private let videoLayer: CAMetalLayer

        init(videoLayer: CAMetalLayer) {
            self.videoLayer = videoLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            resizeVideoLayer(videoLayer, to: bounds, scale: traitCollection.displayScale)
        }
    }
}
#endif
