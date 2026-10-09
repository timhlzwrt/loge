import Foundation
import Libmpv
import MediaCore
import Observation
import QuartzCore
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "mpv")

/// Owns one mpv instance and the Metal layer it renders into.
///
/// mpv runs its own threads; a dedicated thread waits on mpv's event queue and
/// forwards events here on the main actor. Shutting down sends `quit`, and that
/// thread destroys the handle once mpv confirms, so the handle is never freed
/// while something is still waiting on it.
@MainActor @Observable
final class MPVPlayer {
    enum Status: Equatable {
        case idle, loading, playing, paused, buffering, ended
        case failed(String)
    }

    var status: Status {
        switch loadState {
        case .idle: .idle
        case .loading: .loading
        case .failed(let message): .failed(message)
        case .loaded where isEnded: .ended
        case .loaded where isBuffering: .buffering
        case .loaded: isPaused ? .paused : .playing
        }
    }

    var isWaiting: Bool {
        status == .loading || status == .buffering
    }

    private(set) var position: Double = 0
    private(set) var duration: Double?
    private(set) var tracks: [Track] = []
    private(set) var speed = 1.0
    private(set) var isZoomedToFill = false

    struct Track: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable { case audio, sub }

        let id: Int
        let kind: Kind
        let title: String?
        let language: String?
        let codec: String?
        let channelCount: Int?
        let isForced: Bool
        let isHearingImpaired: Bool
        let isSelected: Bool

        /// "English · Commentary · Dolby Digital 5.1" or "English · Forced". Streams often
        /// carry several tracks per language, so the details that tell them apart are included.
        var displayName: String {
            let language = language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            var parts = [language, title].compactMap { $0 }.filter { !$0.isEmpty }
            switch kind {
            case .audio:
                let format = [codec.map(Self.codecName), channelCount.map(Self.channelLayout)].compactMap { $0 }
                if !format.isEmpty { parts.append(format.joined(separator: " ")) }
            case .sub:
                if isForced { parts.append("Forced") }
                if isHearingImpaired { parts.append("SDH") }
            }
            return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
        }

        private static func codecName(_ codec: String) -> String {
            switch codec {
            case "aac": "AAC"
            case "ac3": "Dolby Digital"
            case "eac3": "Dolby Digital Plus"
            case "truehd": "Dolby TrueHD"
            case "dts": "DTS"
            case "flac": "FLAC"
            case "opus": "Opus"
            case "mp3": "MP3"
            default: codec.uppercased()
            }
        }

