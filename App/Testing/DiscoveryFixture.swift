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
        // A `-DISCOVERY_SCREEN name` launch argument works too, for launchers that can't set the environment.
        switch ProcessInfo.processInfo.environment["DISCOVERY_SCREEN"] ?? UserDefaults.standard.string(forKey: "DISCOVERY_SCREEN") {
        case "settings":
            SettingsView()
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
        case "recommended":
            HomeView()
                .environment(recommendationLibrary)
        case "details":
            MetaDetailView(preview: title)
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

    /// Interstellar watched, Arrival started and Inception saved: all three are recommended,
    /// but only titles the viewer doesn't know yet may appear.
    private static let recommendationLibrary: LibraryStore = {
        let suite = "loge.discovery-recommendation-fixture"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let library = LibraryStore(defaults: defaults)
        library.markWatched([WatchItem(id: title.id, type: title.type, metaID: title.id, title: title.name)])
        library.toggleSaved(MetaPreview(id: "tt1375666", type: "movie", name: "Inception",
                                        poster: "https://image.tmdb.org/t/p/w500/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg"))
        library.record(WatchItem(id: "tt2543164", type: "movie", metaID: "tt2543164", title: "Arrival",
                                 background: "https://image.tmdb.org/t/p/w1280/8MUZz7oPXQftFTslZpRP3CVMOoq.jpg"),
                       position: 2_900, duration: 6_960)
        return library
    }()

    /// Interstellar's recommendations as TMDB lists them, with their real artwork paths.
    nonisolated static let recommended: [(tmdbID: Int, imdbID: String, title: String, date: String,
                                          poster: String, backdrop: String)] = [
        (27205, "tt1375666", "Inception", "2010-07-15", "/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg"),
        (1124, "tt0482571", "The Prestige", "2006-10-17", "/Ag2B2KHKQPukjH7WutmgnnSNurZ.jpg", "/yaExZh6qE2cfyK3o4kAMEq0mkgy.jpg"),
        (329865, "tt2543164", "Arrival", "2016-11-10", "/4gUgPIhPBoamMdbvqHyjMmb2K60.jpg", "/8MUZz7oPXQftFTslZpRP3CVMOoq.jpg"),
        (286217, "tt3659388", "The Martian", "2015-09-30", "/5BHuvQ6p9kfc091Z8RiFNhCwL4b.jpg", "/lzMS0CI3FLQYC5EgJoWeIaEt0lm.jpg"),
        (62, "tt0062622", "2001: A Space Odyssey", "1968-04-02", "/ve72VxNqjGM69Uky4WTo2bK6rfq.jpg", "/w5IDXtifKntw0ajv2co7jFlTQDM.jpg"),
        (335984, "tt1856101", "Blade Runner 2049", "2017-10-04", "/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg", "/gNdLJU9TxrpGx4dkZidjys3fyy0.jpg"),
        (155, "tt0468569", "The Dark Knight", "2008-07-16", "/qJ2tW6WMUDux911r6m7haRef0WH.jpg", "/cfT29Im5VDvjE0RpyKOSdCKZal7.jpg"),
    ]

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
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch url.path {
        case "/3/person/525":
            body = #"""
                {
                  "id": 525,
                  "name": "Christopher Nolan",
                  "known_for_department": "Directing",
                  "biography": "Director and screenwriter.",
                  "combined_credits": {
                    "cast": [
                      {
                        "id": 43654,
                        "media_type": "movie",
                        "title": "The Science of Interstellar",
                        "character": "Self",
                        "release_date": "2014-11-25"
                      }
                    ],
                    "crew": [
                      {
                        "id": 157336,
                        "media_type": "movie",
                        "title": "Interstellar",
                        "job": "Director",
                        "release_date": "2014-11-05"
                      },
                      {
                        "id": 27205,
                        "media_type": "movie",
                        "title": "Inception",
                        "job": "Director",
                        "release_date": "2010-07-15"
                      },
                      {
                        "id": 49026,
                        "media_type": "movie",
                        "title": "The Dark Knight Rises",
                        "job": "Producer",
                        "release_date": "2012-07-16"
                      }
                    ]
                  }
                }
                """#
        case "/3/find/tt0816692": body = #"{"movie_results":[{"id":157336}],"tv_results":[]}"#
        case "/3/movie/157336":
            let results = DiscoveryFixture.recommended.map {
                #"{"id":\#($0.tmdbID),"title":"\#($0.title)","release_date":"\#($0.date)","#
                    + #""poster_path":"\#($0.poster)","backdrop_path":"\#($0.backdrop)"}"#
            }
            body = #"""
                {"id":157336,"title":"Interstellar","release_date":"2014-11-05","runtime":169,
                 "poster_path":"/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg","backdrop_path":"/8sNiAPPYU14PUepFNeSNGUTiHW.jpg",
                 "recommendations":{"results":[\#(results.joined(separator: ","))]}}
                """#
        case let path where path.hasPrefix("/3/movie/") && path.hasSuffix("/external_ids"):
            let id = url.pathComponents[3]
            let imdbID = DiscoveryFixture.recommended.first { String($0.tmdbID) == id }?.imdbID
            body = #"{"id":\#(id),"imdb_id":\#(imdbID.map { "\"\($0)\"" } ?? "null")}"#
        case "/3/movie/157336/reviews":
            body = #"""
                {
                  "id": 157336,
                  "page": 1,
                  "total_pages": 1,
                  "total_results": 3,
                  "results": [
                    {
                      "id": "fixture-review",
                      "author": "Film viewer",
                      "author_details": {
                        "rating": 8
                      },
                      "content": "A patient, ambitious journey that gives its enormous images a human scale. The quiet scenes between Cooper and Murph are what stayed with me.\n\nThe ending invites discussion, but the film earns its sense of wonder. This text was written for the offline UI test.",
                      "created_at": "2026-01-15T12:00:00Z",
                      "url": "https://www.themoviedb.org/review/fixture-review"
                    },
                    {
                      "id": "fixture-review-2",
                      "author": "Second viewer",
                      "author_details": {
                        "rating": 6
                      },
                      "content": "Long, loud and sentimental, though the docking sequence alone is worth it. This text was written for the offline UI test.",
                      "created_at": "2026-01-16T12:00:00Z",
                      "url": "https://www.themoviedb.org/review/fixture-review-2"
                    },
                    {
                      "id": "fixture-review-3",
                      "author": "Third viewer",
                      "author_details": {
                        "rating": 9
                      },
                      "content": "Only listed behind All reviews. This text was written for the offline UI test.",
                      "created_at": "2026-01-17T12:00:00Z",
                      "url": "https://www.themoviedb.org/review/fixture-review-3"
                    }
                  ]
                }
                """#
        case "/3/person/138":
            body = #"{"id":138,"name":"Quentin Tarantino","popularity":55,"profile_path":null}"#
        case "/3/person/popular":
            body = #"""
                {
                  "page": 1,
                  "total_pages": 1,
                  "results": [
                    {
                      "id": 525,
                      "name": "Christopher Nolan",
                      "known_for_department": "Directing",
                      "popularity": 85
                    },
                    {
                      "id": 1032,
                      "name": "Martin Scorsese",
                      "known_for_department": "Directing",
                      "popularity": 72
                    },
                    {
                      "id": 488,
                      "name": "Steven Spielberg",
                      "known_for_department": "Directing",
                      "popularity": 64
                    },
                    {
                      "id": 608,
                      "name": "Hayao Miyazaki",
                      "known_for_department": "Directing",
                      "popularity": 58
                    }
                  ]
                }
                """#
        case "/sparql":
            body = #"""
                {
                  "results": {
                    "bindings": [
                      {
                        "imdb": {
                          "value": "tt1234567"
                        },
                        "filmLabel": {
                          "value": "Recorded winner (UI fixture)"
                        },
                        "date": {
                          "value": "2024-01-26T00:00:00Z"
                        }
                      }
                    ]
                  }
                }
                """#
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
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
