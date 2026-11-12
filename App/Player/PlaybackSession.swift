import LogeCore
import SwiftUI
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "playback")

/// The playback in progress, if any. It outlives the player screen, so Picture in Picture
/// can keep playing after the screen closes and bring it back later. The screen itself is
/// only controls and gestures on top of this.
@MainActor @Observable
final class PlaybackSession {
    /// Changes when the next episode starts, without leaving the player.
    private(set) var current: PlaybackRequest?
    private(set) var player: MPVPlayer?
    private(set) var pictureInPicture: PictureInPicture?
    /// The following episode, looked up as the current one nears its end.
    private(set) var next: PlaybackRequest? {
        didSet { nowPlaying?.canPlayNext = next != nil }
    }
    /// Whether the player screen should show; false while only the floating window does.
    var isScreenPresented = false
    /// The source that was asked for didn't open, and another is being tried.
    private(set) var isTryingAnotherSource = false
    /// The sources being listed to switch to another file; the Mac's Playback menu opens it too.
    var choosingSource: SourcesRoute?

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let addons: AddonStore
    @ObservationIgnored private let trakt: TraktAccount
    @ObservationIgnored private let accountSync: AccountSync?
    @ObservationIgnored private var episodes: [Video] = []
    @ObservationIgnored private var isLookingUpNext = false
    @ObservationIgnored private var lastRecordedPosition: Double = 0
    @ObservationIgnored private var hasRememberedSource = false
    @ObservationIgnored private var hasReportedStart = false
    @ObservationIgnored private var nowPlaying: NowPlaying?
    /// Found while the file opens; mpv can only add them once it's open.
    @ObservationIgnored private var externalSubtitles: Task<[ExternalSubtitle], Never>?
    @ObservationIgnored private var isOpeningFile = false
    @ObservationIgnored private var skipLookup: Task<Void, Never>?
    @ObservationIgnored private var didLookUpSkipSegments = false
    /// Other sources for the same item, best first, tried when one doesn't open.
    @ObservationIgnored private var fallbacks: [PlaybackRequest] = []
    @ObservationIgnored private var openingTimeout: Task<Void, Never>?
    /// Set when the file opens; done once mpv reports the duration.
    @ObservationIgnored private var needsEstimatedSeek = false
    @ObservationIgnored private var estimatedResumeFraction: Double?
    @ObservationIgnored private var estimatedResumePosition: Double?
    /// Where this file was opened, in seconds: another source's position after a switch can lie
    /// past the end of a shorter file, which mpv then opens at its end.
    @ObservationIgnored private var openedAt: Double?
    @ObservationIgnored private var pendingRestore: ((Bool) -> Void)?
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    #if os(macOS)
    @ObservationIgnored private var displayActivity: NSObjectProtocol?
    #endif

    init(library: LibraryStore, addons: AddonStore, trakt: TraktAccount, accountSync: AccountSync? = nil) {
        self.library = library
        self.addons = addons
        self.trakt = trakt
        self.accountSync = accountSync
    }

    func start(_ request: PlaybackRequest, fallbacks: [PlaybackRequest] = []) {
        var request = request
        var usesCurrentPosition = false
        if let item = request.item, let currentItem = current?.item,
           item.id == currentItem.id, item.type == currentItem.type,
           let player, player.position > 0 {
            request.startAt = player.position
            usesCurrentPosition = true
        }
        // Keep the existing player screen mounted when its source is replaced.
        stopPlayback()
        self.fallbacks = fallbacks
        let player = MPVPlayer()
        let pictureInPicture = PictureInPicture(player: player)
        pictureInPicture.onStart = { [weak self] in self?.isScreenPresented = false }
        pictureInPicture.onRestore = { [weak self] completion in
            // Answered once the screen is back, so the window shrinks into it.
            guard let self else { completion(false); return }
            if isScreenPresented { completion(true); return }
            pendingRestore = completion
            isScreenPresented = true
        }
        pictureInPicture.onClose = { [weak self] in self?.end() }
        pictureInPicture.onFailure = { [weak self] in
            guard let self, isInBackground else { return }
            player.pause()
            player.setVideoEnabled(false)
        }
        self.player = player
        self.pictureInPicture = pictureInPicture
        nowPlaying = NowPlaying(player: player) { [weak self] in self?.playNext() }
        observe(player)
        load(request, resumeEstimatedProgress: !usesCurrentPosition)
        isScreenPresented = true
    }

