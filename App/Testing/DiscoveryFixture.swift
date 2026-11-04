#if DEBUG
import Foundation
import LogeCore
import SwiftUI

/// Deterministic API responses keep UI comparisons independent of credentials and changing provider data.
@MainActor
enum DiscoveryFixture {
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    static let title = MetaPreview(id: "tt0816692", type: "movie", name: "Interstellar")

    @ViewBuilder
    static var screen: some View {
        switch ProcessInfo.processInfo.environment["DISCOVERY_SCREEN"] {
        case "library":
            if let library = library {
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        ContinueWatchingRow()
                        MyListRow()
                    }
                    .padding(.vertical, 24)
                }
                .environment(library)
                .background(Color.canvas)
                .navigationTitle("Library")
            }
        case "person":
            PersonView(route: PersonRoute(person: Person(name: "Christopher Nolan", roles: [.director], tmdbID: 525)))
        case "festival":
            FilmCollectionView(collection: .sundance, client: FilmCollectionClient(session: session))
        case "directors":
            ScrollView {
                if ProcessInfo.processInfo.environment["DISCOVERY_BASELINE"] == "1" {
                    DiscoveryCollectionRow(title: "Popular Directors", collections: FilmCollection.directors)
                } else {
                    PopularDirectorsRow()
                }
            }
            .background(Color.canvas)
            .navigationTitle("Directors")
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    ReviewsSection(preview: title)
                    PopularDirectorsRow()
                }
                .padding(.vertical, 24)
            }
            .background(Color.canvas)
            .navigationTitle("Discovery")
        }
    }

    private static let library: LibraryStore? = {
        let suite = "loge.discovery-library-fixture"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        let library = LibraryStore(defaults: defaults)
        for index in (1...12).reversed() {
            library.record(WatchItem(id: "fixture-series-\(index):1:2", type: "series",
                                     metaID: "fixture-series-\(index)", title: "Resume \(index)",
                                     season: 1, episode: 2), position: 600, duration: 2400)
            library.toggleSaved(MetaPreview(id: "fixture-movie-\(index)", type: "movie", name: "Saved \(index)"))
        }
        return library
    }()
}

private final class DiscoveryFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch url.path {
        case "/3/person/525":
            body = #"{"id":525,"name":"Christopher Nolan","known_for_department":"Directing","biography":"Director and screenwriter.","combined_credits":{"cast":[{"id":43654,"media_type":"movie","title":"The Science of Interstellar","character":"Self","release_date":"2014-11-25"}],"crew":[{"id":157336,"media_type":"movie","title":"Interstellar","job":"Director","release_date":"2014-11-05"},{"id":27205,"media_type":"movie","title":"Inception","job":"Director","release_date":"2010-07-15"},{"id":49026,"media_type":"movie","title":"The Dark Knight Rises","job":"Producer","release_date":"2012-07-16"}]}}"#
        case "/3/find/tt0816692": body = #"{"movie_results":[{"id":157336}],"tv_results":[]}"#
        case "/3/movie/157336/reviews":
            body = #"{"id":157336,"page":1,"total_pages":1,"total_results":1,"results":[{"id":"fixture-review","author":"Film viewer","author_details":{"rating":8},"content":"A patient, ambitious journey that gives its enormous images a human scale. The quiet scenes between Cooper and Murph are what stayed with me.\n\nThe ending invites discussion, but the film earns its sense of wonder. This text was written for the offline UI test.","created_at":"2026-01-15T12:00:00Z","url":"https://www.themoviedb.org/review/fixture-review"}]}"#
        case "/3/person/138":
            body = #"{"id":138,"name":"Quentin Tarantino","popularity":55,"profile_path":null}"#
        case "/3/person/popular":
            body = #"{"page":1,"total_pages":1,"results":[{"id":525,"name":"Christopher Nolan","known_for_department":"Directing","popularity":85},{"id":1032,"name":"Martin Scorsese","known_for_department":"Directing","popularity":72},{"id":488,"name":"Steven Spielberg","known_for_department":"Directing","popularity":64},{"id":608,"name":"Hayao Miyazaki","known_for_department":"Directing","popularity":58}]}"#
        case "/sparql":
            body = #"{"results":{"bindings":[{"imdb":{"value":"tt1234567"},"filmLabel":{"value":"Recorded winner (UI fixture)"},"date":{"value":"2024-01-26T00:00:00Z"}}]}}"#
        default:
            if url.path.hasPrefix("/catalog/movie/top/search=") {
                let title = String(url.path.dropFirst("/catalog/movie/top/search=".count).dropLast(".json".count))
                let metas: [[String: String]] = [["id": "tt90000001", "type": "movie", "name": title, "releaseInfo": "2026"]]
                guard let data = try? JSONSerialization.data(withJSONObject: ["metas": metas]),
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
