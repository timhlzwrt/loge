import LogeCore
import SwiftUI

struct FestivalAwardsView: View {
    let collection: FilmCollection
    let client: FilmCollectionClient
    @State private var edition: FestivalEdition?
    @State private var failed = false
    @State private var section: String?
    @State private var matches: [String: MetaPreview] = [:]
    @State private var finished = Set<String>()
    @State private var failures = Set<String>()
    @State private var attempt = 0

    private var filmWidth: CGFloat {
        #if os(macOS)
        160
        #else
        Metrics.posterWidth
        #endif
    }

    private var films: [FestivalFilm] {
        var result: [FestivalFilm] = []
        for award in edition?.awards ?? [] where award.isFilm && (section == nil || award.section == section) {
            if let index = result.firstIndex(where: { $0.title == award.title }) {
                result[index].awards.append(award)
            } else {
                result.append(FestivalFilm(title: award.title, awards: [award]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let edition {
                    HStack(alignment: .center, spacing: 24) {
                        CollectionArtwork(collection: collection)
                            .frame(width: Metrics.posterWidth * 1.4, height: Metrics.posterWidth * 0.72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(String(edition.year)) winners").font(.sectionTitle)
                            Text("\(films.count) films").font(.metaLine).foregroundStyle(.secondary)
                            NavigationLink("All awards", value: FestivalRoute.allAwards(collection))
                            .font(.metaLine)
                            .buttonStyle(.plain)
                        }
                    }
                    sectionPicker(edition)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: filmWidth), spacing: Metrics.rowSpacing,
                                                alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(films) { film in
                            NavigationLink(value: FestivalRoute.film(title: film.title, collection: collection)) {
                                FestivalFilmTile(film: film, meta: matches[film.title],
                                                 loading: !finished.contains(film.title) && !failures.contains(film.title))
                            }
                            .tileButtonStyle()
                        }
                    }
                    .accessibilityIdentifier("festival-films")
                    if !failures.isEmpty {
                        HStack {
                            Text("Some title listings couldn't load.").foregroundStyle(.secondary)
                            Button("Retry") { attempt += 1 }
                        }.font(.metaLine)
                    }
                    Divider()
                    NavigationLink("Previous recorded winners", value: FestivalRoute.recordedWinners(collection))
                    .font(.metaLine)
                } else if failed {
                    ContentUnavailableView("Award list unavailable", systemImage: "film",
                        description: Text("The bundled edition couldn't be read."))
                    NavigationLink("Recorded winners", value: FestivalRoute.recordedWinners(collection))
                } else {
                    ProgressView("Loading winners…")
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
        }
        .background(Color.canvas)
        .pageTitle(collection.name)
        .task(id: collection) {
            edition = nil
            section = nil
            matches = [:]
            finished = []
            failures = []
            failed = false
            do { edition = try FestivalEdition.edition(for: collection) }
            catch { failed = true }
        }
        .task(id: "\(collection.id):\(edition?.year ?? 0):\(attempt)") {
            guard let edition else { return }
            await loadFilms(edition)
        }
    }

    private func loadFilms(_ edition: FestivalEdition) async {
        var seen = Set<String>()
        let pending = edition.awards.filter { $0.isFilm && seen.insert($0.title).inserted && !finished.contains($0.title) }
        var remaining = pending.makeIterator()
        failures = []
        await withTaskGroup(of: (String, MetaPreview?, Bool).self) { group in
            func enqueue(_ award: FestivalAward) {
                group.addTask {
                    // Awaited on its own line, as in SourcesView: Release builds have mishandled
                    // child results awaited inside a larger expression.
                    do {
                        let meta = try await client.film(named: award.title, festivalYear: edition.year)
                        return (award.title, meta, false)
                    } catch {
                        return (award.title, nil, true)
                    }
                }
            }
            // A full edition must not swamp the catalog with parallel requests.
            for _ in 0..<4 { if let award = remaining.next() { enqueue(award) } }
            for await (title, meta, didFail) in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if didFail { failures.insert(title) }
                else {
                    finished.insert(title)
                    if let meta { matches[title] = meta }
                }
                if let award = remaining.next() { enqueue(award) }
            }
        }
    }

    @ViewBuilder
    private func sectionPicker(_ edition: FestivalEdition) -> some View {
        let sections = edition.awards.filter(\.isFilm).reduce(into: [String]()) { values, award in
            if !values.contains(award.section) { values.append(award.section) }
        }
        #if os(tvOS)
        NavigationLink { FestivalSectionView(sections: sections, selection: $section) } label: {
            HStack { Text("Awards"); Spacer(); Text(section ?? "All winners").foregroundStyle(.secondary) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("festival-section-picker")
        #else
        Picker("Awards", selection: $section) {
            Text("All winners").tag(String?.none)
            ForEach(sections, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("festival-section-picker")
        #endif
    }
}

private struct FestivalFilm: Identifiable {
    let title: String
    var awards: [FestivalAward]
    var id: String { title }
    var awardSummary: String {
        guard let first = awards.first else { return "" }
        switch first.section {
        case "Grand Jury Prizes": return "Grand Jury Prize · \(first.award)"
        case "Audience Awards": return "Audience Award · \(first.award)"
        case "Directing, Editing and Screenwriting", "Special Jury Awards": return first.award
        case "Short Film Awards": return "Short Film · \(first.award)"
        default: return first.award
        }
    }
}

private struct FestivalFilmTile: View {
    let film: FestivalFilm
    let meta: MetaPreview?
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white.opacity(0.06)
                if let poster = meta?.poster {
                    Artwork(url: poster)
                } else if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(film.title).font(.metaLine).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(12)
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Metrics.posterRadius))
            Text(film.title).font(.cardTitle).foregroundStyle(.primary).lineLimit(2)
            Text(film.awardSummary).font(.metaLine).foregroundStyle(.secondary).lineLimit(2)
            if film.awards.count > 1 {
                Text("\(film.awards.count) awards").font(.metaLine).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct FestivalFilmDestination: View {
    let film: FestivalFilm
    let collection: FilmCollection
    let year: Int
    var client = FilmCollectionClient.shared
    @State private var resolved: MetaPreview?
    @State private var loading = true
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let meta = resolved {
                MetaDetailView(preview: meta)
            } else {
                VStack(spacing: 0) {
                    FestivalFilmInfoView(film: film, collection: collection, year: year,
                                         lookupFailed: failed, loading: loading)
                    if failed { Button("Retry title") { attempt += 1 }.padding() }
                }
                .background(Color.canvas)
            }
        }
        .task(id: attempt) {
            // Usually answered from the client's cache, filled while the winners showed.
            loading = true
            failed = false
            do {
                let meta = try await client.film(named: film.title, festivalYear: year)
                try Task.checkCancellation()
                resolved = meta
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                loading = false
            }
        }
    }
}

private struct FestivalFilmInfoView: View {
    let film: FestivalFilm
    let collection: FilmCollection
    let year: Int
    let lookupFailed: Bool
    var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(film.title).font(.sectionTitle)
                Text("\(collection.name) · \(String(year))").font(.metaLine).foregroundStyle(.secondary)
                ForEach(film.awards) { award in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(award.section).font(.metaLine).foregroundStyle(.secondary)
                        Text(award.award).font(.cardTitle)
                        if let recipient = award.recipient { Text(recipient).font(.synopsis).foregroundStyle(.secondary) }
                    }
                }
                if loading {
                    ProgressView("Finding title…")
                } else {
                    Text(lookupFailed ? "The title listing couldn't load." : "A matching title listing isn't available yet.")
                        .font(.synopsis).foregroundStyle(.secondary)
                    NavigationLink("Find title", value: FestivalRoute.search(film.title))
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(Metrics.gutter)
        }
        .background(Color.canvas)
        .pageTitle(film.title)
    }
}

private struct FestivalAwardListView: View {
    let collection: FilmCollection
    let edition: FestivalEdition