    func end() {
        isScreenPresented = false
        stopPlayback()
        keepDisplayAwake(false)
    }

    /// The screen stays on while a video plays or is about to, and may sleep once it's paused.
    private func keepDisplayAwake(_ awake: Bool) {
        #if os(macOS)
        // mpv's video output on the Mac doesn't hold this itself, as AVPlayer would.
        if awake, displayActivity == nil {
            displayActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing video")
        } else if !awake, let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            self.displayActivity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }

    private func stopPlayback() {
        guard let player else { return }
        recordConnectionSpeed()
        recordProgress()
        scrobble(.stop)
        tasks.forEach { $0.cancel() }
        tasks = []
        choosingSource = nil
        openingTimeout?.cancel()
        externalSubtitles?.cancel()
        externalSubtitles = nil
        skipLookup?.cancel()
        skipLookup = nil
        fallbacks = []
        isTryingAnotherSource = false
        // AVKit can finish stopping after a replacement session has started.
        pictureInPicture?.onStart = {}
        pictureInPicture?.onRestore = { $0(false) }
        pictureInPicture?.onClose = {}
        pictureInPicture?.onFailure = {}
        pendingRestore?(false)
        pendingRestore = nil
        pictureInPicture?.stop()
        nowPlaying?.clear()
        player.shutDown()
        self.player = nil
        pictureInPicture = nil
        nowPlaying = nil
        current = nil
        next = nil
        episodes = []
    }

    #if DEBUG
    /// The playback fixture has no addon to look the next episode up from.
    func offerNextForTesting(_ request: PlaybackRequest) { next = request }
    #endif

    var canChooseSource: Bool { current?.item != nil }

    /// Lists the sources for what's playing; not for playback that has no title behind it.
    func chooseSource() {
        guard let current, let item = current.item else { return }
        choosingSource = SourcesRoute(item: item, title: current.title)
    }

    /// Opens the same file again after a failure, from where it stopped.
    func retry() {
        guard var request = current else { return }
        if lastRecordedPosition > 0 { request.startAt = lastRecordedPosition }
        load(request)
    }

    func playNext() {
        guard let next else { return }
        if let item = current?.item {
            recordProgress()
            // Skipping the credits shouldn't leave the episode looking unfinished.
            library.markWatched([item])
            trakt.scrobble(.stop, item, progress: 100)
        }
        // The alternatives were for the episode that just ended.
        fallbacks = []
        load(next)
    }

    // MARK: Screen

    func screenDidAppear() {
        pendingRestore?(true)
        pendingRestore = nil
    }

    /// The screen was closed: by the user, which ends playback, or by Picture in Picture
    /// taking over, which doesn't.
    func screenDidDisappear() {
        isScreenPresented = false
        if pictureInPicture?.isActive != true {
            end()
        }
    }

    func sceneDidEnterBackground() {
        // The app sends these while it still has time, rather than each saving starting its own.
        recordProgress(flushSync: false)
        isInBackground = true
        if let pictureInPicture {
            // AVKit may deliver its start callback after the scene backgrounds.
            if pictureInPicture.isActive || pictureInPicture.isStarting { return }
            #if os(iOS)
            if pictureInPicture.isPossible && player?.status == .playing { return }
            #endif
        }
        // mpv reports the pause asynchronously, which can be too late to send before suspension.
        scrobble(.pause)
        player?.pause()
        player?.setVideoEnabled(false)
    }

    func sceneDidBecomeActive() {
        guard isInBackground else { return }
        isInBackground = false
        // The window opened by itself on leaving, so coming back undoes that. One the viewer
        // opened to browse beside stays.
        if let pictureInPicture, pictureInPicture.isActive, !pictureInPicture.wasStartedByViewer {
            isScreenPresented = true
            pictureInPicture.returnToScreen()
        }
        player?.restoreVideoOutput()
    }

    // MARK: Playback

