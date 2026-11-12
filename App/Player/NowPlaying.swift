import MediaPlayer
import LogeCore

#if os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#else
import UIKit
private typealias PlatformImage = UIImage
#endif

/// Shows the playing title on the Lock Screen, in Control Center and the Mac's Now Playing,
/// and routes their buttons, headphone controls and the Siri Remote to the player.
@MainActor
final class NowPlaying {
    private let player: MPVPlayer
    private var request: PlaybackRequest?
    private var artwork: MPMediaItemArtwork?
    private var tasks: [Task<Void, Never>] = []
    private var artworkTask: Task<Void, Never>?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    /// The elapsed time last reported, and when and at what rate, to tell a seek from playback.
    private var reported: (position: Double, date: Date, rate: Double)?
    private let playNext: @MainActor () -> Void
    /// Whether the next track button skips to the next episode: only once there is one.
    var canPlayNext = false {
        didSet { MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = canPlayNext }
    }

    init(player: MPVPlayer, playNext: @escaping @MainActor () -> Void) {
        self.player = player
        self.playNext = playNext
        registerCommands()
        tasks.append(Task { [weak self, player] in
            for await _ in Observations({ (player.status, player.duration, player.speed) }) {
                self?.update()
            }
        })
        tasks.append(Task { [weak self, player] in
            for await position in Observations({ player.position }) {
                self?.positionChanged(position)
            }
        })
    }

    /// The system extrapolates elapsed time from the rate, so only a jump, such as a seek,
    /// needs reporting rather than every second.
    private func positionChanged(_ position: Double) {
        guard let reported else { return }
        let expected = reported.position + Date.now.timeIntervalSince(reported.date) * reported.rate
        if abs(position - expected) > 2 { update() }
    }

    func show(_ request: PlaybackRequest) {
        artworkTask?.cancel()
        self.request = request
        artwork = nil
        update()
        guard let url = request.item.flatMap({ $0.thumbnail ?? $0.background ?? $0.poster }).flatMap(URL.init(string:)) else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = PlatformImage(data: data),
                  self?.request == request
            else { return }
            self?.artwork = Self.artwork(image)
            self?.update()
        }
    }

    /// MediaPlayer asks for the image on its own queue, so the closure mustn't belong to the main actor.
    private nonisolated static func artwork(_ image: PlatformImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func clear() {
        request = nil
        artwork = nil
        artworkTask?.cancel()
        artworkTask = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets = []
        canPlayNext = false
        reported = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    private func update() {
        guard let request else { return }
        let item = request.item
        let rate = player.status == .playing ? player.speed : 0
        reported = (player.position, .now, rate)
        var info: [String: Any] = [
            // Episodes show their own title over the series name, like the TV app.
            MPMediaItemPropertyTitle: item?.episodeTitle ?? request.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if item?.episodeTitle != nil, let series = item?.title {
            info[MPMediaItemPropertyArtist] = series
        }
        if let duration = player.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = player.status == .playing ? .playing : .paused
        #endif
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        let player = player
        // The system calls these handlers on the main thread.
        // At the end, playing starts over, as the player's own button does.
        add(center.playCommand) { _ in
            MainActor.assumeIsolated { player.status == .ended ? player.togglePause() : player.play() }
        }
        add(center.pauseCommand) { _ in MainActor.assumeIsolated { player.pause() } }
        add(center.togglePlayPauseCommand) { _ in MainActor.assumeIsolated { player.togglePause() } }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.skipForwardCommand) { _ in MainActor.assumeIsolated { player.seek(by: 10) } }
        add(center.skipBackwardCommand) { _ in MainActor.assumeIsolated { player.seek(by: -10) } }
        let playNext = playNext
        center.nextTrackCommand.isEnabled = false
        add(center.nextTrackCommand) { _ in MainActor.assumeIsolated { playNext() } }
        add(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            MainActor.assumeIsolated { player.seek(to: time) }
            return .success
        }
    }

    private func add(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        commandTargets.append((command, command.addTarget(handler: handler)))
    }

    private func add(_ command: MPRemoteCommand, action: @escaping (MPRemoteCommandEvent) -> Void) {
        add(command) { event in
            action(event)
            return .success
        }
    }
}
