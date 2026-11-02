import Foundation

extension TMDBDetails {
    /// TMDB enriches display fields; addon episode IDs and IMDb ratings keep their original meaning.
    public func applying(to meta: Meta) -> Meta {
        var result = meta
        result.description = overview ?? meta.description
        result.poster = posterURL ?? meta.poster
        result.background = backgroundURL ?? meta.background
        result.releaseInfo = meta.type == "series" ? meta.releaseInfo ?? releaseInfo : releaseInfo ?? meta.releaseInfo
        result.runtime = runtime ?? meta.runtime
        result.genres = genres ?? meta.genres
        return result
    }

    public func meta(for preview: MetaPreview) -> Meta {
        applying(to: Meta(id: preview.id, type: preview.type, name: preview.name,
                          poster: preview.poster, background: preview.background, logo: preview.logo,
                          description: preview.description, releaseInfo: preview.releaseInfo,
                          runtime: preview.runtime, genres: preview.genres, imdbRating: preview.imdbRating,
                          cast: preview.cast, director: preview.director, writer: preview.writer))
    }

    public var creditedPeople: [Person] {
        people.map {
            Person(name: $0.name, roles: $0.roles, tmdbID: $0.id, portraitURL: $0.profileURL, character: $0.character)
        }
    }
}
