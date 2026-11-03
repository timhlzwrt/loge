import LogeCore
import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var submittedQuery = ""
    /// Results per catalog for the current query, filled in as each one answers.
    @State private var resultCounts: [CatalogSource.ID: Int] = [:]
    /// "movie" or "series"; nil shows both.
    @State private var type: String?
    @State private var genre: String?
    /// Newest first, one per line.
    @AppStorage("recentSearches") private var recentSearches = ""

    var body: some View {
        let sources = DiscoveryCatalogs.search.filtered(type: type, genre: genre)
        ScrollView {
            filters
            if query.isEmpty && genre == nil {
                recent
                genreList
            } else if query.isEmpty {
                // Browsing a genre: each row's See All opens the whole genre.
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(sources) { CatalogRow(source: $0) }
                }
                .padding(.vertical, 24)
            } else if !submittedQuery.isEmpty {
                // Rows with no matches hide themselves, so without this an unsuccessful
                // search would look like it was still loading.
                if sources.allSatisfy({ resultCounts[$0.id] == 0 }) {
                    ContentUnavailableView.search(text: submittedQuery)
                        .padding(.top, 80)
                }
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(sources) { source in
                        CatalogRow(source: source, search: submittedQuery, onLoaded: { count in
                            resultCounts[source.id] = count
                        })
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .navigationTitle("Search")
        #if os(iOS)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movies and series")
        #else
        .searchable(text: $query, prompt: "Movies and series")
        #endif
        .onSubmit(of: .search) { remember(query) }
        // Opening a result also leaves this screen, which is when a search proved useful.
        .onDisappear { remember(submittedQuery) }
        .task(id: query) {
            // Wait for a pause in typing so each keystroke doesn't query every addon.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed != submittedQuery { resultCounts = [:] }
            submittedQuery = trimmed
        }
    }

    /// Genres of the types shown; a series-only genre such as Reality-TV hides Movies.
    private var genres: [String] {
        DiscoveryCatalogs.search.filtered(type: type, genre: nil).genres
    }

    private var filters: some View {
        HStack(spacing: 20) {
            Picker("Type", selection: $type) {
                Text("All").tag(String?.none)
                ForEach(DiscoveryCatalogs.search) { Text($0.title).tag(Optional($0.catalog.type)) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            // With nothing typed the genre list below is the way in, so only a chosen genre
            // shows here, as something to remove; while searching, a menu narrows the results.
            if let genre {
                Button {
                    self.genre = nil
                } label: {
                    HStack(spacing: 6) {
                        Text(genre)
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    #if !os(tvOS)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(.white.opacity(0.12), in: .capsule)
                    #endif
                }
                #if !os(tvOS)
                .buttonStyle(.plain)
                #endif
                .accessibilityLabel("\(genre), remove genre")
                .fixedSize()
            } else if !query.isEmpty {
                Menu {
                    Picker("Genre", selection: $genre) {
                        Text("Any Genre").tag(String?.none)
                        ForEach(genres, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                } label: {
                    Label("Genre", systemImage: "line.3.horizontal.decrease.circle")
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .labelsHidden()
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .onChange(of: type) {
            if let genre, !genres.contains(genre) { self.genre = nil }
        }
    }

    private var genreList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth * 1.4), spacing: 24, alignment: .leading)],
                      alignment: .leading, spacing: 0) {
                ForEach(genres, id: \.self) { genre in
                    Button { self.genre = genre } label: {
                        HStack {
                            Text(genre)
                            Spacer(minLength: 8)
                            #if !os(tvOS)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            #endif
                        }
                        #if !os(tvOS)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 0.5) }
                        .contentShape(.rect)
                        #endif
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 24)
    }

    private var recents: [String] {
        recentSearches.split(separator: "\n").map(String.init)
    }

    @ViewBuilder
    private var recent: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Searches")
                        .font(.headline)
                    Spacer()
                    Button("Clear") { recentSearches = "" }
                        #if !os(tvOS)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        #endif
                }
                ForEach(recents, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
        }
    }

    /// Saves a search that found something; ones that didn't aren't worth repeating.
    private func remember(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2, term == submittedQuery, resultCounts.values.contains(where: { $0 > 0 }) else { return }
        let others = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentSearches = ([term] + others).prefix(10).joined(separator: "\n")
    }
}
