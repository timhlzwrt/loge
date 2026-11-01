import AVFoundation
import Libmpv
import MediaCore
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "mpv")

/// Owns one mpv instance and the system video layer it shows frames in.
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

    /// Buffering stops the clock temporarily without changing the user's play/pause choice.
    var isPlaybackPaused: Bool {
        switch loadState {
        case .loaded: isPaused || isEnded
        default: true
        }
    }

    private(set) var position: Double = 0
    private(set) var duration: Double?
    private(set) var tracks: [Track] = []
    private(set) var speed = 1.0
    private(set) var isZoomedToFill = false
    /// The playing video's frame rate and dynamic range, for Apple TV to switch the display to.
    private(set) var videoFormat: VideoFormat?
    /// Seconds the subtitles or the sound are shifted; positive shows or plays them later.
    private(set) var subtitleDelay = 0.0
    private(set) var audioDelay = 0.0
    private(set) var trackError: String?
    private(set) var playbackInfo = PlaybackInfo()

    struct PlaybackInfo {
        var hardwareDecoder: String?
        var decoderDrops: Int64?
        var outputDrops: Int64?
        var bufferedSeconds: Double?
        var videoBitrate: Double?
        var audioBitrate: Double?
    }

    struct VideoFormat: Equatable, Sendable {
        enum DynamicRange: Sendable { case sdr, hdr10, hlg, dolbyVision }

        let width: Int
        let height: Int
        let frameRate: Double?
        let dynamicRange: DynamicRange
    }

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

    /// mpv's avfoundation output hands it each frame as it's due, already decoded by
    /// VideoToolbox and with subtitles drawn in, which is what Picture in Picture shows.
    @ObservationIgnored let layer = AVSampleBufferDisplayLayer()
    /// The exact `time-pos`; `position` is rounded for the UI.
    @ObservationIgnored private var exactPosition: Double = 0

    private enum LoadState { case idle, loading, loaded, failed(String) }
    private var loadState = LoadState.idle
    private var isPaused = false
    private var isBuffering = false
    private var isEnded = false

    @ObservationIgnored private let handle: OpaquePointer
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored private var defaultUserAgent = ""
    private struct TrackOperation {
        var arguments: [String]
        let kind: Track.Kind?
    }
    @ObservationIgnored private var trackOperations: [TrackOperation] = []
    @ObservationIgnored private var activeTrackOperation: (id: UInt64, operation: TrackOperation, preempted: Bool)?
    @ObservationIgnored private var nextCommandID: UInt64 = 0
    @ObservationIgnored private var pendingLoad: (() -> Void)?
    @ObservationIgnored private var hasSelectedSubtitles = false
    private struct SeekOperation {
        let seconds: Double
        let completion: () -> Void
    }
    @ObservationIgnored private var pendingSeeks: [SeekOperation] = []
    @ObservationIgnored private var activeSeek: (id: UInt64, operation: SeekOperation, started: Bool)?
    @ObservationIgnored private var seekTimeout: Task<Void, Never>?

    init() {
        // mpv_create only fails when allocation fails.
        guard let handle = mpv_create() else { fatalError("mpv_create failed") }
        self.handle = handle

        layer.videoGravity = .resizeAspect
        // Frames are shown as soon as they arrive, so the layer's clock doesn't time them.
        // It runs only while playing, which Picture in Picture reads as progress.
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        layer.controlTimebase = timebase

        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid), "wid")
        for (name, value) in [
            ("vo", "avfoundation"),
            // Draw subtitles into the frames, so they're also in Picture in Picture.
            ("avfoundation-composite-osd", "yes"),
            ("hwdec", "videotoolbox"),
            // Stay on the last frame at the end instead of unloading the file.
            ("keep-open", "yes"),
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

        if let value = mpv_get_property_string(handle, "user-agent") {
            defaultUserAgent = String(cString: value)
            mpv_free(value)
        }

        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NODE)
        // Video format is read through its sub-properties when it changes.
        mpv_observe_property(handle, 0, "video-params", MPV_FORMAT_NONE)

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
        trackOperations = []
        trackError = nil
        playbackInfo = PlaybackInfo()
        loadState = .loading
        cancelSeeks()
        position = 0
        duration = nil
        tracks = []
        if let activeTrackOperation {
            // Finish or abort the old file's subtitle load before issuing the next loadfile.
            pendingLoad = { [weak self] in
                self?.load(url, headers: headers, startAt: startAt,
                           audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage)
            }
            mpv_abort_async_command(handle, activeTrackOperation.id)
            return
        }
        pendingLoad = nil
        hasSelectedSubtitles = false
        // mpv sends User-Agent from its own option, so a header field would be ignored.
        var fields = headers
        var userAgent = defaultUserAgent
        if let key = fields.keys.first(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }),
           let value = fields.removeValue(forKey: key) {
            userAgent = value
        }
        setProperty("user-agent", userAgent)
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
        // A shift fixes one file's timing, so it shouldn't carry over to the next.
        setDelay(0, for: .sub)
        setDelay(0, for: .audio)
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
        // Queue user gestures without waiting for mpv's playback thread on the UI actor.
        command(["seek", String(seconds), "relative"], replyID: 0)
    }

    /// AVKit must wait for decoded playback to restart, rather than merely submitting the seek.
    func seek(by seconds: Double, completion: @escaping () -> Void) {
        guard !isShutDown, case .loaded = loadState, seconds.isFinite, seconds != 0 else { completion(); return }
        pendingSeeks.append(SeekOperation(seconds: seconds, completion: completion))
        runNextSeek()
    }

    func seek(to seconds: Double) {
        command(["seek", String(seconds), "absolute"], replyID: 0)
    }

    /// For the end of a scrub: lands on the keyframe next to `seconds` instead of decoding on
    /// to the exact frame, which on long-GOP network files means fetching and decoding up to
    /// several seconds of video first. Seeking relative to here makes mpv take the keyframe in
    /// the direction of travel, so a short scrub forward still moves forward.
    func seek(toKeyframeNear seconds: Double) {
        command(["seek", String(seconds - exactPosition), "relative+keyframes"], replyID: 0)
    }

    /// 1 is normal speed.
    func setSpeed(_ speed: Double) {
        self.speed = speed
        setProperty("speed", String(speed))
        updateClock()
    }

    /// Multiplies the subtitle font size; 1 is mpv's default.
    func setSubtitleScale(_ scale: Double) {
        setProperty("sub-scale", String(scale))
    }

    /// Crops the picture to fill the screen instead of letterboxing it.
    func setZoomToFill(_ fill: Bool) {
        isZoomedToFill = fill
        layer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    func setDelay(_ seconds: Double, for kind: Track.Kind) {
        switch kind {
        case .sub:
            subtitleDelay = seconds
            setProperty("sub-delay", String(seconds))
        case .audio:
            audioDelay = seconds
            setProperty("audio-delay", String(seconds))
        }
    }

    /// Adds a subtitle file as a track; `select` also switches to it.
    func addSubtitle(url: String, title: String, language: String, select: Bool) {
        enqueueTrackOperation(TrackOperation(
            arguments: ["sub-add", url, select && !hasSelectedSubtitles ? "select" : "auto", title, language], kind: nil))
    }

    /// Pass nil to turn subtitles off.
    func select(_ track: Track?, kind: Track.Kind) {
        trackError = nil
        if kind == .sub {
            hasSelectedSubtitles = true
            // A subtitle still downloading must not override the user's explicit choice.
            for index in trackOperations.indices where trackOperations[index].arguments.first == "sub-add" {
                trackOperations[index].arguments[2] = "auto"
            }
        }
        let operation = TrackOperation(
            arguments: ["set", kind == .audio ? "aid" : "sid", track.map { String($0.id) } ?? "no"], kind: kind)
        trackOperations.removeAll { $0.kind == kind }
        if activeTrackOperation?.operation.arguments == operation.arguments { return }
        enqueueTrackOperation(operation)
    }

    func dismissTrackError() { trackError = nil }

    /// Requested only while Playback Info is open, without blocking the UI on mpv.
    func refreshPlaybackInfo() {
        guard !isShutDown else { return }
        for (name, format) in [
            ("hwdec-current", MPV_FORMAT_STRING),
            ("decoder-frame-drop-count", MPV_FORMAT_INT64),
            ("frame-drop-count", MPV_FORMAT_INT64),
            ("demuxer-cache-duration", MPV_FORMAT_DOUBLE),
            ("video-bitrate", MPV_FORMAT_DOUBLE),
            ("audio-bitrate", MPV_FORMAT_DOUBLE),
        ] {
            check(mpv_get_property_async(handle, 0, name, format), name)
        }
    }

    /// Detaches video while the app is in the background without Picture in Picture;
    /// the system stops a hidden video layer, and reattaching starts it afresh.
    func setVideoEnabled(_ isEnabled: Bool) {
        setProperty("vid", isEnabled ? "auto" : "no")
    }

    /// Stops playback immediately; the player can't be reused afterwards.
    func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        cancelSeeks()
        trackOperations = []
        pendingLoad = nil
        activeTrackOperation = nil
        command(["quit"], ignoringShutdown: true, replyID: 0)
    }

    // MARK: - Events

    private enum Event: Sendable {
        case commandReply(UInt64, Int32)
        case seekStarted
        case playbackRestart(Double?)
        case fileLoaded
        case failed(String)
        case flag(String, Bool)
        case double(String, Double?)
        case integer(String, Int64)
        case string(String, String)
        case tracks([Track])
        case videoFormat(VideoFormat?)
    }

    private func startEventThread() {
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)

        // The handle is safe to share: libmpv's client API is thread-safe. The
        // layer is captured so it outlives mpv's video output, which enqueues frames
        // into it until mpv_terminate_destroy returns.
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
        case MPV_EVENT_COMMAND_REPLY:
            return .commandReply(event.reply_userdata, event.error)
        case MPV_EVENT_SEEK:
            return .seekStarted
        case MPV_EVENT_PLAYBACK_RESTART:
            var position = 0.0
            let result = mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
            return .playbackRestart(result >= 0 ? position : nil)
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let end = event.data?.load(as: mpv_event_end_file.self),
                  end.reason == MPV_END_FILE_REASON_ERROR
            else { return nil }
            return .failed(String(cString: mpv_error_string(end.error)))
        case MPV_EVENT_PROPERTY_CHANGE, MPV_EVENT_GET_PROPERTY_REPLY:
            guard let property = event.data?.load(as: mpv_event_property.self) else { return nil }
            let name = String(cString: property.name)
            if event.event_id == MPV_EVENT_GET_PROPERTY_REPLY, event.error < 0 {
                return name == "video-bitrate" || name == "audio-bitrate" ? .double(name, nil) : nil
            }
            if name == "track-list" {
                guard property.format == MPV_FORMAT_NODE, let data = property.data else { return .tracks([]) }
                return .tracks(readTracks(data.load(as: mpv_node.self)))
            }
            if name == "video-params" {
                return .videoFormat(readVideoFormat(handle))
            }
            switch property.format {
            case MPV_FORMAT_STRING:
                return .string(name, String(cString: property.data.load(as: UnsafePointer<CChar>.self)))
            case MPV_FORMAT_INT64:
                return .integer(name, property.data.load(as: Int64.self))
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

    private nonisolated static func readVideoFormat(_ handle: OpaquePointer) -> VideoFormat? {
        func string(_ name: String) -> String? {
            guard let value = mpv_get_property_string(handle, name) else { return nil }
            defer { mpv_free(value) }
            return String(cString: value)
        }
        guard let width = string("video-params/w").flatMap(Int.init),
              let height = string("video-params/h").flatMap(Int.init)
        else { return nil }
        let dynamicRange: VideoFormat.DynamicRange = switch string("video-params/gamma") {
        case "pq": string("current-tracks/video/dolby-vision-profile") != nil ? .dolbyVision : .hdr10
        case "hlg": .hlg
        default: .sdr
        }
        return VideoFormat(width: width, height: height,
                           frameRate: string("container-fps").flatMap(Double.init),
                           dynamicRange: dynamicRange)
    }

    private nonisolated static func readTracks(_ node: mpv_node) -> [Track] {
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list?.pointee,
              list.num > 0, let values = list.values else { return [] }
        return (0..<Int(list.num)).compactMap { index in
            let entry = values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let fields = entry.u.list?.pointee,
                  fields.num > 0, let keys = fields.keys, let values = fields.values else { return nil }
            var properties: [String: mpv_node] = [:]
            for index in 0..<Int(fields.num) {
                if let key = keys[index] { properties[String(cString: key)] = values[index] }
            }
            func string(_ name: String) -> String? {
                guard let value = properties[name] else { return nil }
                switch value.format {
                case MPV_FORMAT_STRING: return value.u.string.map { String(cString: $0) }
                case MPV_FORMAT_INT64: return String(value.u.int64)
                case MPV_FORMAT_DOUBLE: return String(value.u.double_)
                case MPV_FORMAT_FLAG: return value.u.flag == 0 ? "no" : "yes"
                default: return nil
                }
            }
            guard let kind = string("type").flatMap(Track.Kind.init(rawValue:)),
                  let id = string("id").flatMap(Int.init)
            else { return nil } // Video tracks aren't selectable here.
            return Track(
                id: id,
                kind: kind,
                title: string("title"),
                language: string("lang"),
                codec: string("codec"),
                channelCount: string("demux-channel-count").flatMap(Int.init),
                isForced: string("forced") == "yes",
                isHearingImpaired: string("hearing-impaired") == "yes",
                isSelected: string("selected") == "yes"
            )
        }
    }

    private func apply(_ event: Event) {
        switch event {
        case .commandReply(let id, let status):
            if id == 0 {
                check(status, "command")
            } else if activeSeek?.id == id {
                if status < 0 {
                    check(status, "seek")
                    completeSeek()
                }
            } else {
                completeTrackOperation(id: id, status: status)
            }
            return
        case .seekStarted:
            activeSeek?.started = true
            return
        case .playbackRestart(let value):
            if let value {
                exactPosition = value
                position = value.rounded(.down)
            }
            updateClock()
            if activeSeek?.started == true { completeSeek() }
            return
        case .fileLoaded:
            loadState = .loaded
        case .failed(let message):
            loadState = .failed(message)
            cancelSeeks()
        case .flag("pause", let value):
            isPaused = value
        case .flag("paused-for-cache", let value):
            isBuffering = value
        case .flag("eof-reached", let value):
            isEnded = value
        case .double("time-pos", let value):
            // mpv reports every frame; whole seconds are enough for the UI and
            // avoid redrawing the controls 24+ times a second.
            exactPosition = value ?? 0
            let seconds = exactPosition.rounded(.down)
            if seconds != position {
                position = seconds
            }
            // The clock extrapolates elapsed time; its rate changes only with state or speed.
            return
        case .double("duration", let value):
            duration = value
        case .tracks(let value):
            if value != tracks { tracks = value }
        case .videoFormat(let value):
            if value != videoFormat { videoFormat = value }
        case .string("hwdec-current", let value):
            playbackInfo.hardwareDecoder = value
            return
        case .integer("decoder-frame-drop-count", let value):
            playbackInfo.decoderDrops = value
            return
        case .integer("frame-drop-count", let value):
            playbackInfo.outputDrops = value
            return
        case .double("demuxer-cache-duration", let value):
            playbackInfo.bufferedSeconds = value
            return
        case .double("video-bitrate", let value):
            playbackInfo.videoBitrate = value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return
        case .double("audio-bitrate", let value):
            playbackInfo.audioBitrate = value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return
        case .flag, .double, .integer, .string:
            break
        }
        updateClock()
    }

    // MARK: - Picture in Picture

    private func updateClock() {
        guard let timebase = layer.controlTimebase else { return }
        let rate = status == .playing ? speed : 0
        if CMTimebaseGetRate(timebase) != rate {
            CMTimebaseSetRate(timebase, rate: rate)
        }
    }

    /// The file's span on the video layer's clock, which is what Picture in Picture
    /// measures progress against. The clock only runs while playing, so the span is
    /// shifted by however far it is from the playback position.
    var playbackTimeRange: CMTimeRange {
        guard let duration, let timebase = layer.controlTimebase else {
            // Live streams have no duration.
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        let start = CMTimebaseGetTime(timebase).seconds - exactPosition
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    // MARK: - Commands

    private func nextReplyID() -> UInt64 {
        nextCommandID &+= 1
        if nextCommandID == 0 { nextCommandID = 1 }
        return nextCommandID
    }

    private func runNextSeek() {
        guard !isShutDown, activeSeek == nil, !pendingSeeks.isEmpty else { return }
        let operation = pendingSeeks.removeFirst()
        let id = nextReplyID()
        activeSeek = (id, operation, false)
        // A demuxer can reject a queued seek without emitting a restart event. Don't
        // leave AVKit's controls locked indefinitely for an unseekable source.
        seekTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, activeSeek?.id == id else { return }
            log.error("Seek did not finish; releasing Picture in Picture controls")
            cancelSeeks()
        }
        command(["seek", String(operation.seconds), "relative"], replyID: id)
    }

    private func completeSeek() {
        seekTimeout?.cancel()
        seekTimeout = nil
        let completion = activeSeek?.operation.completion
        activeSeek = nil
        completion?()
        runNextSeek()
    }

    private func cancelSeeks() {
        seekTimeout?.cancel()
        seekTimeout = nil
        let completions = activeSeek.map { [$0.operation.completion] } ?? []
        let queued = pendingSeeks.map(\.completion)
        activeSeek = nil
        pendingSeeks = []
        for completion in completions + queued { completion() }
    }

    private func enqueueTrackOperation(_ operation: TrackOperation) {
        guard !isShutDown else { return }
        if operation.kind != nil {
            trackOperations.insert(operation, at: 0)
            if let active = activeTrackOperation, active.operation.arguments.first == "sub-add", !active.preempted {
                activeTrackOperation?.preempted = true
                mpv_abort_async_command(handle, active.id)
            }
        } else {
            trackOperations.append(operation)
        }
        runNextTrackOperation()
    }

    private func runNextTrackOperation() {
        guard !isShutDown, activeTrackOperation == nil else { return }
        if let load = pendingLoad {
            pendingLoad = nil
            load()
            return
        }
        guard !trackOperations.isEmpty else { return }
        let operation = trackOperations.removeFirst()
        let id = nextReplyID()
        activeTrackOperation = (id, operation, false)
        // libmpv may reorder async requests, so submit the next only after its reply.
        command(operation.arguments, replyID: id)
    }

    private func completeTrackOperation(id: UInt64, status: Int32) {
        guard let active = activeTrackOperation, active.id == id else { return }
        activeTrackOperation = nil
        if status < 0, active.preempted, pendingLoad == nil, !isShutDown {
            var retry = active.operation
            if hasSelectedSubtitles { retry.arguments[2] = "auto" }
            trackOperations.append(retry)
        }
        if status < 0, !active.preempted, pendingLoad == nil {
            check(status, active.operation.arguments[0])
            if let kind = active.operation.kind, !trackOperations.contains(where: { $0.kind == kind }) {
                trackError = "Couldn't switch \(kind == .audio ? "audio" : "subtitles"). \(String(cString: mpv_error_string(status)))."
            }
        }
        runNextTrackOperation()
    }

    private func command(_ args: [String], ignoringShutdown: Bool = false, replyID: UInt64? = nil) {
        guard !isShutDown || ignoringShutdown else { return }
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        let status = cArgs.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                if let replyID {
                    mpv_command_async(handle, replyID, $0)
                } else {
                    mpv_command(handle, $0)
                }
            }
        }
        if let replyID, replyID != 0 {
            if status < 0 { apply(.commandReply(replyID, status)) }
        } else {
            check(status, args[0])
        }
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
