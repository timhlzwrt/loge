import AVFoundation
import Foundation

@main struct Export4K {
    static func main() async throws {
        let input = AVURLAsset(url: URL(fileURLWithPath: "/tmp/loge-multiaudio.mov"))
        let video = try await input.loadTracks(withMediaType: .video)[0]
        let size = try await video.load(.naturalSize)
        let preferred = try await video.load(.preferredTransform)
        let duration = CMTime(seconds: 20, preferredTimescale: 600)
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: video)
        let oriented = CGRect(origin: .zero, size: size).applying(preferred)
        let scale = max(3840 / oriented.width, 2160 / oriented.height)
        let transform = preferred
            .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        layer.setTransform(transform, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration)))
        let composition = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(value: 1, timescale: 30), instructions: [instruction],
            renderSize: CGSize(width: 3840, height: 2160)))
        guard let exporter = AVAssetExportSession(asset: input, presetName: AVAssetExportPresetHEVC3840x2160) else {
            fatalError("HEVC 4K export is unavailable")
        }
        exporter.videoComposition = composition
        exporter.timeRange = CMTimeRange(start: .zero, duration: duration)
        let output = URL(fileURLWithPath: "/tmp/loge-4k.mov")
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try await exporter.export(to: output, as: .mov)
        let result = AVURLAsset(url: output)
        let resultVideo = try await result.loadTracks(withMediaType: .video)
        let resultAudio = try await result.loadTracks(withMediaType: .audio)
        print("path=\(output.path) duration=\(try await result.load(.duration).seconds) audioTracks=\(resultAudio.count)")
        for track in resultVideo {
            let dimensions = try await track.load(.naturalSize)
            let formats = try await track.load(.formatDescriptions)
            print("video=\(dimensions.width)x\(dimensions.height) fps=\(try await track.load(.nominalFrameRate))")
            for format in formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
print("encodedDimensions=\(dimensions) codecFourCC=\(CMFormatDescriptionGetMediaSubType(format))")
            }
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        print("bytes=\(attributes[.size]!)")
    }
}
