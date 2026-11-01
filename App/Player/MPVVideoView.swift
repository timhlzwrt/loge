import AVFoundation
import SwiftUI

/// Hosts an `MPVPlayer`'s video layer, sized to the view. The layer belongs to the
/// player, not the view, so it survives the player screen closing during Picture in Picture.
struct MPVVideoView {
    let player: MPVPlayer
}

#if os(macOS)
import AppKit

extension MPVVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView(videoLayer: player.layer) }
    func updateNSView(_ view: HostView, context: Context) {}

    final class HostView: NSView {
        private let videoLayer: CALayer

        init(videoLayer: CALayer) {
            self.videoLayer = videoLayer
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            // Live window resizing redraws every frame; animating would make the picture lag.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = bounds
            // mpv's subtitle layer, which doesn't follow its superlayer's size by itself.
            videoLayer.sublayers?.forEach { $0.frame = videoLayer.bounds }
            CATransaction.commit()
        }
    }
}
#else
import UIKit

extension MPVVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView { HostView(videoLayer: player.layer) }

    func updateUIView(_ view: HostView, context: Context) {
        #if os(tvOS)
        // Reading the format here makes SwiftUI call this again when it changes.
        view.match(player.videoFormat)
        #endif
    }

    #if os(tvOS)
    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        view.match(nil)
    }
    #endif

    final class HostView: UIView {
        private let videoLayer: CALayer

        init(videoLayer: CALayer) {
            self.videoLayer = videoLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // A sublayer doesn't follow UIKit's animations by itself; match the rotation's
            // duration so the picture turns with the screen instead of snapping first.
            let duration = UIView.inheritedAnimationDuration
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setDisableActions(duration == 0)
            videoLayer.frame = bounds
            // mpv's subtitle layer, which doesn't follow its superlayer's size by itself.
            videoLayer.sublayers?.forEach { $0.frame = videoLayer.bounds }
            CATransaction.commit()
        }

        #if os(tvOS)
        private var format: MPVPlayer.VideoFormat?

        /// Asks the TV to switch to the video's frame rate and dynamic range, if the user
        /// has Match Content turned on; nil hands the display back to the system.
        func match(_ format: MPVPlayer.VideoFormat?) {
            self.format = format
            window?.avDisplayManager.preferredDisplayCriteria = format.flatMap(Self.criteria)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            match(format)
        }

        private static func criteria(for format: MPVPlayer.VideoFormat) -> AVDisplayCriteria? {
            let transfer, primaries, matrix: CFString
            switch format.dynamicRange {
            case .sdr:
                (transfer, primaries, matrix) = (kCMFormatDescriptionTransferFunction_ITU_R_709_2,
                                                 kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
                                                 kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2)
            case .hdr10, .dolbyVision:
                (transfer, primaries, matrix) = (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
                                                 kCMFormatDescriptionColorPrimaries_ITU_R_2020,
                                                 kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
            case .hlg:
                (transfer, primaries, matrix) = (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG,
                                                 kCMFormatDescriptionColorPrimaries_ITU_R_2020,
                                                 kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
            }
            let extensions = [
                kCMFormatDescriptionExtension_TransferFunction: transfer,
                kCMFormatDescriptionExtension_ColorPrimaries: primaries,
                kCMFormatDescriptionExtension_YCbCrMatrix: matrix,
            ] as CFDictionary
            var description: CMFormatDescription?
            CMVideoFormatDescriptionCreate(
                allocator: nil,
                codecType: format.dynamicRange == .dolbyVision ? kCMVideoCodecType_DolbyVisionHEVC : kCMVideoCodecType_HEVC,
                width: Int32(format.width), height: Int32(format.height),
                extensions: extensions, formatDescriptionOut: &description)
            guard let description else { return nil }
            // Zero leaves the refresh rate alone when the file doesn't say.
            return AVDisplayCriteria(refreshRate: Float(format.frameRate ?? 0), formatDescription: description)
        }
        #endif
    }
}
#endif