    private var sections: [String] {
        edition.awards.reduce(into: []) { if !$0.contains($1.section) { $0.append($1.section) } }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(edition.awards.filter { $0.section == section }) { award in
                        if award.isFilm {
                            NavigationLink(value: FestivalRoute.film(title: award.title, collection: collection)) {
                                label(award)
                            }
                        } else {
                            label(award)
                                #if os(tvOS)
                                .focusable()
                                #endif
                        }
                    }
                }
            }
            Section("About this edition") {
                Text(edition.coverage)
                Text("Checked \(edition.checkedOn)").foregroundStyle(.secondary)
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.canvas)
        .pageTitle("\(String(edition.year)) awards")
    }

    private func label(_ award: FestivalAward) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if award.award != award.section { Text(award.award).font(.metaLine).foregroundStyle(.secondary) }
            Text(award.title).font(.cardTitle)
            if let recipient = award.recipient { Text(recipient).font(.metaLine).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 6)
    }
}

#if os(tvOS)
private struct FestivalSectionView: View {
    let sections: [String]
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button("All winners") { selection = nil; dismiss() }
            ForEach(sections, id: \.self) { section in
                Button { selection = section; dismiss() } label: {
                    HStack {
                        Text(section)
                        Spacer()
                        if selection == section { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                }
            }
        }
        .navigationTitle("Awards")
    }
}
#endif

/// Festival screens are pushed by value, like the rest of a browse stack: a screen pushed as
/// a view left the value links inside it, to titles, cast and sources, doing nothing.
enum FestivalRoute: Hashable {
    case recordedWinners(FilmCollection)
    case allAwards(FilmCollection)
    case film(title: String, collection: FilmCollection)
    case search(String)

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .recordedWinners(let collection):
            RecordedCollectionView(collection: collection)
        case .allAwards(let collection):
            if let edition = try? FestivalEdition.edition(for: collection) {
                FestivalAwardListView(collection: collection, edition: edition)
            }
        case .film(let title, let collection):
            if let edition = try? FestivalEdition.edition(for: collection) {
                FestivalFilmDestination(
                    film: FestivalFilm(title: title, awards: edition.awards.filter { $0.isFilm && $0.title == title }),
                    collection: collection, year: edition.year)
            }
        case .search(let query):
            SearchView(query: query)
        }
    }
}
