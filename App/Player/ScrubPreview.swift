import CoreGraphics
import Foundation
import Libmpv
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "scrub-preview")

/// Frames for the timeline while scrubbing. AVFoundation can't open most of what mpv plays
/// (MKV in particular), so a second mpv instance opens the same file paused, silent and
/// without a picture of its own, jumps to the keyframe at each scrub position and hands
/// back that frame at thumbnail size.
///
/// One frame is fetched at a time and only the latest position is kept, so a fast drag
/// costs no more than the decoder can keep up with.
@MainActor @Observable
final class ScrubPreview {
    /// The keyframe nearest the last position fetched; nil until the first one arrives,
    /// and for files this can't decode.
    private(set) var image: CGImage?

    let url: URL

    @ObservationIgnored private let handle: OpaquePointer
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var wanted: Double?
    @ObservationIgnored private var fetched: Double?

    init(url: URL, headers: [String: String]) {
        self.url = url
        guard let handle = mpv_create() else { fatalError("mpv_create failed") }
        self.handle = handle
        for (name, value) in [
            ("vo", "null"),
            ("ao", "null"),
            ("aid", "no"),
            ("sid", "no"),
            ("pause", "yes"),
            ("keep-open", "yes"),
            // Copied back from VideoToolbox, so the scale filter can shrink it before the
            // frame is converted for Core Graphics.
            ("hwdec", "videotoolbox-copy"),
            ("vf", "scale=w=480:h=-2"),
            // Only a keyframe is needed each time, not a buffer to play from.
            ("cache", "no"),
            ("demuxer-max-bytes", "8MiB"),
            ("demuxer-max-back-bytes", "0"),
            ("hls-bitrate", "min"),
            ("ytdl", "no"),
        ] {
            check(mpv_set_option_string(handle, name, value), name)
        }
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            isShutDown = true
            return
        }
        // Same as the player's: User-Agent has its own option, and the fields are added one
        // by one because the single-string form splits on commas inside header values.
        var fields = headers
        if let key = fields.keys.first(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }),
           let value = fields.removeValue(forKey: key) {
            check(mpv_set_property_string(handle, "user-agent", value), "user-agent")
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            command(["change-list", "http-header-fields", "append", "\(name): \(value)"])
        }
        startEventThread()
    }

    isolated deinit {
        shutDown()
    }

    /// Fetches the frame for `seconds` once the one in progress is done.
    func show(_ seconds: Double) {
        wanted = seconds
        fetchIfNeeded()
    }

    /// Forgets the last frame, so the next scrub doesn't open on a picture from elsewhere.
    func clear() {
        wanted = nil
        fetched = nil
        image = nil
    }

    func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        command(["quit"], ignoringShutdown: true, asynchronously: true)
    }

    private func fetchIfNeeded() {
        guard !isShutDown, !isFetching, let wanted else { return }
        // Nearby positions almost always share a keyframe, so they'd decode the same picture.
        if let fetched, abs(wanted - fetched) < 2 { return }
        isFetching = true
        fetched = wanted
        if isLoaded {
            command(["seek", String(wanted), "absolute+keyframes"], asynchronously: true)
        } else {
            isLoaded = true
            check(mpv_set_property_string(handle, "start", String(wanted)), "start")
            command(["loadfile", url.absoluteString], asynchronously: true)
        }
    }

    // MARK: - Events

    private enum Event: Sendable {
        /// nil when the frame couldn't be read.
        case frame(CGImage?)
        case failed
    }

    private func startEventThread() {
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)
        nonisolated(unsafe) let handle = handle
        Thread.detachNewThread {
            while let event = mpv_wait_event(handle, -1)?.pointee, event.event_id != MPV_EVENT_SHUTDOWN {
                switch event.event_id {
                case MPV_EVENT_COMMAND_REPLY where event.error < 0:
                    continuation.yield(.failed)
                case MPV_EVENT_PLAYBACK_RESTART:
                    // A seek has finished and its frame is on the (null) output, even while paused.
                    continuation.yield(.frame(Self.readFrame(handle)))
                case MPV_EVENT_END_FILE:
                    if let end = event.data?.load(as: mpv_event_end_file.self), end.reason == MPV_END_FILE_REASON_ERROR {
                        continuation.yield(.failed)
                    }
                default:
                    break
                }
            }
            continuation.finish()
            mpv_terminate_destroy(handle)
        }
        Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
    }

    private func apply(_ event: Event) {
        guard !isShutDown else { return }
        switch event {
        case .frame(let frame):
            if let frame, wanted != nil { image = frame }
            isFetching = false
            fetchIfNeeded()
        case .failed:
            // The timeline shows the time alone.
            log.error("Couldn't open the file for previews")
            shutDown()
        }
    }

    /// Runs on the event thread, which may wait for mpv here without holding up the UI.
    private nonisolated static func readFrame(_ handle: OpaquePointer) -> CGImage? {
        var result = mpv_node()
        var args: [UnsafePointer<CChar>?] = [
            UnsafePointer(strdup("screenshot-raw")), UnsafePointer(strdup("video")), nil,
        ]
        defer { args.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        guard mpv_command_ret(handle, &args, &result) >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }

        guard result.format == MPV_FORMAT_NODE_MAP, let map = result.u.list?.pointee,
              let keys = map.keys, let values = map.values else { return nil }
        var width = 0, height = 0, stride = 0
        var pixels: Data?
        for index in 0..<Int(map.num) {
            guard let key = keys[index] else { continue }
            let value = values[index]
            switch String(cString: key) {
            case "w": width = Int(value.u.int64)
            case "h": height = Int(value.u.int64)
            case "stride": stride = Int(value.u.int64)
            case "data":
                if value.format == MPV_FORMAT_BYTE_ARRAY, let bytes = value.u.ba?.pointee, let data = bytes.data {
                    pixels = Data(bytes: data, count: bytes.size)
                }
            default: break
            }
        }
        // screenshot-raw's default format is bgr0: blue first in memory, the fourth byte unused.
        guard width > 0, height > 0, let pixels, pixels.count >= stride * height,
              let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Commands

    private func command(_ args: [String], ignoringShutdown: Bool = false, asynchronously: Bool = false) {
        guard !isShutDown || ignoringShutdown else { return }
        let status = withMPVArguments(args) { asynchronously ? mpv_command_async(handle, 0, $0) : mpv_command(handle, $0) }
        check(status, args[0])
        if status < 0 && asynchronously { apply(.failed) }
    }

    private func check(_ status: Int32, _ context: String) {
        if status < 0 {
            log.error("\(context): \(String(cString: mpv_error_string(status)))")
        }
    }
}