        private static func channelLayout(_ count: Int) -> String {
            switch count {
            case 1: "Mono"
            case 2: "Stereo"
            case 6: "5.1"
            case 8: "7.1"
            default: "\(count) ch"
            }
        }
    }

    @ObservationIgnored let layer = MPVMetalLayer()

    private enum LoadState { case idle, loading, loaded, failed(String) }
    private var loadState = LoadState.idle
    private var isPaused = false
    private var isBuffering = false
    private var isEnded = false

    @ObservationIgnored private let handle: OpaquePointer
    @ObservationIgnored private var isShutDown = false

    init() {
        // mpv_create only fails when allocation fails.
        guard let handle = mpv_create() else { fatalError("mpv_create failed") }
        self.handle = handle

        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid), "wid")
        for (name, value) in [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            // Stay on the last frame at the end instead of unloading the file.
            ("keep-open", "yes"),
            // Keep text subtitles inside the picture; mpv otherwise places them in the
            // letterbox bars, which on a phone in portrait is where the controls are.
            ("sub-use-margins", "no"),
            // Size them to the picture rather than the window, which in portrait is far taller.
            ("sub-scale-by-window", "no"),
        ] {
            check(mpv_set_option_string(handle, name, value), name)
        }
        mpv_request_log_messages(handle, "warn")

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            loadState = .failed(String(cString: mpv_error_string(status)))
            mpv_terminate_destroy(handle)
            isShutDown = true
            return
        }

        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        // Observed only as a change signal; the list itself is read through its sub-properties.
        mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NONE)

        startEventThread()
    }

    isolated deinit {
        shutDown()
    }

    /// - Parameters:
    ///   - headers: Sent with every request for this file, e.g. debrid authorisation.
    ///   - startAt: Seconds into the file to start from, for resuming.
    ///   - audioLanguage: ISO 639-1 code to prefer; nil keeps the file's default track.
    ///   - subtitleLanguage: ISO 639-1 code to show; nil turns subtitles off.
    func load(
        _ url: URL,
        headers: [String: String] = [:],
        startAt: Double? = nil,
        audioLanguage: String? = nil,
        subtitleLanguage: String? = nil
    ) {
        guard !isShutDown else { return }
        loadState = .loading
        position = 0
        duration = nil
        tracks = []
        // mpv sends User-Agent from its own option, so a header field would be ignored.
        var fields = headers
        if let key = fields.keys.first(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }),
           let userAgent = fields.removeValue(forKey: key) {
            setProperty("user-agent", userAgent)
        }
        // Built item by item: the single-string form splits on commas, which header values may contain.
        command(["change-list", "http-header-fields", "clr", ""])
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            command(["change-list", "http-header-fields", "append", "\(name): \(value)"])
        }
        // These are global options, so each is set explicitly rather than left over from the last file.
        setProperty("start", startAt.map { String(Int($0)) } ?? "none")
        setProperty("alang", audioLanguage.map(LanguageCodes.trackTags) ?? "")
        if let subtitleLanguage {
            setProperty("slang", LanguageCodes.trackTags(for: subtitleLanguage))
            setProperty("sid", "auto")
        } else {
            // Otherwise mpv shows any track the file marks as default.
            setProperty("sid", "no")
        }
        // mpv pauses at the end of a file and keeps that for the next one, which
        // would leave the next episode waiting on its first frame.
        setProperty("pause", "no")
        command(["loadfile", url.absoluteString, "replace"])
    }

    func togglePause() {
        command(["cycle", "pause"])
    }

    func play() {
        setProperty("pause", "no")
    }

    func pause() {
        setProperty("pause", "yes")
    }

    func seek(by seconds: Double) {
        command(["seek", String(seconds), "relative"])
    }

    func seek(to seconds: Double) {
        command(["seek", String(seconds), "absolute"])
    }

    /// 1 is normal speed.
    func setSpeed(_ speed: Double) {
        self.speed = speed
        setProperty("speed", String(speed))
    }

    /// Multiplies the subtitle font size; 1 is mpv's default.
    func setSubtitleScale(_ scale: Double) {
        setProperty("sub-scale", String(scale))
    }

    /// Crops the picture to fill the screen instead of letterboxing it.
    func setZoomToFill(_ fill: Bool) {
        isZoomedToFill = fill
        setProperty("panscan", fill ? "1.0" : "0.0")
    }

    /// Pass nil to turn subtitles off.
    func select(_ track: Track?, kind: Track.Kind) {
        setProperty(kind == .audio ? "aid" : "sid", track.map { String($0.id) } ?? "no")
    }

    /// Detaches video while the app is in the background; rendering into a
    /// hidden layer leaves it black when the app returns.
    func setVideoEnabled(_ isEnabled: Bool) {
        setProperty("vid", isEnabled ? "auto" : "no")
    }

    /// Stops playback immediately; the player can't be reused afterwards.
    func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        command(["quit"], ignoringShutdown: true)
    }

    // MARK: - Events

    private enum Event: Sendable {
        case fileLoaded
        case failed(String)
        case flag(String, Bool)
        case double(String, Double?)
        case tracks([Track])
    }

    private func startEventThread() {
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)

        // The handle is safe to share: libmpv's client API is thread-safe. The
        // layer is captured so it outlives mpv's render thread, which draws into it
        // until mpv_terminate_destroy returns.
        nonisolated(unsafe) let handle = handle
        nonisolated(unsafe) let layer = layer
        Thread.detachNewThread {
            while let event = mpv_wait_event(handle, -1)?.pointee, event.event_id != MPV_EVENT_SHUTDOWN {
                if let parsed = Self.parse(event, handle: handle) {
                    continuation.yield(parsed)
                }
            }
            continuation.finish()
            mpv_terminate_destroy(handle)
            withExtendedLifetime(layer) {}
        }

        Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
    }

    private nonisolated static func parse(_ event: mpv_event, handle: OpaquePointer) -> Event? {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let end = event.data?.load(as: mpv_event_end_file.self),
                  end.reason == MPV_END_FILE_REASON_ERROR
            else { return nil }
            return .failed(String(cString: mpv_error_string(end.error)))
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let property = event.data?.load(as: mpv_event_property.self) else { return nil }
            let name = String(cString: property.name)
            if name == "track-list" {
                return .tracks(readTracks(handle))
            }
            switch property.format {
            case MPV_FORMAT_FLAG:
                return .flag(name, property.data.load(as: Int32.self) != 0)
            case MPV_FORMAT_DOUBLE:
                return .double(name, property.data.load(as: Double.self))
            default:
                // MPV_FORMAT_NONE: the property is currently unavailable, e.g. no file loaded.
                return .double(name, nil)
            }
        case MPV_EVENT_LOG_MESSAGE:
            if let message = event.data?.load(as: mpv_event_log_message.self) {
                log.warning("[\(String(cString: message.prefix))] \(String(cString: message.text))")
            }
            return nil
        default:
            return nil
        }
    }

    private nonisolated static func readTracks(_ handle: OpaquePointer) -> [Track] {
        func string(_ name: String) -> String? {
            guard let value = mpv_get_property_string(handle, name) else { return nil }
            defer { mpv_free(value) }
            return String(cString: value)
        }
        let count = string("track-list/count").flatMap(Int.init) ?? 0
        return (0..<count).compactMap { index in
            let prefix = "track-list/\(index)/"
            guard let kind = string(prefix + "type").flatMap(Track.Kind.init(rawValue:)),
                  let id = string(prefix + "id").flatMap(Int.init)
            else { return nil } // Video tracks aren't selectable here.
            return Track(
                id: id,
                kind: kind,
                title: string(prefix + "title"),
                language: string(prefix + "lang"),
                codec: string(prefix + "codec"),
                channelCount: string(prefix + "demux-channel-count").flatMap(Int.init),
                isForced: string(prefix + "forced") == "yes",
                isHearingImpaired: string(prefix + "hearing-impaired") == "yes",
                isSelected: string(prefix + "selected") == "yes"
            )
        }
    }

    private func apply(_ event: Event) {
        switch event {
        case .fileLoaded:
            loadState = .loaded
        case .failed(let message):
            loadState = .failed(message)
        case .flag("pause", let value):
            isPaused = value
        case .flag("paused-for-cache", let value):
            isBuffering = value
        case .flag("eof-reached", let value):
            isEnded = value
        case .double("time-pos", let value):
            // mpv reports every frame; whole seconds are enough for the UI and
            // avoid redrawing the controls 24+ times a second.
            let seconds = (value ?? 0).rounded(.down)
            if seconds != position {
                position = seconds
            }
        case .double("duration", let value):
            duration = value
        case .tracks(let value):
            tracks = value
        case .flag, .double:
            break
        }
    }

    // MARK: - Commands

    private func command(_ args: [String], ignoringShutdown: Bool = false) {
        guard !isShutDown || ignoringShutdown else { return }
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        let status = cArgs.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                mpv_command(handle, $0)
            }
        }
        check(status, args[0])
    }

    private func setProperty(_ name: String, _ value: String) {
        guard !isShutDown else { return }
        check(mpv_set_property_string(handle, name, value), name)
    }

    private func check(_ status: Int32, _ context: String) {
        if status < 0 {
            log.error("\(context): \(String(cString: mpv_error_string(status)))")
        }
    }
}

/// MoltenVK briefly sets the drawable to 1×1 to force a presentation, which
/// causes flicker and can leave it stuck at that size.
/// https://github.com/mpv-player/mpv/pull/13651
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if newValue.width > 1 && newValue.height > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
