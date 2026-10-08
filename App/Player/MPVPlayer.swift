import Foundation
import Libmpv
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

    private(set) var position: Double = 0
    private(set) var duration: Double?

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
            ("subs-match-os-language", "yes"),
            ("subs-fallback", "yes"),
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

        startEventThread()
    }

    isolated deinit {
        shutDown()
    }

    func load(_ url: URL) {
        guard !isShutDown else { return }
        loadState = .loading
        position = 0
        duration = nil
        command(["loadfile", url.absoluteString, "replace"])
    }

    func togglePause() {
        command(["cycle", "pause"])
    }

    func seek(by seconds: Double) {
        command(["seek", String(seconds), "relative"])
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
                if let parsed = Self.parse(event) {
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

    private nonisolated static func parse(_ event: mpv_event) -> Event? {
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
            position = value ?? 0
        case .double("duration", let value):
            duration = value
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
