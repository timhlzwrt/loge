import Foundation
import Testing
@testable import LogeCore

@MainActor
struct EpisodeScheduleTests {
    let defaults = UserDefaults(suiteName: "EpisodeScheduleTests-\(UUID().uuidString)")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60

    func episode(_ number: Int, of show: String = "tt9") -> WatchItem {
        WatchItem(id: "\(show):1:\(number)", type: "series", metaID: show, title: "Show", season: 1, episode: number,
                  background: "https://img/backdrop")
    }

    /// Season one of `show`, an episode a week: the first aired `firstAired` days from now.
    func meta(_ show: String = "tt9", firstAired: Double, count: Int = 4) -> Meta {
        let videos = (1...count).map { number in
            Video(id: "\(show):1:\(number)", title: "Episode \(number)", season: 1, episode: number,
                  released: now.addingTimeInterval((firstAired + Double(number - 1) * 7) * day).ISO8601Format())
        }
        // Out of order, with a special that has no place in the schedule.
        return Meta(id: show, type: "series", name: "Show",
                    videos: videos.reversed() + [Video(id: "\(show):0:1", season: 0, episode: 1)])
    }

    func schedule(_ library: LibraryStore, _ metas: Meta...) async -> EpisodeSchedule {
        let schedule = EpisodeSchedule()
        await schedule.refresh(for: library, at: now) { id in metas.first { $0.id == id } }
        return schedule
    }

    @Test func anEpisodeAiredSinceTheLastOneWasFinishedIsNew() async {
        let library = LibraryStore(defaults: defaults)
        // Episode 2 was out when episode 1 was watched; episode 3 aired yesterday.
        library.record(episode(2), position: 1990, duration: 2000, at: now - 3 * day)
        let schedule = await schedule(library, meta(firstAired: -15))

        let new = schedule.newEpisodes(in: library, at: now)
        #expect(new.map(\.item.id) == ["tt9:1:3"])
        #expect(new.first?.item.episodeTitle == "Episode 3")
        #expect(new.first?.item.background == "https://img/backdrop")
        #expect(new.first?.date == now - day)
        #expect(schedule.upcoming(in: library, at: now).map(\.item.id) == ["tt9:1:4"])

        // Once it's started it has its own Continue Watching entry.
        library.record(episode(3), position: 600, duration: 2000, at: now)
        #expect(schedule.newEpisodes(in: library, at: now).isEmpty)
    }

    @Test func anEpisodeThatWasAlreadyOutIsntNew() async {
        let library = LibraryStore(defaults: defaults)
        library.record(episode(1), position: 1990, duration: 2000, at: now - day)
        let schedule = await schedule(library, meta(firstAired: -300))

        #expect(schedule.newEpisodes(in: library, at: now).isEmpty)
        #expect(schedule.upcoming(in: library, at: now).isEmpty)
    }

    @Test func anUnfinishedEpisodeHoldsBackTheNextOne() async {
        let library = LibraryStore(defaults: defaults)
        library.record(episode(2), position: 600, duration: 2000, at: now - 3 * day)
        let schedule = await schedule(library, meta(firstAired: -15))

        #expect(schedule.newEpisodes(in: library, at: now).isEmpty)
    }

    @Test func upcomingListsEachSeriesNextEpisodeSoonestFirst() async {
        let library = LibraryStore(defaults: defaults)
        library.record(episode(1), position: 1990, duration: 2000, at: now - day)
        library.record(episode(1, of: "tt8"), position: 1990, duration: 2000, at: now - 2 * day)
        library.record(WatchItem(id: "tt1", type: "movie", metaID: "tt1", title: "Movie"), position: 600, duration: 6000, at: now)
        let schedule = await schedule(library, meta(firstAired: -4), meta("tt8", firstAired: -6))

        #expect(schedule.upcoming(in: library, at: now).map(\.item.id) == ["tt8:1:2", "tt9:1:2"])

        // Removed from Continue Watching, a series is no longer followed.
        library.removeFromContinueWatching(metaID: "tt8")
        #expect(schedule.upcoming(in: library, at: now).map(\.item.id) == ["tt9:1:2"])
    }

    @Test func episodesAreLookedUpAgainOnlyOnceTheyreStale() async {
        let library = LibraryStore(defaults: defaults)
        library.record(episode(1), position: 1990, duration: 2000, at: now - day)
        let schedule = EpisodeSchedule()
        var lookups = 0
        let lookup: (String) async -> Meta? = { _ in
            lookups += 1
            return self.meta(firstAired: -4)
        }
        await schedule.refresh(for: library, at: now, lookup: lookup)
        await schedule.refresh(for: library, at: now + 60, lookup: lookup)
        #expect(lookups == 1)
        await schedule.refresh(for: library, force: true, at: now + 120, lookup: lookup)
        await schedule.refresh(for: library, at: now + EpisodeSchedule.lifetime + 180, lookup: lookup)
        #expect(lookups == 3)

        // A failed lookup keeps what was known.
        await schedule.refresh(for: library, force: true, at: now + 240) { _ in nil }
        #expect(schedule.upcoming(in: library, at: now).count == 1)
    }
}
