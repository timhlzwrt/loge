import LogeCore
import SwiftUI

struct AboutSection: View {
    private let build = BuildInfo()
    #if os(macOS)
    @EnvironmentObject private var appUpdater: AppUpdater
    #endif

    var body: some View {
        Section {
            LabeledContent("Version", value: version)
            #if os(macOS)
            Button("Check for Updates…", action: appUpdater.checkForUpdates)
                .disabled(!appUpdater.canCheckForUpdates)
            Toggle("Automatically check for updates", isOn: $appUpdater.automaticallyChecksForUpdates)
            #endif
            if let commit = build.commit {
                LabeledContent("Build", value: build.summary)
                if let branch = build.branch {
                    LabeledContent("Branch", value: branch)
                }
                #if !os(tvOS)
                // GitHub answers "identical" when this is main's latest, or lists the commits it's missing.
                Link("Compare with main on GitHub",
                     destination: URL(string: "https://github.com/timhlzwrt/loge/compare/\(commit)...main")!)
                #endif
            }
            LabeledContent("Development", value: "Tim Holzwarth")
            LabeledContent("Testing", value: "Lenja")
            NavigationLink("Data Sources") { DataSourcesView() }
        } header: { SettingsHeader("About") }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// The commit a build was made from, stamped into Info.plist by the "Stamp commit" build phase.
private struct BuildInfo {
    let commit: String?
    let date: Date?
    /// Nil on main, and for the detached checkout the install script builds in.
    let branch: String?
    let isModified: Bool

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        commit = info["LogeCommit"] as? String
        date = (info["LogeCommitDate"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        branch = (info["LogeBranch"] as? String).flatMap { ["main", "HEAD"].contains($0) ? nil : $0 }
        isModified = info["LogeModified"] as? Bool ?? false
    }

    /// "a87f81f · Nov 3, 2026, 16:39", with "· modified" when built with uncommitted changes.
    var summary: String {
        [commit.map { String($0.prefix(7)) },
         date.map { "\($0.formatted(.dateTime.day().month(.abbreviated).year().locale(.interface))), "
             + $0.formatted(date: .omitted, time: .shortened) },
         isModified ? "modified" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Where titles, artwork and timings come from. Kept here rather than under every
/// picture and list, which once carried their own source lines.
struct DataSourcesView: View {
    @State private var editions: [FestivalEdition] = []
    @State private var festivalSourceFailure = false
    var body: some View {
        SettingsPage("Data Sources") {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image("TMDBLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 16)
                        .foregroundStyle(.white)
                        .accessibilityLabel("TMDB")
                    Text("Details, filmographies, portraits, popular directors and member reviews, once connected.")
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

            Section {
                source("Cinemeta", "Catalogs, search, title details, artwork and IMDb ratings.",
                       url: "https://www.stremio.com")
                source("MDBList", "Letterboxd and Rotten Tomatoes scores on a title's page, once connected.",
                       url: "https://mdblist.com")
                source("Letterboxd via Stremboxd", "Popular and all-time lists on Home and in genres.",
                       url: "https://letterboxd.com")
                source("Wikidata", "Recorded historical festival winners and selected directors’ films. Records may be incomplete.",
                       url: "https://www.wikidata.org")
            } header: { SettingsHeader("Titles") }

            Section {
                ForEach(editions, id: \.festival) { edition in
                    ForEach(edition.sources, id: \.absoluteString) { url in
                        source("\(edition.festival.name) · \(url.host() ?? "Source")",
                               "\(edition.coverage) Checked \(edition.checkedOn).", url: url.absoluteString)
                    }
                }
                if festivalSourceFailure {
                    Text("The bundled festival source list couldn't be read.")
                        .foregroundStyle(.secondary)
                }
            } header: { SettingsHeader("2026 Festival Awards") }

            Section {
                source("TheIntroDB", "Intro, recap and credits timings for the skip buttons.",
                       url: "https://theintrodb.org")
                Text("Streams and subtitles come from the addons you install.")
                    .foregroundStyle(.secondary)
            } header: { SettingsHeader("Playback") }

            Section {
                ForEach(FilmCollection.allCases) { collection in
                    // The licences of the cropped portraits ask for the change to be noted.
                    let credit = collection.isFestival
                        ? collection.artworkCredit
                        : "Photo: \(collection.artworkCredit) · Cropped"
                    source(collection.name, credit, url: collection.artworkCreditURL.absoluteString)
                }
            } header: { SettingsHeader("Images") }
        }
        .task {
            do { editions = try FestivalEdition.all() }
            catch { festivalSourceFailure = true }
        }
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
