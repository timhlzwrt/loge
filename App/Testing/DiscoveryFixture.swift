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

    static var screenName: String? {
        ProcessInfo.processInfo.environment["DISCOVERY_SCREEN"] ?? UserDefaults.standard.string(forKey: "DISCOVERY_SCREEN")
    }

    @ViewBuilder
    static var screen: some View {
        // A `-DISCOVERY_SCREEN name` launch argument works too, for launchers that can't set the environment.
        switch screenName {
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
        case "series":
            MetaDetailView(preview: MetaPreview(id: "tt0903747", type: "series", name: "Breaking Bad"))
        // TMDB has no match for this title, and TMDB is rate limiting for the next.
        case "details-unmatched":
            MetaDetailView(preview: MetaPreview(id: "tt0062622", type: "movie", name: "2001: A Space Odyssey"))
        case "details-busy":
            MetaDetailView(preview: MetaPreview(id: "tt2543164", type: "movie", name: "Arrival"))
        case "person":
            PersonView(route: PersonRoute(person: Person(name: "Christopher Nolan", roles: [.director], tmdbID: 525)))
        case "festival":
            FilmCollectionView(collection: .sundance, client: FilmCollectionClient(session: session))
        // Sources from `Tools/test-addon.py --port 8769 --many --delay 5`: twelve 1080p rows that
        // fold, and while they're awaited, autoplay waiting for a remembered source they don't list.
        case "sources-folded", "sources-autoplay", "sources-empty", "sources-empty-sheet":
            SourcesFixture(screen: screenName ?? "")
        // States that need a sync server or a Trakt account, in stores kept apart from the app's.
        case "settings-review", "settings-failed":
            SettingsView().accountFixture()
        case "trakt-signin", "trakt-keys":
            SettingsPage("Trakt") { TraktSection() }.accountFixture()
        // The first featured series, started at S2, E3: its carousel page says where Play resumes.
        case "carousel-resume":
            CarouselResumeFixture()
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

    /// Interstellar's top-billed cast as TMDB lists it, with real portrait paths; TMDB has
    /// no photo for some of the smaller parts, and its full list runs to dozens of extras.
    nonisolated static let cast: [(id: Int, name: String, character: String, profile: String?)] = [
        (10297, "Matthew McConaughey", "Cooper", "/lCySuYjhXix3FzQdS4oceDDrXKI.jpg"),
        (1813, "Anne Hathaway", "Brand", "/s6tflSD20MGz04ZR2R1lZvhmC4Y.jpg"),
        (3895, "Michael Caine", "Professor Brand", "/bVZRMlpjTAO2pJK6v90buFgVbSW.jpg"),
        (83002, "Jessica Chastain", "Murph", "/mR1ELpP0T2Q1ZRSaADPgtrbPGla.jpg"),
        (1893, "Casey Affleck", "Tom", "/304ilSygaCRWykoBWAL67TOw8g9.jpg"),
        (8210, "Wes Bentley", "Doyle", "/voD93lzFZrr9xfAggwFcPRBi84i.jpg"),
        (17052, "Topher Grace", "Getty", "/89sF57Br5lq8nrepS7HLzJ41QD1.jpg"),
        (851784, "Mackenzie Foy", "Murph (10 Yrs.)", "/ga2HkX7gBjjXooegTu9cLgXy9nE.jpg"),
        (9560, "Ellen Burstyn", "Murph (older)", "/zGihSIVRzwmCqilnA4PmNM4C2RT.jpg"),
        (12074, "John Lithgow", "Donald", "/ajfuBSm1HuVqFJlbTmAlza62Xxr.jpg"),
        (58549, "Bill Irwin", "TARS (voice)", "/bAV5qsljgiHQkn3QluB5clVYC13.jpg"),
        (55411, "David Gyasi", "Romilly", "/1382u2e4jiGhuDKgeK9UZtXXqfh.jpg"),
        (1190668, "Timothée Chalamet", "Tom (15 Yrs.)", "/dFxpwRpmzpVfP1zjluH68DeQhyj.jpg"),
        (1892, "Matt Damon", "Mann", "/aCvBXTAR9B1qRjIRzMBYhhbm1fR.jpg"),
        (40039, "Josh Stewart", "CASE (voice)", "/prgoT9fq5Z2ZCGmC1rrSZkq4wH9.jpg"),
        (32202, "Leah Cairns", "Lois", "/pdPcPWuPcheSRPwJFmnMI66XTn5.jpg"),
        (1452481, "Liam Dickinson", "Coop", "/4qXWvTQ2dC4369FnV4Ac2JoYk3p.jpg"),
        (100650, "Francis X. McCarthy", "Boots", "/4DyZhRmxGrwhr2UNc1CTZHdvZ0R.jpg"),
        (21416, "William Devane", "Williams", "/wCfPYMkAOCXM4RF1Pg6VhtKR50U.jpg"),
        (167720, "Andrew Borba", "Smith", "/nCrQGvvugig0vfOCgnmFkMKvTOL.jpg"),
        (78050, "Elyes Gabel", "Administrator", "/z9IqYTYxhVR9ADxaksbPQwiYQns.jpg"),
        (35013, "David Oyelowo", "School Principal", "/7UZHRwOKe2cYxj8SeNUklyPYkns.jpg"),
        (86624, "Collette Wolfe", "Ms. Hanley", "/cyX7HFrY1YYgXXrveGlaFGAAmKn.jpg"),
        (2142337, "Griffen Fraser", "Boy on Truck", nil),
        (1573547, "Kristian Van der Heyden", "Scientist (uncredited)", "/59HMcKb4BiO5gI52LPmpYZTkpw3.jpg"),
        (1452865, "William Patrick Brown", "NASA Employee (uncredited)", nil),
        (1663832, "Alexander Michael Helisek", "Construction Boss (uncredited)", "/nxf8iwz1ODRQMcTbZE86amTTTG5.jpg"),
        (1360008, "Joseph Oliveira", "Astronaut (uncredited)", nil),
        (2142494, "Emily Kwong", "Hospital Worker (uncredited)", nil),
        (1447570, "Joel Tobman", "Grain Farmer (uncredited)", nil),
    ]

    /// Nine member reviews over two pages, shaped like TMDB's: long Markdown with blank lines,
    /// HTML breaks, a link, a missing rating and a long user name.
    nonisolated static func reviews(page: Int) -> String {
        let entries: [(id: String, author: String, rating: String, content: String)] = page == 1 ? [
            ("fixture-review", "Film viewer", "8",
             "A patient, ambitious journey that gives its enormous images a human scale. The quiet scenes between Cooper and Murph are what stayed with me.\\n\\nThe ending invites discussion, but the film earns its sense of wonder. It asks for patience in its first hour, with the farm, the dust and the school meeting about the moon landings, and it pays that patience back once the ship leaves. I would have cut a few of the explanations shouted across the cockpit, and the organ is loud enough to rattle the seats, but neither stopped me from going back to see it again the following week. On the second visit I watched the people around me more than the screen, and nobody reached for a phone during the last hour, which says more than I can. This text was written for the offline UI test."),
            ("fixture-review-2", "Second viewer", "6",
             "Long, loud and sentimental, though the docking sequence alone is worth it. This text was written for the offline UI test."),
            ("fixture-review-3", "Third viewer", "9",
             "Only listed behind All reviews. This text was written for the offline UI test."),
            ("fixture-review-4", "cinephile_from_the_back_row_1987", "null",
             "**Spoilers below.**<br><br>I went in expecting a space film and came out having watched a film about a father who keeps missing his daughter's life, one video message at a time. The Miller's planet sequence is the clearest example: an hour there costs seven years back home, and the film lets you feel each of them when Cooper sits down in front of the screen.\\n\\nThe score does a lot of the work, sometimes too much; in the dust-storm scenes it drowns out dialogue I'd have liked to hear. The science has been argued over [at length](https://www.themoviedb.org/movie/157336), and I'm not the one to settle it.\\n\\nWhat I keep coming back to is how physical it all is: the corn, the dust on the plates, the robots that look like slabs of metal and turn out to be the funniest characters in it.\\n\\nThe docking scene deserves its reputation. There's no music for the first few seconds, only the sound inside the cabin, and then the organ comes in as the ship starts to spin. I've seen people in the row in front of me lean with it. It's the rare blockbuster set piece where you understand exactly what's at stake and exactly what has to happen, and the film doesn't cut away to explain it.\\n\\nThe bookshelf is where people split. I think it works because the film has been setting it up from the first scene, with the books falling and the dust on the floor; others find it too neat. Either way, it's the emotional point the whole film was heading for, and McConaughey plays it as a man who has run out of other options.\\n\\nOn a second viewing the first hour plays better than I remembered. Knowing where it goes, the scenes on the farm read as goodbyes, and the baseball game with the dust storm coming in over the field is one of the best things in it.\\n\\nIf you can, see it on the largest screen near you. The IMAX sequences were shot for it, and on a television the black bars come and go as the aspect ratio changes, which takes some getting used to.\\n\\nOne more thing, for anyone who hasn't seen it yet: go in knowing as little as you can. The trailers give away more than they should, and the film works best when the third act arrives without warning. It's long, and I'd still sit through all of it again tomorrow. This text was written for the offline UI test."),
            ("fixture-review-5", "Ana", "7",
             "Beautiful and a bit too long. This text was written for the offline UI test."),
            ("fixture-review-6", "Rewatcher", "10",
             "Third time in a cinema and it still works. This text was written for the offline UI test."),
        ] : [
            ("fixture-review-7", "Late reader", "5", "Page two, loaded by More reviews. This text was written for the offline UI test."),
            ("fixture-review-8", "Weekend viewer", "8", "Page two again. This text was written for the offline UI test."),
            ("fixture-review-9", "Last one", "null", "The last review in the fixture. This text was written for the offline UI test."),
        ]
        return entries.map {
            #"{"id":"\#($0.id)","author":"\#($0.author)","author_details":{"rating":\#($0.rating)},"content":"\#($0.content)","#
                + #""created_at":"2026-01-15T12:00:00Z","url":"https://www.themoviedb.org/review/\#($0.id)"}"#
        }.joined(separator: ",")
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

private struct SourcesFixture: View {
    let screen: String
    @State private var addons: AddonStore?
    @State private var library: LibraryStore?
    private static let addon = "http://127.0.0.1:8769/manifest.json"
    private let item = WatchItem(id: "tt0816692", type: "movie", metaID: "tt0816692", title: "Interstellar")

    var body: some View {
        Group {
            if let addons, let library {
                let route = SourcesRoute(item: item, title: "Interstellar", autoplay: screen == "sources-autoplay")
                if screen == "sources-empty-sheet" {
                    Color.canvas.sheet(isPresented: .constant(true)) { SourcesView(route: route, isChoosing: true) }
                        .environment(addons).environment(library)
                } else {
                    SourcesView(route: route).environment(addons).environment(library)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            let suite = "loge.sources-fixture"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let addons = AddonStore(defaults: defaults)
            let library = LibraryStore(defaults: defaults)
            if !screen.hasPrefix("sources-empty") {
                do { try await addons.install(manifestURL: Self.addon) } catch {
                    print("Sources fixture: start Tools/test-addon.py --port 8769 --many --delay 5 (\(error))")
                }
            }
            if screen == "sources-autoplay", let url = URL(string: "http://127.0.0.1:8769/gone.mkv") {
                library.rememberSource(RememberedSource(itemID: item.id, providerURL: Self.addon, url: url,
                                                        headers: [:], bingeGroup: "gone"), metaID: item.metaID)
            }
            self.addons = addons
            self.library = library
        }
    }
}

private struct CarouselResumeFixture: View {
    @State private var library: LibraryStore?

    var body: some View {
        Group {
            if let library { HomeView().environment(library) } else { ProgressView() }
        }
        .task {
            let suite = "loge.carousel-resume-fixture"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let library = LibraryStore(defaults: defaults)
            let catalogs = DiscoveryCatalogs.home
            if let movies = try? await catalogs[0].items(), let series = try? await catalogs[1].items(),
               let first = DiscoveryCatalogs.featured(movies: movies, series: series).first(where: { $0.type == "series" }) {
                library.record(WatchItem(id: "\(first.id):2:3", type: "series", metaID: first.id, title: first.name,
                                         season: 2, episode: 3), position: 600, duration: 2400)
            }
            self.library = library
        }
    }
}

private extension View {
    func accountFixture() -> some View {
        let stores = DiscoveryFixture.accountStores
        return environment(stores.addons).environment(stores.library).environment(stores.sync).environment(stores.trakt)
    }
}

extension DiscoveryFixture {
    /// One account state: a review pending with Trakt paused by the account, a failed sync
    /// beside a Trakt sign-in in progress, the sign-in code alone, or saved keys before signing in.
    static let accountStores: (addons: AddonStore, library: LibraryStore, sync: AccountSync, trakt: TraktAccount) = {
        let suite = "loge.account-states-fixture"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let addons = AddonStore(defaults: defaults)
        let library = LibraryStore(defaults: defaults)
        let sync = AccountSync(addons: addons, library: library, defaults: defaults, temporaryConnection: true)
        let trakt: TraktAccount
        if screenName == "settings-review" {
            sync.showForTesting(status: .choosingInitialSetup, needsChoice: true)
            // An account's library is active, which is what pauses Trakt.
            library.activateProfile(id: "ui-fixture")
            trakt = TraktAccount(library: library, addons: addons, defaults: defaults, showing: .signedIn(username: "ui-fixture"))
        } else {
            if screenName == "settings-failed" { sync.showForTesting(status: .failed, needsChoice: false) }
            trakt = TraktAccount(library: library, addons: addons, defaults: defaults,
                                 showing: screenName == "trakt-keys" ? .signedOut : .awaitingApproval(.uiFixture))
        }
        return (addons, library, sync, trakt)
    }()
}

private final class DiscoveryFixtureProtocol: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        var status = 200
        switch url.path {
        case "/3/person/525":
            let directed: [(Int, String, String, String?)] = [
                (157336, "Interstellar", "2014-11-05", "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg"),
                (27205, "Inception", "2010-07-15", "/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg"),
                (155, "The Dark Knight", "2008-07-16", "/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
                (1124, "The Prestige", "2006-10-17", "/Ag2B2KHKQPukjH7WutmgnnSNurZ.jpg"),
                (272, "Batman Begins", "2005-06-10", "/b3UIToGx8JIpRqUTGkaoyaNLuU3.jpg"),
                (374720, "Dunkirk", "2017-07-19", "/pcVC6wvEVodaUxkTsUkXlgVrXHF.jpg"),
                (77, "Memento", "2000-10-11", "/qaXfDrZCdd3wix2XYor5HDDpFrT.jpg"),
                (1368337, "The Odyssey", "2026-07-16", nil),
                (11660, "Following", "1998-09-12", nil),
            ]
            let credits = directed.map { #"{"id":\#($0.0),"media_type":"movie","title":"\#($0.1)","job":"Director","release_date":"\#($0.2)","poster_path":\#($0.3.map { "\"\($0)\"" } ?? "null")}"# }
            body = #"""
                {
                  "id": 525,
                  "name": "Christopher Nolan",
                  "known_for_department": "Directing",
                  "birthday": "1970-07-30",
                  "place_of_birth": "Westminster, London, England, UK",
                  "profile_path": "/xuAIuYSmsUzKlUMBFGVZaWsY3DZ.jpg",
                  "biography": "Director and screenwriter. This biography is long on purpose, for the offline UI test: it has to run across several lines to show how wide the text gets and how many lines stay visible before Read Biography. A real TMDB biography usually covers early life, the first short films, the breakthrough feature and the later studio work, which makes it one of the longest pieces of text in the app. It keeps going here for the same reason, so that the fifth line is still cut short and the limit can be seen on every screen size this fixture runs on.\n\nA second paragraph, as TMDB biographies often have one: it covers the awards, the production company and the frequent collaborators, and only shows once the biography is opened.",
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
                      \#(credits.joined(separator: ",\n")),
                      {
                        "id": 49026,
                        "media_type": "movie",
                        "title": "The Dark Knight Rises",
                        "job": "Director",
                        "release_date": "2012-07-16",
                        "poster_path": "/9NyCuhyvFKTqGRLcr4r8fWXnu9v.jpg"
                      },
                      {
                        "id": 49026,
                        "media_type": "movie",
                        "title": "The Dark Knight Rises",
                        "job": "Producer",
                        "release_date": "2012-07-16"
                      },
                      {
                        "id": 1426,
                        "media_type": "tv",
                        "name": "Westworld",
                        "job": "Executive Producer",
                        "first_air_date": "2016-10-02"
                      }
                    ]
                  }
                }
                """#
        case "/3/find/tt0816692": body = #"{"movie_results":[{"id":157336}],"tv_results":[]}"#
        case "/3/find/tt0903747": body = #"{"movie_results":[],"tv_results":[{"id":1396}]}"#
        case "/3/find/tt0062622": body = #"{"movie_results":[],"tv_results":[]}"#
        case "/3/find/tt2543164":
            status = 429
            body = #"{"status_code":25,"status_message":"Your request count is over the allowed limit."}"#
        case "/3/movie/157336":
            let results = DiscoveryFixture.recommended.map {
                #"{"id":\#($0.tmdbID),"title":"\#($0.title)","release_date":"\#($0.date)","#
                    + #""poster_path":"\#($0.poster)","backdrop_path":"\#($0.backdrop)"}"#
            }
            let cast = DiscoveryFixture.cast.map {
                #"{"id":\#($0.id),"name":"\#($0.name)","character":"\#($0.character)","profile_path":\#($0.profile.map { "\"\($0)\"" } ?? "null")}"#
            }
            body = #"""
                {"id":157336,"title":"Interstellar","original_title":"Interstellar","release_date":"2014-11-05","runtime":169,
                 "tagline":"Mankind was born on Earth. It was never meant to die here.","status":"Released",
                 "original_language":"en","vote_average":8.5,"vote_count":38214,"budget":165000000,"revenue":746606706,
                 "genres":[{"name":"Adventure"},{"name":"Drama"},{"name":"Science Fiction"}],
                 "production_countries":[{"iso_3166_1":"GB","name":"United Kingdom"},{"iso_3166_1":"US","name":"United States of America"}],
                 "production_companies":[{"name":"Legendary Pictures"},{"name":"Syncopy"},{"name":"Lynda Obst Productions"}],
                 "poster_path":"/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg","backdrop_path":"/8sNiAPPYU14PUepFNeSNGUTiHW.jpg",
                 "credits":{"cast":[\#(cast.joined(separator: ","))],
                            "crew":[{"id":525,"name":"Christopher Nolan","department":"Directing","job":"Director","profile_path":"/xuAIuYSmsUzKlUMBFGVZaWsY3DZ.jpg"},
                                    {"id":525,"name":"Christopher Nolan","department":"Writing","job":"Writer","profile_path":"/xuAIuYSmsUzKlUMBFGVZaWsY3DZ.jpg"},
                                    {"id":527,"name":"Jonathan Nolan","department":"Writing","job":"Writer","profile_path":"/qgTOwfg2B4C0ZFGAP4EnRZ7domo.jpg"},
                                    {"id":74401,"name":"Hoyte van Hoytema","department":"Camera","job":"Director of Photography","profile_path":"/y2HXvac1oPzciwxfdyWc5syThRk.jpg"},
                                    {"id":947,"name":"Hans Zimmer","department":"Sound","job":"Original Music Composer","profile_path":"/tpQnDeHY15szIXvpnhlprufz4d.jpg"}]},
                 "recommendations":{"results":[\#(results.joined(separator: ","))]}}
                """#
        case "/3/tv/1396":
            let cast = [
                (17419, "Bryan Cranston", "Walter White", "/7Jahy5LZX2Fo8fGJltMreAI49hC.jpg"),
                (84497, "Aaron Paul", "Jesse Pinkman", "/8Ac9uuoYwZoYVAIJfRLzzLsGGJn.jpg"),
                (134531, "Anna Gunn", "Skyler White", "/adppyeu1a4REN3khtgmXusrapFi.jpg"),
                (209674, "RJ Mitte", "Walter White Jr.", "/sNPA92ZrssYhlaB1UA2pWcLD9db.jpg"),
                (14329, "Dean Norris", "Hank Schrader", "/mKRrEbsxAX3ro700HsViFArRM7l.jpg"),
                (1217934, "Betsy Brandt", "Marie Schrader", "/xAnuzyjdMbQq9L1c4JNwXL52Wm4.jpg"),
                (59410, "Bob Odenkirk", "Saul Goodman", "/rF0Lb6SBhGSTvjRffmlKRSeI3jE.jpg"),
                (783, "Jonathan Banks", "Mike Ehrmantraut", "/lIZZPQLEstz7DkETN4Q9fHp7jjV.jpg"),
                (61535, "Steven Michael Quezada", "Steven Gomez", "/pVYrDkwI6GWvCNL2kJhpDJfBFyd.jpg"),
                (4808, "Giancarlo Esposito", "Gustavo Fring", "/MJOo4QZgMAb3y8QzOUDVFQusQZ.jpg"),
            ].map { #"{"id":\#($0.0),"name":"\#($0.1)","character":"\#($0.2)","profile_path":"\#($0.3)"}"# }
            let results = [
                (60059, "Better Call Saul", "2015-02-08", "/fC2HDm5t0kHl7mTm7jxMR31b7by.jpg", "/rfxryDIv8huejujg4JueDJx8zCz.jpg"),
                (1398, "The Sopranos", "1999-01-10", "/rTc7ZXdroqjkKivFPvCPX0Ru7uw.jpg", "/lNpkvX2s8LGB0mjGODMT4o6Up7j.jpg"),
                (69740, "Ozark", "2017-07-21", "/pCGyPVrI9Fzw6rE1Pvi4BIXF6ET.jpg", "/aatG9iVAUL7U7OyFEmupESpOrD2.jpg"),
                (1438, "The Wire", "2002-06-02", "/4lbclFySvugI51fwsyxBTOm4DqK.jpg", "/aQTtua5pG490fMfeKgtYg5B853e.jpg"),
                (63351, "Narcos", "2015-08-28", "/rTmal9fDbwh5F0waol2hq35U4ah.jpg", "/y9ekzkPFmWSqUU3Kj0wHmYUM8qu.jpg"),
                (46648, "True Detective", "2014-01-12", "/cuV2O5ZyDLHSOWzg3nLVljp1ubw.jpg", "/v8YFr8BbU9qsO8PYIulzTeM6Qk.jpg"),
            ].map {
                #"{"id":\#($0.0),"name":"\#($0.1)","first_air_date":"\#($0.2)","poster_path":"\#($0.3)","backdrop_path":"\#($0.4)"}"#
            }
            body = #"""
                {"id":1396,"name":"Breaking Bad","original_name":"Breaking Bad","first_air_date":"2008-01-20","last_air_date":"2013-09-29",
                 "episode_run_time":[45,47],"status":"Ended","original_language":"en","number_of_seasons":5,"number_of_episodes":62,
                 "vote_average":8.9,"vote_count":16890,"origin_country":["US"],
                 "tagline":"Change the equation.",
                 "genres":[{"name":"Drama"},{"name":"Crime"}],
                 "production_companies":[{"name":"Sony Pictures Television Studios"},{"name":"High Bridge Productions"},{"name":"Gran Via Productions"}],
                 "poster_path":"/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg","backdrop_path":"/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
                 "credits":{"cast":[\#(cast.joined(separator: ","))],"crew":[]},
                 "recommendations":{"results":[\#(results.joined(separator: ","))]}}
                """#
        case "/3/tv/1396/reviews":
            body = #"{"id":1396,"page":1,"total_pages":0,"total_results":0,"results":[]}"#
        case let path where path.hasPrefix("/3/movie/") && path.hasSuffix("/external_ids"):
            let id = url.pathComponents[3]
            let imdbID = DiscoveryFixture.recommended.first { String($0.tmdbID) == id }?.imdbID
            body = #"{"id":\#(id),"imdb_id":\#(imdbID.map { "\"\($0)\"" } ?? "null")}"#
        case "/3/movie/157336/reviews":
            let page = url.query?.contains("page=2") == true ? 2 : 1
            body = #"{"id":157336,"page":\#(page),"total_pages":2,"total_results":9,"results":[\#(DiscoveryFixture.reviews(page: page))]}"#
        case "/3/person/138":
            body = #"{"id":138,"name":"Quentin Tarantino","popularity":55,"profile_path":"/1gjcpAa99FAOWGnrUvHEXXsRs7o.jpg"}"#
        case "/3/person/popular":
            let people: [(Int, String, Double, String?)] = [
                (525, "Christopher Nolan", 85, "/xuAIuYSmsUzKlUMBFGVZaWsY3DZ.jpg"),
                (137427, "Denis Villeneuve", 78, "/xzQYqb4nR8xT7Zdw5itbEL9K3fd.jpg"),
                (1032, "Martin Scorsese", 72, "/g3DjfKsgZQWZiw30I20hZVk1oMX.jpg"),
                (45400, "Greta Gerwig", 69, "/dxKAhpkz4XNwmRzMG5QOpXjPZ1N.jpg"),
                (488, "Steven Spielberg", 64, "/tZxcg19YQ3e8fJ0pOs7hjlnmmr6.jpg"),
                (21684, "Bong Joon-ho", 61, "/stwnTvZAoD8gEJEDHpDQyLCyDy5.jpg"),
                (608, "Hayao Miyazaki", 58, "/ouhjt9KugzhWtdEyBPipihB3ic8.jpg"),
                (69759, "Apichatpong Weerasethakul", 21, nil),
            ]
            let results = people.map {
                #"{"id":\#($0.0),"name":"\#($0.1)","known_for_department":"Directing","popularity":\#($0.2),"profile_path":\#($0.3.map { "\"\($0)\"" } ?? "null")}"#
            }
            body = #"{"page":1,"total_pages":1,"results":[\#(results.joined(separator: ","))]}"#
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
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