    private func load(_ request: PlaybackRequest, resumeEstimatedProgress: Bool = true) {
        guard let player else { return }
        recordConnectionSpeed()
        let episodesChanged = request.item?.metaID != current?.item?.metaID
        skipLookup?.cancel()
        skipLookup = nil
        didLookUpSkipSegments = false
        current = request
        nowPlaying?.show(request)
        next = nil
        isLookingUpNext = false
        hasRememberedSource = false
        hasReportedStart = false
        lastRecordedPosition = 0
        let defaults = UserDefaults.standard
        let audio = defaults.string(forKey: PlaybackPreferences.audioKey) ?? PlaybackPreferences.defaultAudioLanguage
        let subtitles = defaults.string(forKey: PlaybackPreferences.subtitleKey) ?? ""
        isOpeningFile = true
        needsEstimatedSeek = false
        estimatedResumeFraction = resumeEstimatedProgress
            ? request.item.flatMap { library.estimatedFraction(for: $0.id) } : nil
        estimatedResumePosition = nil
        openedAt = estimatedResumeFraction == nil ? request.startAt : nil
        openingTimeout?.cancel()
        openingTimeout = Task {
            // Debrid links that are still being cached can hang instead of failing.
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard current == request && isOpeningFile, !tryAnotherSource() else { return }
            player.failLoading("timed out")
        }
        externalSubtitles?.cancel()
        externalSubtitles = Task { await findSubtitles(for: request, preferring: subtitles) }
        let scale = defaults.object(forKey: PlaybackPreferences.subtitleScaleKey) as? Double ?? 1
        player.setSubtitleScale(scale)
        player.load(
            request.url,
            headers: request.headers,
            // Runtime estimates can exceed the file's real length; seek once its duration is known.
            startAt: estimatedResumeFraction == nil ? request.startAt : nil,
            audioLanguage: audio.isEmpty ? nil : audio,
            subtitleLanguage: subtitles.isEmpty ? nil : subtitles,
            // The languages subtitles are most likely turned on in: the sound's and the device's.
            hiddenSubtitleLanguages: [audio.isEmpty ? PlaybackPreferences.defaultAudioLanguage : audio]
                + Locale.preferredLanguages.prefix(1).compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        )
        if episodesChanged {
            episodes = []
            tasks.append(Task { await loadEpisodes() })
        }
    }

