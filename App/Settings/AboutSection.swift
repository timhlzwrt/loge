import LogeCore
import SwiftUI

struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: version)
            LabeledContent("Development", value: "Tim Holzwarth")
            LabeledContent("Testing", value: "Lenja")
            NavigationLink("Data Sources") { DataSourcesView() }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// Where titles, artwork and timings come from. Kept here rather than under every
/// picture and list, which once carried their own source lines.
struct DataSourcesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image("TMDBLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 16)
                        .foregroundStyle(.white)
                        .accessibilityLabel("TMDB")
                    Text("Details, cast and crew, filmographies and portraits, once connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #if !os(tvOS)
                    Link("themoviedb.org", destination: URL(string: "https://www.themoviedb.org")!)
                        .font(.footnote)
                    #endif
                }
                .padding(.vertical, 8)
            }

            Section("Titles") {
                source("Cinemeta", "Catalogs, search, title details, artwork and IMDb ratings.",
                       url: "https://www.stremio.com")
                source("Letterboxd via Stremboxd", "Popular and all-time lists on Home and in genres.",
                       url: "https://letterboxd.com")
                source("Wikidata", "Festival winners and directors’ films. Records may be incomplete.",
                       url: "https://www.wikidata.org")
            }

            Section("Playback") {
                source("TheIntroDB", "Intro, recap and credits timings for the skip buttons.",
                       url: "https://theintrodb.org")
                source("Trakt", "Watch progress and history, when signed in.",
                       url: "https://trakt.tv")
                Text("Streams and subtitles come from the addons you install.")
                    .foregroundStyle(.secondary)
            }

            Section("Images") {
                ForEach(FilmCollection.allCases) { collection in
                    // The licences of the cropped portraits ask for the change to be noted.
                    let credit = collection.isFestival
                        ? collection.artworkCredit
                        : "Photo: \(collection.artworkCredit) · Cropped"
                    source(collection.name, credit, url: collection.artworkCreditURL.absoluteString)
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.canvas)
        .navigationTitle("Data Sources")
    }

    @ViewBuilder
    private func source(_ name: String, _ detail: String, url: String) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            Text(name).foregroundStyle(.primary)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
        // tvOS can't open web links, and plain rows can't take focus to scroll; a button can.
        Button {} label: { label }
        #else
        Link(destination: URL(string: url)!) { label }
        #endif
    }
}
