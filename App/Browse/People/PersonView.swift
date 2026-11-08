import LogeCore
import SwiftUI

/// A person picked on a title's details or a discovery shelf.
struct PersonRoute: Hashable {
    let person: Person
    /// Retained when catalog search misses the title the person was found on.
    let title: MetaPreview?

    init(person: Person, title: MetaPreview? = nil) {
        self.person = person
        self.title = title
    }
}

struct PersonView: View {
    let route: PersonRoute
    @Environment(TMDBAccount.self) private var tmdb
    @State private var state = LoadState.loading
    @State private var attempt = 0
    @State private var filter = CreditFilter.all
    @State private var role: TMDBCreditRole?
    @State private var sort = CreditSort.newest
    @State private var biographyExpanded = false

    private enum LoadState {
        case loading
        case filmography(TMDBPersonDetails)
        case catalog([MetaPreview])
        case failed(String)
    }

    private enum CreditFilter: String, CaseIterable {
        case all = "All", movies = "Movies", series = "Series"
    }

    private enum CreditSort: String, CaseIterable {
        case newest = "Newest first", oldest = "Oldest first", title = "Title"
    }

    private struct LoadKey: Hashable {
        let revision: Int
        let attempt: Int
    }

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                loading
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry") { attempt += 1 }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            case .filmography(let person):
                VStack(alignment: .leading, spacing: 28) {
                    profile(person)
                    filmography(person.titles)
                }
                .padding(.vertical, 24)
            case .catalog(let titles):
                VStack(alignment: .leading, spacing: 32) {
                    Text(tmdb.isConfigured
                         ? "This credit has no TMDB person ID. Catalog matches may be incomplete."
                         : "Connect TMDB in Settings for the full filmography. Catalog matches below may be incomplete.")
                        .font(.metaLine)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Metrics.gutter)
                    catalogSection("Movies", titles.filter { $0.type == MediaType.movie })
                    catalogSection("Series", titles.filter { $0.type == MediaType.series })
                    if titles.isEmpty {
                        ContentUnavailableView("No catalog matches", systemImage: "person",
                                               description: Text("No titles crediting this name were found."))
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .scrollClipDisabled()
        .background(Color.canvas)
        .hidingPhoneTabBar()
        .navigationTitle(route.person.name)
        .task(id: LoadKey(revision: tmdb.revision, attempt: attempt)) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--person-role-ui-test") {
                state = .filmography(TMDBPersonDetails(id: 1, name: "Filmography check", titles: [
                    TMDBCreditTitle(tmdbID: 1, type: "movie", name: "Acting movie", roles: ["Actor"], creditRoles: [.acting]),
                    TMDBCreditTitle(tmdbID: 2, type: "series", name: "Directed series", roles: ["Director"], creditRoles: [.directing]),
                    TMDBCreditTitle(tmdbID: 3, type: "movie", name: "Mixed credit", roles: ["Actor", "Director", "Producer"],
                                    creditRoles: [.acting, .directing, .otherCrew]),
                    TMDBCreditTitle(tmdbID: 4, type: "series", name: "Camera series", roles: ["Director of Photography"],
                                    creditRoles: [.otherCrew]),
                ]))
                return
            }
            #endif
            state = .loading
            do {
                if let id = route.person.tmdbID, tmdb.isConfigured {
                    let person = try await tmdb.personDetails(id: id)
                    try Task.checkCancellation()
                    state = .filmography(person)
                } else {
                    let titles = try await catalogTitles()
                    try Task.checkCancellation()
                    state = .catalog(titles)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = switch error as? TMDBError {
                case .unauthorized: "TMDB didn't accept the saved token. Check TMDB in Settings."
                case .rateLimited: "TMDB is busy. Try again in a few minutes."
                case .notFound: "This person wasn't found on TMDB."
                default: "Couldn't load titles with \(route.person.name)."
                }
                state = .failed(message)
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 20) {
                Artwork(url: route.person.portraitURL)
                    .frame(width: Metrics.personSize * 1.4, height: Metrics.personSize * 2.1)
                    .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                    .accessibilityHidden(true)
                Text(route.person.name).font(.sectionTitle)
            }
            ProgressView("Loading filmography…")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing,
                                        alignment: .top)], spacing: Metrics.rowSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Metrics.posterRadius)
                        .fill(.white.opacity(0.06))
                        .aspectRatio(2 / 3, contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 24)
    }

    private func profile(_ person: TMDBPersonDetails) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Artwork(url: person.portraitURL ?? route.person.portraitURL)
                    .frame(width: Metrics.personSize * 1.4, height: Metrics.personSize * 2.1)
                    .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.name).font(.sectionTitle)
                    if let department = person.knownFor {
                        Text(department).font(.metaLine).foregroundStyle(.secondary)
                    }
                    if let birthday = person.birthday.flatMap(Self.formattedBirthday) {
                        Text("Born \(birthday)").font(.metaLine).foregroundStyle(.secondary)
                    }
                    if let birthplace = person.placeOfBirth {
                        Text(birthplace).font(.metaLine).foregroundStyle(.secondary)
                    }
                    #if !os(tvOS)
                    Link("View profile on TMDB", destination: URL(string: "https://www.themoviedb.org/person/\(person.id)")!)
                        .font(.metaLine)
                        .frame(minHeight: 44)
                    #endif
                }
            }
            if let biography = person.biography {
                VStack(alignment: .leading, spacing: 8) {
                    Text(biography)
                        .font(.synopsis)
                        .foregroundStyle(.secondary)
                        .lineLimit(biographyExpanded ? nil : 5)
                        .readingWidth()
                    Button(biographyExpanded ? "Show Less" : "Read Biography") {
                        biographyExpanded.toggle()
                    }
                    .font(.metaLine)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func filmography(_ titles: [TMDBCreditTitle]) -> some View {
        let titles = titles.filter { title in role.map { title.creditRoles.contains($0) } ?? true }
        let movies = titles.filter { $0.type == MediaType.movie }.count
        let series = titles.filter { $0.type == MediaType.series }.count
        let visible = sortedTitles(titles.filter {
            filter == .all || (filter == .movies && $0.type == MediaType.movie) || (filter == .series && $0.type == MediaType.series)
        })
        return VStack(alignment: .leading, spacing: 20) {
            Text("Filmography").font(.sectionTitle)
            Picker("Title type", selection: $filter) {
                Text("All (\(titles.count))").tag(CreditFilter.all)
                Text("Movies (\(movies))").tag(CreditFilter.movies)
                Text("Series (\(series))").tag(CreditFilter.series)
            }
            .pickerStyle(.segmented)
            #if os(tvOS)
            Picker("Credit role", selection: $role) {
                Text("All roles").tag(TMDBCreditRole?.none)
                ForEach(TMDBCreditRole.allCases, id: \.self) { role in
                    Text(role.rawValue).tag(Optional(role))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("person-role-filter")
            #endif
            HStack {
                #if !os(tvOS)
                Menu {
                    Picker("Credit role", selection: $role) {
                        Text("All roles").tag(TMDBCreditRole?.none)
                        ForEach(TMDBCreditRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(Optional(role))
                        }
                    }
                } label: {
                    Label(role?.rawValue ?? "All roles", systemImage: "line.3.horizontal.decrease")
                        .font(.metaLine)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Credit role")
                .accessibilityValue(role?.rawValue ?? "All roles")
                .accessibilityIdentifier("person-role-filter")
                #endif
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CreditSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.metaLine)
                }
            }
            if visible.isEmpty {
                Text("No credits in this category.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing, alignment: .top)],
                          alignment: .leading, spacing: Metrics.rowSpacing) {
                    ForEach(visible) { title in
                        NavigationLink {
                            TMDBTitleView(title: title)
                        } label: {
                            TMDBCreditTile(title: title)
                        }
                        #if os(tvOS)
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .accessibilityIdentifier("person-filmography")
                #if os(tvOS)
                .padding(.top, 20)
                #endif
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private static func formattedBirthday(_ value: String) -> String? {
        guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func sortedTitles(_ titles: [TMDBCreditTitle]) -> [TMDBCreditTitle] {
        titles.sorted { lhs, rhs in
            if sort != .title {
                // Undated credits remain after dated work in either chronological direction.
                if lhs.releaseDate == nil, rhs.releaseDate != nil { return false }
                if lhs.releaseDate != nil, rhs.releaseDate == nil { return true }
                if lhs.releaseDate != rhs.releaseDate {
                    return sort == .newest
                        ? (lhs.releaseDate ?? "") > (rhs.releaseDate ?? "")
                        : (lhs.releaseDate ?? "") < (rhs.releaseDate ?? "")
                }
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    private func catalogTitles() async throws -> [MetaPreview] {
        let name = route.person.name
        let results = try await withThrowingTaskGroup(of: [MetaPreview].self) { group in
            for source in DiscoveryCatalogs.search {
                group.addTask { try await source.items(search: name) }
            }
            var results: [MetaPreview] = []
            for try await titles in group { results += titles }
            return results
        }
        if let title = route.title { return route.person.titles(in: results, foundOn: title) }
        return results.filter { $0.credits(name) }.sorted { ($0.releaseInfo ?? "") > ($1.releaseInfo ?? "") }
    }

    @ViewBuilder
    private func catalogSection(_ title: String, _ titles: [MetaPreview]) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text(title).font(.sectionTitle)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing, alignment: .top)],
                          spacing: Metrics.rowSpacing) {
                    ForEach(titles) { meta in
                        NavigationLink(value: meta) {
                            PosterTile(meta: meta, width: nil)
                        }
                        .tileButtonStyle()
                    }
                }
                #if os(tvOS)
                .padding(.top, 20)
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }
}