    private func observe(_ player: MPVPlayer) {
        tasks.append(Task { [weak self] in
            for await position in Observations({ player.position }) {
                self?.positionChanged(position)
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in Observations({ player.duration }) {
                self?.lookUpSkipSegmentsIfReady()
            }
        })
        tasks.append(Task { [weak self] in
            for await status in Observations({ player.status }) {
                self?.statusChanged(status)
            }
        })
    }

    private func positionChanged(_ position: Double) {
        if let target = estimatedResumePosition {
            guard position >= target - 1 else { return }
            estimatedResumePosition = nil
            estimatedResumeFraction = nil
            if player?.status == .playing { scrobble(.start) }
        }
        if needsEstimatedSeek && player?.duration != nil {
            needsEstimatedSeek = false
            if seekToEstimatedProgress() { return }
        }
        // Often enough that a crash or force-quit loses little, rarely enough not to churn storage.
        if abs(position - lastRecordedPosition) >= 10 {
            recordProgress(flushSync: false)
            if let item = current?.item, let progress = reportableProgress(for: item) {
                trakt.keepProgress(item, progress: progress)
            }
        }
        // Held back while sampling a source; see `reportableProgress`.
        if !hasReportedStart && player?.status == .playing { scrobble(.start) }
        lookUpNextIfDue()
    }

    private func lookUpSkipSegmentsIfReady() {
        guard !didLookUpSkipSegments, !isOpeningFile, let request = current,
              let item = request.item, let player, let duration = player.duration,
              duration.isFinite, duration > 0 else { return }
        didLookUpSkipSegments = true
        skipLookup = Task { [weak self] in
            do {
                let segments = try await SkipTimingClient().segments(for: item, duration: duration)
                guard !Task.isCancelled, let self, current == request, self.player === player else { return }
                player.setCommunitySegments(segments)
            } catch {
                guard !Task.isCancelled else { return }
                // Timing data is optional; playback continues with any embedded chapters.
                log.error("Community skip timings unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func statusChanged(_ status: MPVPlayer.Status) {
        keepDisplayAwake([.loading, .playing, .buffering].contains(status))
        let wasOpeningFile = isOpeningFile
        if isOpeningFile && status != .loading && status != .idle {
            isOpeningFile = false
            if !status.isFailed {
                isTryingAnotherSource = false
                addExternalSubtitles()
                needsEstimatedSeek = true
            }
        }
        if case .failed = status, wasOpeningFile, tryAnotherSource() {
            return
        }
        lookUpSkipSegmentsIfReady()
        switch status {
        case .playing:
            rememberSource()
            scrobble(.start)
        case .paused:
            recordProgress()
            scrobble(.pause)
        case .ended:
            if openedPastEnd, let player, let duration = player.duration {
                // Not watched: nothing played. Near the end, as close as this file allows, and
                // not saved before that seek lands, so the time between isn't saved as the end.
                let opened = openedAt
                player.seek(to: max(duration - 30, 0)) { [weak self] in
                    // Unless another file has been opened meanwhile.
                    if self?.openedAt == opened { self?.openedAt = nil }
                }
                player.play()
                return
            }
            recordProgress()
            lookUpNextIfDue()
            continueInPictureInPicture()
        case .failed:
            // A remembered source that no longer plays shouldn't be tried again.
            if let item = current?.item { library.forgetSource(metaID: item.metaID) }
        default:
            break
        }
    }

    /// Lets Trakt follow along; the account keeps its completion threshold aligned with the library.
    private func scrobble(_ action: TraktClient.ScrobbleAction) {
        guard let item = current?.item, let progress = reportableProgress(for: item) else { return }
        hasReportedStart = action == .start
        trakt.scrobble(action, item, progress: progress)
    }

    /// 0–100, once playback is worth telling Trakt about. Sampling a source isn't saved here, and
    /// reporting it would cost another device its position: a pause replaces that position, and
    /// a start removes it.
    private func reportableProgress(for item: WatchItem) -> Double? {
        guard estimatedResumeFraction == nil, !openedPastEnd, let player, let duration = player.duration, duration > 0,
              library.recordsProgress(for: item.id, at: player.position) else { return nil }
        return player.position / duration * 100
    }

    /// Progress from another device is a percentage; now that the real duration is known,
    /// go to the exact spot.
    private func seekToEstimatedProgress() -> Bool {
        guard let fraction = estimatedResumeFraction, let player, let duration = player.duration
        else { return false }
        // The seek is asynchronous; preserve the remote entry until its position arrives.
        let target = max(fraction * duration - 5, 0)
        estimatedResumePosition = target
        player.seek(to: target) { [weak self] in
            // Or until playback restarts anywhere else: a seek back made before this one landed
            // replaces it, and waiting for the target would hold back saving and scrobbling
            // until playback passed it again. A new file has cleared the target already.
            guard let self, estimatedResumePosition == target else { return }
            estimatedResumePosition = nil
            estimatedResumeFraction = nil
            if player.status == .playing { scrobble(.start) }
        }
        return true
    }

    /// Before the file changes, which starts a new measurement. Files served from this
    /// machine, such as the test addon's, say nothing about the network.
    private func recordConnectionSpeed() {
        guard let speed = player?.measuredDownloadSpeed, let host = current?.url.host(),
              !["127.0.0.1", "localhost", "::1"].contains(host) else { return }
        ConnectionSpeed.record(speed)
    }

    /// Whether the file opened at its end because the position it was opened at lies beyond it.
    private var openedPastEnd: Bool {
        guard let openedAt, let duration = player?.duration else { return false }
        return openedAt >= duration - 1
    }

    private func recordProgress(flushSync: Bool = true) {
        // Live streams have no duration, and nothing is known before the file has loaded.
        guard !isOpeningFile, estimatedResumeFraction == nil, !openedPastEnd, let item = current?.item, let player,
              let duration = player.duration, player.position > 0 else { return }
        library.record(item, position: player.position, duration: duration)
        lastRecordedPosition = player.position
        if flushSync, let accountSync {
            Task { await accountSync.sync() }
        }
    }

    private func rememberSource() {
        guard !hasRememberedSource, let current, let item = current.item, let providerURL = current.providerURL else { return }
        hasRememberedSource = true
        library.rememberSource(
            RememberedSource(itemID: item.id, providerURL: providerURL, url: current.url,
                             headers: current.headers, bingeGroup: current.bingeGroup),
            metaID: item.metaID
        )
    }

    /// Switches to the next alternative, keeping the resume position. Failures once a
    /// file is playing aren't retried, since starting a different file would surprise.
    @discardableResult
    private func tryAnotherSource() -> Bool {
        guard !fallbacks.isEmpty, let current else { return false }
        var request = fallbacks.removeFirst()
        request.startAt = current.startAt
        isTryingAnotherSource = true
        load(request)
        return true
    }

    // MARK: Subtitles

    private struct ExternalSubtitle {
        let url: String
        let title: String
        let language: String
        let isPreferred: Bool
    }

    /// The stream's own subtitles, plus those from subtitle addons in the preferred
    /// language and the device's, a few per language so the menu stays short.
    private func findSubtitles(for request: PlaybackRequest, preferring preferred: String) async -> [ExternalSubtitle] {
        var wanted = preferred.isEmpty ? [] : [preferred]
        for identifier in Locale.preferredLanguages.prefix(2) {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier, !wanted.contains(code) {
                wanted.append(code)
            }
        }
        func external(_ subtitle: Subtitle, title: String) -> ExternalSubtitle {
            ExternalSubtitle(url: subtitle.url, title: title, language: subtitle.lang,
                             isPreferred: !preferred.isEmpty && LanguageCodes.alpha2(for: subtitle.lang) == preferred)
        }

        var found = request.subtitles.map { external($0, title: "Stream") }
        guard let item = request.item else { return found }
        let providers = addons.addons.subtitleProviders(type: item.type, id: item.id)
        let results = await withTaskGroup(of: (index: Int, subtitles: [Subtitle]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    // Awaited on its own line, as in SourcesView: Release builds have mishandled
                    // child results awaited inside a larger expression.
                    let subtitles = try? await provider.subtitles(type: item.type, id: item.id, filename: request.filename)
                    return (index, subtitles ?? [])
                }
            }
            var results: [(index: Int, subtitles: [Subtitle])] = []
            for await result in group {
                results.append(result)
            }
            // Back in the user's addon order.
            return results.sorted { $0.index < $1.index }
        }
        // Numbered per language so the track menu tells them apart; addon names aren't shown.
        var counts: [String: Int] = [:]
        for (_, subtitles) in results {
            // Addons list their best matches first.
            let byLanguage = Dictionary(grouping: subtitles) { LanguageCodes.alpha2(for: $0.lang) ?? "" }
            for language in wanted {
                for subtitle in (byLanguage[language] ?? []).prefix(3) {
                    let number = (counts[language] ?? 0) + 1
                    counts[language] = number
                    found.append(external(subtitle, title: "Addon \(number)"))
                }
            }
        }
        return found
    }

    private func addExternalSubtitles() {
        guard let request = current, let task = externalSubtitles else { return }
        Task {
            let subtitles = await task.value
            guard !task.isCancelled, current == request, let player else { return }
            // Switch one on only if the file had nothing in the preferred language.
            var shouldSelect = !player.tracks.contains { $0.kind == .sub && $0.isSelected }
            for subtitle in subtitles {
                let select = shouldSelect && subtitle.isPreferred
                player.addSubtitle(url: subtitle.url, title: subtitle.title, language: subtitle.language, select: select)
                if select { shouldSelect = false }
            }
        }
    }

    // MARK: Next episode

    private func loadEpisodes() async {
        guard let item = current?.item, item.type == MediaType.series,
              let client = addons.addons.metaClient(type: item.type, id: item.metaID)
        else { return }
        let videos = (try? await client.meta(type: item.type, id: item.metaID).videos) ?? []
        guard !Task.isCancelled, current?.item?.metaID == item.metaID,
              current?.item?.type == item.type else { return }
        episodes = videos
        lookUpNextIfDue()
    }

    /// The floating window has no countdown to cancel, so it goes straight on to the
    /// next episode, as the countdown would have.
    private func continueInPictureInPicture() {
        guard pictureInPicture?.isActive == true, next != nil else { return }
        playNext()
    }

    /// Starts looking for the next episode a minute before it's offered.
    private func lookUpNextIfDue() {
        guard !isLookingUpNext, next == nil, let current, !episodes.isEmpty,
              let player, let duration = player.duration,
              player.position >= NextEpisode.offerTime(duration: duration) - 60 || player.status == .ended
        else { return }
        isLookingUpNext = true
        let episodes = episodes
        tasks.append(Task {
            do {
                let found = try await NextEpisode.request(after: current, episodes: episodes)
                // The episode may have changed while the lookup ran.
                guard self.current == current else { return }
                self.next = found
                if self.player?.status == .ended { self.continueInPictureInPicture() }
            } catch {
                guard !Task.isCancelled, self.current == current else { return }
                log.error("Next episode lookup failed: \(error.localizedDescription)")
                // Tried again later rather than on every position update, so a struggling addon
                // isn't asked each second; at the end, nothing else would ask again.
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard self.current == current else { return }
                self.isLookingUpNext = false
                self.lookUpNextIfDue()
            }
        })
    }
}
