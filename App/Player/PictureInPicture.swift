import AVKit

/// Picture in Picture for an `MPVPlayer`'s video layer. The floating window's play, pause
/// and skip buttons drive mpv, and its progress follows the player's clock.
@MainActor @Observable
final class PictureInPicture: NSObject {
    private(set) var isActive = false
    private(set) var isPossible = false

    /// The floating window took over; the player screen can close.
    @ObservationIgnored var onStart: () -> Void = {}
    /// Show the player screen again, then call the completion handler.
    @ObservationIgnored var onRestore: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// The window was closed rather than expanded, which ends playback.
    @ObservationIgnored var onClose: () -> Void = {}

    @ObservationIgnored private let player: MPVPlayer
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var playbackObservation: Task<Void, Never>?

    init(player: MPVPlayer) {
        self.player = player
        super.init()
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
            for await _ in Observations({ (player.status, player.position) }) {
                self?.controller?.invalidatePlaybackState()
            }
        }
    }

    // The observation holds the player, so it has to end with this object.
    isolated deinit {
        playbackObservation?.cancel()
    }

    func start() { controller?.startPictureInPicture() }
    func stop() { controller?.stopPictureInPicture() }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            onStart()
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // AVKit calls this on the main thread, where the handler is later called too.
        nonisolated(unsafe) let completionHandler = completionHandler
        MainActor.assumeIsolated {
            isRestoring = true
            onRestore(completionHandler)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            if !isRestoring { onClose() }
            isRestoring = false
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        MainActor.assumeIsolated { isActive = false }
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { playing ? player.play() : player.pause() }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated { player.playbackTimeRange }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { player.status != .playing }
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
        MainActor.assumeIsolated { player.seek(by: skipInterval.seconds) }
        completionHandler()
    }
}
