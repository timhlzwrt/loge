import LogeCore
import SwiftUI

struct SearchView: View {
    @Environment(TMDBAccount.self) private var tmdb
    @State private var ownQuery = ""
    /// The Mac's toolbar field, which lives above the tabs, in place of this page's own.
    private var toolbarQuery: Binding<String>?
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
        _ownQuery = State(initialValue: query)
    }

    #if os(macOS)
    init(toolbarQuery: Binding<String>) {
        self.toolbarQuery = toolbarQuery
    }
    #endif

    private var query: Binding<String> { toolbarQuery ?? $ownQuery }

    var body: some View {
        if toolbarQuery != nil {
            page
        } else {
            page
                #if os(iOS)
                .searchable(text: $ownQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
                .navigationBarTitleDisplayMode(.large)
                #else
                .searchable(text: $ownQuery, prompt: prompt)
                #endif
                .onSubmit(of: .search) {
                    // Return searches at once rather than after the typing pause.
                    submit(trimmedQuery)
                    returnedQuery = trimmedQuery
                    remember(trimmedQuery)
                }
        }
    }

    @ViewBuilder
    private var page: some View {
        let sources = DiscoveryCatalogs.search.filtered(type: type, genre: genre)
        // Spaces alone search nothing, so they show what an empty field does.
        let isEmpty = trimmedQuery.isEmpty
        ScrollView {
            // A phone opens on recent searches and genres; the filters come with something to narrow.
            if Metrics.isTV || !isEmpty || genre != nil || type != nil {
                filters
            }
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
                if !Metrics.isTV {
                    SearchResultList(sources: sources, query: submittedQuery, onLoaded: loaded)
                        .padding(.vertical, 12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(sources) { source in
                            CatalogRow(source: source, search: submittedQuery, onLoaded: { loaded(source.id, count: $0) })
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        #if !os(tvOS)
        // tvOS keeps a title fixed in place, over the content as it scrolls; the tab already says Search.
        .navigationTitle("Search")
        #endif
        // Opening a result also leaves this screen, which is when a search proved useful.
        .onDisappear { remember(submittedQuery) }
        .task(id: query.wrappedValue) {
            // Wait for a pause in typing so each keystroke doesn't query every addon.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            submit(trimmedQuery)
        }
    }

    /// A catalog's number of results, or -1 when it failed.
    private func loaded(_ id: CatalogSource.ID, count: Int) {
        resultCounts[id] = count
        if count > 0, returnedQuery == submittedQuery { remember(submittedQuery) }
    }

    /// A phone finds people too, with TMDB.
    private var prompt: String {
        !Metrics.isTV && tmdb.isConfigured ? "Movies, series and people" : "Movies and series"
    }

    private var takesFocus: Bool {
        #if os(tvOS)
        focusesFirstResult
        #else
        false
        #endif
    }

    private var trimmedQuery: String {
        query.wrappedValue.trimmingCharacters(in: .whitespaces)
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
            Text("Browse by Genre")
                .font(.sectionTitle)
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
                    Text("Recent")
                        .font(.sectionTitle)
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
                            query.wrappedValue = term
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

/// A phone's results: one list across the catalogs, alternating between them as they rank
/// their own matches, each title a row with its kind and year. With TMDB, someone whose name
/// matches comes first.
private struct SearchResultList: View {
    let sources: [CatalogSource]
    let query: String
    /// A catalog's number of results, or -1 when it failed.
    let onLoaded: (CatalogSource.ID, _ count: Int) -> Void

    @Environment(TMDBAccount.self) private var tmdb
    @State private var results: [CatalogSource.ID: Result<[MetaPreview], Error>] = [:]
    @State private var person: Person?
    @State private var attempt = 0

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let person {
                NavigationLink(value: PersonRoute(person: person)) {
                    row(name: person.name, detail: role(of: person)) {
                        PersonAvatar(name: person.name, portraitURL: person.portraitURL, size: 54)
                    }
                }
                .buttonStyle(.plain)
            }
            if Metrics.isPhone {
                ForEach(titles) { meta in
                    NavigationLink(value: meta) {
                        row(name: meta.name, detail: detail(of: meta)) {
                            Artwork(url: meta.poster)
                                .frame(width: 54, height: 81)
                                .clipShape(.rect(cornerRadius: 7))
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { WatchLaterToggle(title: meta) }
                }
            } else {
                // Wider screens have room for the posters themselves.
                LazyVGrid(columns: Metrics.posterGridColumns, spacing: 22) {
                    ForEach(titles) { meta in
                        NavigationLink(value: meta) {
                            PosterTile(meta: meta, width: nil, caption: .line(detail(of: meta)))
                        }
                        .tileButtonStyle()
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
            }
            let failed = sources.filter { if case .failure = results[$0.id] { true } else { false } }
            if !failed.isEmpty {
                HStack {
                    Text("Couldn't search \(failed.map(\.title).formatted(.list(type: .and).locale(.interface))).")
                        .foregroundStyle(.secondary)
                    Button("Retry") { attempt += 1 }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
            }
            if sources.contains(where: { results[$0.id] == nil }) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .task(id: query) {
            results = [:]
            person = nil
        }
        .task(id: "\(query)#\(attempt)") { await load() }
        // Not an error worth showing: the titles are what was searched for.
        .task(id: "\(query)#\(tmdb.revision)") {
            guard tmdb.isConfigured else { return }
            person = try? await tmdb.person(named: query)
        }
    }

    /// The catalogs' lists taken in turn, so neither kind waits below the other's whole list.
    private var titles: [MetaPreview] {
        let lists = sources.map { source -> [MetaPreview] in
            if case .success(let metas) = results[source.id] { metas } else { [] }
        }
        var seen = Set<String>()
        return (0..<(lists.map(\.count).max() ?? 0)).flatMap { index in
            lists.compactMap { index < $0.count ? $0[index] : nil }
        }
        .filter { seen.insert($0.id).inserted }
    }

    private func load() async {
        let query = query
        await withTaskGroup(of: (CatalogSource.ID, Result<[MetaPreview], Error>).self) { group in
            for source in sources where !isLoaded(source) {
                results[source.id] = nil
                group.addTask {
                    do {
                        // Awaited on its own line, as Release builds have lost a child task's result
                        // when it was wrapped straight into another expression.
                        let metas = try await source.items(search: query)
                        return (source.id, .success(metas))
                    } catch {
                        return (source.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                guard !Task.isCancelled else { return }
                results[id] = result
                if case .success(let metas) = result { onLoaded(id, metas.count) } else { onLoaded(id, -1) }
            }
        }
    }

    private func isLoaded(_ source: CatalogSource) -> Bool {
        if case .success = results[source.id] { true } else { false }
    }

    private func row(name: String, detail: String?, @ViewBuilder image: () -> some View) -> some View {
        HStack(spacing: 14) {
            image()
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(detail ?? "")
    }

    /// "Movie · 2021".
    private func detail(of meta: MetaPreview) -> String? {
        let kind = meta.type == MediaType.movie ? "Movie" : meta.type == MediaType.series ? "Series" : nil
        return [kind, meta.releaseInfo?.nilIfEmpty].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    private func role(of person: Person) -> String {
        switch person.roles.first {
        case .director: "Director"
        case .writer: "Writer"
        case .actor: "Actor"
        case nil: "Person"
        }
    }
}
