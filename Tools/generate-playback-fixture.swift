import AVFoundation
import Foundation

@main struct Fixture {
    static func main() async throws {
        let composition = AVMutableComposition()
        let video = AVURLAsset(url: URL(fileURLWithPath: "/tmp/loge-fixture-video.mp4"))
        let sourceVideo = try await video.loadTracks(withMediaType: .video)[0]
        let sourceDuration = try await video.load(.duration)
        let duration = CMTime(seconds: 60, preferredTimescale: 600)
        let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        var cursor = CMTime.zero
        while cursor < duration {
            let span = CMTimeMinimum(sourceDuration, duration - cursor)
            try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: span), of: sourceVideo, at: cursor)
            cursor += span
        }
        targetVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        for (name, language) in [("en", "eng"), ("de", "deu")] {
            let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/loge-tone-\(name).wav"))
            let source = try await asset.loadTracks(withMediaType: .audio)[0]
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            track.languageCode = language
            track.extendedLanguageTag = name
        }
        let output = URL(fileURLWithPath: "/tmp/loge-multiaudio.mov")
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            fatalError("Cannot export fixture")
        }
        try await exporter.export(to: output, as: .mov)
        let result = AVURLAsset(url: output)
        let tracks = try await result.loadTracks(withMediaType: .audio)
        print("Exported \(output.path); duration=\(try await result.load(.duration).seconds), audio tracks=\(tracks.count)")
        for track in tracks {
            let language = try await track.load(.languageCode) ?? "none"
            print("audio \(track.trackID): language=\(language), tag=\(try await track.load(.extendedLanguageTag) ?? "none")")
        }
    }
}
