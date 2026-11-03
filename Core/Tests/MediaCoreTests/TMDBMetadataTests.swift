import Testing
@testable import MediaCore

struct TMDBMetadataTests {
    @Test func enrichmentChangesDisplayFieldsWithoutChangingPlaybackIdentity() {
        let episode = Video(id: "tt123:2:4", title: "Episode Four", season: 2, episode: 4)
        let original = Meta(
            id: "tt123", type: "series", name: "Addon Title", poster: "addon-poster",
            background: "addon-background", logo: "addon-logo", description: "Addon overview",
            releaseInfo: "2020–2025", runtime: "40 min", genres: ["Drama"], imdbRating: "8.4",
            cast: ["Addon Actor"], director: ["Addon Director"], writer: ["Addon Writer"],
            videos: [episode])
        let details = TMDBDetails(
            overview: "TMDB overview", posterURL: "tmdb-poster", backgroundURL: "tmdb-background",
            releaseInfo: "2020", runtime: "45 min", genres: ["Mystery"])

        let result = details.applying(to: original)

        #expect(result.description == "TMDB overview")
        #expect(result.poster == "tmdb-poster")
        #expect(result.background == "tmdb-background")
        #expect(result.runtime == "45 min")
        #expect(result.genres == ["Mystery"])
        #expect(result.releaseInfo == "2020–2025")
        #expect(result.id == "tt123")
        #expect(result.type == "series")
        #expect(result.name == "Addon Title")
        #expect(result.logo == "addon-logo")
        #expect(result.imdbRating == "8.4")
        #expect(result.videos == [episode])
        #expect(result.videos?.first?.id == "tt123:2:4")
        #expect(result.cast == original.cast)
        #expect(result.director == original.director)
        #expect(result.writer == original.writer)
    }

    @Test func absentProviderFieldsKeepExistingMetadata() throws {
        let original = try decodeFixture("cinemeta-meta-movie", as: MetaResponse.self).meta
        #expect(TMDBDetails().applying(to: original) == original)
    }

    @Test func partialProviderMetadataFallsBackFieldByField() {
        let original = Meta(
            id: "tt123", type: "movie", name: "Movie", poster: "addon-poster",
            background: "addon-background", description: "Addon overview", releaseInfo: "2021",
            runtime: "90 min", genres: ["Drama"])
        let result = TMDBDetails(overview: "TMDB overview", runtime: "95 min").applying(to: original)
        #expect(result.description == "TMDB overview")
        #expect(result.runtime == "95 min")
        #expect(result.poster == "addon-poster")
        #expect(result.background == "addon-background")
        #expect(result.releaseInfo == "2021")
        #expect(result.genres == ["Drama"])
    }

    @Test func releaseYearEnrichesMoviesAndSeriesWithoutExistingDates() {
        let details = TMDBDetails(releaseInfo: "2022")
        let movie = Meta(id: "tt123", type: "movie", name: "Movie", releaseInfo: "2021")
        let series = Meta(id: "tt456", type: "series", name: "Series")
        #expect(details.applying(to: movie).releaseInfo == "2022")
        #expect(details.applying(to: series).releaseInfo == "2022")
    }

    @Test func previewFallbackRetainsOriginalIdentityAndAvailableMetadata() {
        let preview = MetaPreview(
            id: "tt123", type: "movie", name: "Preview Title", poster: "preview-poster",
            releaseInfo: "2021", background: "preview-background", logo: "preview-logo",
            description: "Preview overview", imdbRating: "8.1", genres: ["Drama"], runtime: "90 min",
            cast: ["Actor"], director: ["Director"], writer: ["Writer"])
        let result = TMDBDetails(overview: "TMDB overview", runtime: "95 min").meta(for: preview)

        #expect(result.id == preview.id)
        #expect(result.type == preview.type)
        #expect(result.name == preview.name)
        #expect(result.logo == preview.logo)
        #expect(result.imdbRating == preview.imdbRating)
        #expect(result.poster == preview.poster)
        #expect(result.background == preview.background)
        #expect(result.releaseInfo == preview.releaseInfo)
        #expect(result.genres == preview.genres)
        #expect(result.cast == preview.cast)
        #expect(result.director == preview.director)
        #expect(result.writer == preview.writer)
        #expect(result.description == "TMDB overview")
        #expect(result.runtime == "95 min")
        #expect(result.videos == nil)
    }

    @Test func creditedPeopleUseProviderIDsAndPreservePortraitsCharactersAndRoles() {
        let details = TMDBDetails(people: [
            TMDBPerson(id: 12, name: "Alex Lee", profileURL: "portrait-12", roles: [.actor, .director], character: "The Pilot"),
            TMDBPerson(id: 34, name: "Alex Lee", roles: [.writer]),
        ])
        let people = details.creditedPeople

        #expect(people.map(\.id) == ["tmdb:12", "tmdb:34"])
        #expect(Set(people.map(\.id)).count == 2)
        #expect(people.map(\.name) == ["Alex Lee", "Alex Lee"])
        #expect(people[0].tmdbID == 12)
        #expect(people[0].portraitURL == "portrait-12")
        #expect(people[0].character == "The Pilot")
        #expect(people[0].roles == [.actor, .director])
        #expect(people[1].portraitURL == nil)
        #expect(people[1].character == nil)
        #expect(people[1].roles == [.writer])
        #expect(Person(name: "Alex Lee", roles: [.actor]).id == "Alex Lee")
    }
}
