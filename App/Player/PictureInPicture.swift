import AVKit
import Synchronization

/// Picture in Picture for an `MPVPlayer`'s video layer. The floating window's play, pause
/// and skip buttons drive mpv, and its progress follows the player's clock.
@MainActor @Observable
final class PictureInPicture: NSObject {
    private(set) var isActive = false
    private(set) var isStarting = false
    private(set) var isPossible = false
    private(set) var failureMessage: String?

    /// The floating window took over; the player screen can close.
    @ObservationIgnored var onStart: () -> Void = {}
    /// Show the player screen again, then call the completion handler.
    @ObservationIgnored var onRestore: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// The window was closed rather than expanded, which ends playback.
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onFailure: () -> Void = {}

    @ObservationIgnored private let player: MPVPlayer
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var playbackObservation: Task<Void, Never>?
    private struct PlaybackState: Sendable {
        var timeRange = CMTimeRange.invalid
        var isPaused = true
    }
    // AVKit queries playback synchronously from outside the main actor.
    @ObservationIgnored nonisolated private let playbackState = Mutex(PlaybackState())

    init(player: MPVPlayer) {
        self.player = player
        super.init()
        playbackState.withLock {
            $0 = PlaybackState(timeRange: player.playbackTimeRange, isPaused: player.isPlaybackPaused)
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(contentSource: .init(
            sampleBufferDisplayLayer: player.layer, playbackDelegate: self))
        controller.delegate = self
        #if os(iOS)
        // Going to the Home Screen while playing moves the video into the floating window.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
        self.controller = controller

        // The floating window asks for the time range and paused state only when told
        // they changed: on every play, pause, seek, and once a second as time passes.
        playbackObservation = Task { [weak self, player] in
            for await _ in Observations({ (player.isPlaybackPaused, player.position, player.duration, player.speed) }) {
                guard let self else { return }
                refreshPlaybackState()
            }
        }
    }

    // The observation holds the player, so it has to end with this object.
    isolated deinit {
        playbackObservation?.cancel()
    }

    func start() {
        guard isPossible, !isActive, !isStarting else { return }
        isStopping = false
        failureMessage = nil
        isStarting = true
        controller?.startPictureInPicture()
    }

    func stop() {
        isStopping = true
        isStarting = false
        playbackObservation?.cancel()
        playbackObservation = nil
        possibleObservation?.invalidate()
        possibleObservation = nil
        // The controller can outlive this session, and with playback last seen as playing
        // it would float the closed player on the next trip to the Home Screen.
        #if os(iOS)
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        #endif
        playbackState.withLock { $0.isPaused = true }
        controller?.invalidatePlaybackState()
        controller?.stopPictureInPicture()
    }

    func dismissFailure() { failureMessage = nil }

    private func refreshPlaybackState() {
        let state = PlaybackState(timeRange: player.playbackTimeRange, isPaused: isStopping || player.isPlaybackPaused)
        playbackState.withLock { $0 = state }
        controller?.invalidatePlaybackState()
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { return }
            isStarting = true
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { return }
            isStarting = false
            isActive = true
            onStart()
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // Transfer AVKit's completion to the main actor and always answer it there.
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { completionHandler(false); return }
            isRestoring = true
            onRestore(completionHandler)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isStarting = false
            isActive = false
            if !isRestoring && !isStopping { onClose() }
            isRestoring = false
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isStarting = false
            isActive = false
            if !isStopping {
                failureMessage = "Picture in Picture couldn't start. Try again while the video is playing."
                onFailure()
            }
        }
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { return }
            if playing { player.play() } else { player.pause() }
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        playbackState.withLock { $0.timeRange }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        playbackState.withLock { $0.isPaused }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor [weak self] in
            guard let self, !isStopping else { completionHandler(); return }
            player.seek(by: skipInterval.seconds) { [weak self] in
                self?.refreshPlaybackState()
                completionHandler()
            }
        }
    }
}
