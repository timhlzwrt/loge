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
    /// The term Return was pressed on, saved to Recent Searches once a catalog finds it.
    @State private var returnedQuery: String?
    /// Newest first, one per line.
    @AppStorage("recentSearches") private var recentSearches = ""
    #if os(tvOS)
    /// A genre tile was just picked; the rows that replace it take focus. Not after a type change.
    @State private var focusesFirstResult = false
    #endif

    init(query: String = "") {
        _query = State(initialValue: query)
    }

    var body: some View {
        let sources = DiscoveryCatalogs.search.filtered(type: type, genre: genre)
        // Spaces alone search nothing, so they show what an empty field does.
        let isEmpty = trimmedQuery.isEmpty
        ScrollView {
            filters
            if isEmpty && genre == nil {
                recent
                genreList
            } else if isEmpty {
                // Browsing a genre: each row's See All opens the whole genre.
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(sources) { source in
                        CatalogRow(source: source, takesFocusWhenLoaded: takesFocus && source.id == sources.first?.id)
                    }
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
                            if count > 0, returnedQuery == submittedQuery { remember(submittedQuery) }
                        })
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PageGlow() }
        #if !os(tvOS)
        // tvOS keeps a title fixed in place, over the content as it scrolls; the tab already says Search.
        .navigationTitle("Search")
        #endif
        #if os(iOS)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movies and series")
        #else
        .searchable(text: $query, prompt: "Movies and series")
        #endif
        .onSubmit(of: .search) {
            // Return searches at once rather than after the typing pause.
            submit(trimmedQuery)
            returnedQuery = trimmedQuery
            remember(trimmedQuery)
        }
        // Opening a result also leaves this screen, which is when a search proved useful.
        .onDisappear { remember(submittedQuery) }
        .task(id: query) {
            // Wait for a pause in typing so each keystroke doesn't query every addon.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            submit(trimmedQuery)
        }
    }

    private var takesFocus: Bool {
        #if os(tvOS)
        focusesFirstResult
        #else
        false
        #endif
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private func submit(_ term: String) {
        guard term != submittedQuery else { return }
        resultCounts = [:]
        submittedQuery = term
    }

    /// Genres of the types shown; a series-only genre such as Reality-TV hides Movies.
    private var genres: [String] {
        DiscoveryCatalogs.search.filtered(type: type, genre: nil).genres
    }

    /// What the results are narrowed to, read as a sentence whose values are the menus that change them.
    private var filters: some View {
        Sentence.filters {
            Words("Looking for")
            Menu {
                Picker("Type", selection: $type) {
                    Text("Movies and series").tag(String?.none)
                    ForEach(DiscoveryCatalogs.search) { Text($0.title).tag(Optional($0.catalog.type)) }
                }
            } label: {
                TokenLabel(DiscoveryCatalogs.search.first { $0.catalog.type == type }?.title.lowercased() ?? "movies and series")
            }
            .accessibilityLabel("Type")
            .accessibilityValue(DiscoveryCatalogs.search.first { $0.catalog.type == type }?.title ?? "Movies and series")
            Words("in")
            Menu {
                Picker("Genre", selection: $genre) {
                    Text("Any genre").tag(String?.none)
                    ForEach(genres, id: \.self) { Text($0).tag(Optional($0)) }
                }
            } label: {
                TokenLabel(genre?.lowercased() ?? "any genre")
            }
            .accessibilityLabel("Genre")
            .accessibilityValue(genre ?? "Any genre")
            Words(".")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(TokenButtonStyle())
        .menuStyle(.button)
        .labelsHidden()
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .onChange(of: type) {
            if let genre, !genres.contains(genre) { self.genre = nil }
            #if os(tvOS)
            focusesFirstResult = false
            #endif
        }
    }

    private var genreList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth * 1.4), spacing: Metrics.rowSpacing)],
                      spacing: Metrics.rowSpacing) {
                ForEach(genres.compactMap(DiscoveryCatalogs.genre(named:))) { genre in
                    Button {
                        #if os(tvOS)
                        focusesFirstResult = true
                        #endif
                        self.genre = genre.name
                    } label: {
                        GenreTile(genre: genre, width: nil)
                    }
                    .tileButtonStyle()
                }
            }
            #if os(tvOS)
            // Room for the focus lift, which would otherwise cover the heading.
            .padding(.vertical, 20)
            #endif
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
                    Button {
                        recentSearches = ""
                    } label: {
                        Text("Clear")
                            #if !os(tvOS)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                            #endif
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    #endif
                }
                VStack(alignment: .leading, spacing: Self.recentSpacing) {
                    ForEach(recents, id: \.self) { term in
                        Button {
                            query = term
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                #if os(tvOS)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                #else
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                #endif
                                .contentShape(.rect)
                        }
                        #if !os(tvOS)
                        .buttonStyle(.plain)
                        #endif
                        // A one-off search can go without clearing the whole list.
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) { forget(term) }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
        }
    }

    /// The 44 pt rows already space themselves out on iPhone, iPad and Mac.
    #if os(tvOS)
    private static let recentSpacing: CGFloat = 12
    #else
    private static let recentSpacing: CGFloat = 0
    #endif

    private func forget(_ term: String) {
        recentSearches = recents.filter { $0 != term }.joined(separator: "\n")
    }

    /// Saves a search that found something; ones that didn't aren't worth repeating.
    private func remember(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2, term == submittedQuery, resultCounts.values.contains(where: { $0 > 0 }) else { return }
        let others = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentSearches = ([term] + others).prefix(10).joined(separator: "\n")
    }
}
