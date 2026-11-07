import Foundation

/// Stable title links; review text and scores require licensed provider access.
public enum ReviewLinks {
    public static func critics(imdbID: String) -> URL? {
        guard isIMDbTitle(imdbID) else { return nil }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/externalreviews/")
    }

    public static func letterboxd(imdbID: String, type: String) -> URL? {
        guard type == MediaType.movie, isIMDbTitle(imdbID) else { return nil }
        return URL(string: "https://letterboxd.com/imdb/\(imdbID)/")
    }

    private static func isIMDbTitle(_ id: String) -> Bool {
        id.wholeMatch(of: /tt\d+/) != nil
    }
}
