import Foundation

/// Stable title links; review text and scores require licensed provider access.
public enum ReviewLinks {
    public static func imdb(imdbID: String) -> URL? {
        guard MediaType.isIMDbTitle(imdbID) else { return nil }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/")
    }
}
