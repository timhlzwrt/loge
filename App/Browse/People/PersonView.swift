import LogeCore
import SwiftUI

/// A person picked on a title's details or a discovery shelf.
struct PersonRoute: Hashable {
    let person: Person
    /// The title the person was found on, shown when there's no TMDB filmography.
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
    @State private var biographyFullHeight: CGFloat = 0
    @State private var biographyShownHeight: CGFloat = 0

    private enum LoadState {
        case loading
        case filmography(TMDBPersonDetails)
        case unlinked
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
            case .unlinked:
                unlinked
            }
        }
        .scrollClipDisabled()
        .background(Color.canvas)
        .hidingPhoneTabBar()
        // The name heads the page beside the portrait, so iOS leaves the bar untitled, as on
        // details, and the TV draws its title over the filmography as the page scrolls.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
        .navigationTitle(route.person.name)
        #endif
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
                    // Cinemeta's name search no longer carries cast or directors, so it can't
                    // tell which results a person worked on.
                    state = .unlinked
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
                        // TMDB names the department: "Directing", "Acting".
                        Text("Known for \(department.lowercased())").font(.metaLine).foregroundStyle(.secondary)
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { biographyShownHeight = $0 }
                        .background(alignment: .top) {
                            // The unclamped text, measured so the button shows only when five lines cut it short.
                            Text(biography)
                                .font(.synopsis)
                                .fixedSize(horizontal: false, vertical: true)
                                .readingWidth()
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { biographyFullHeight = $0 }
                        }
                    if biographyExpanded || biographyFullHeight > biographyShownHeight + 1 {
                        Button {
                            biographyExpanded.toggle()
                        } label: {
                            Text(biographyExpanded ? "Show Less" : "Read Biography")
                                #if !os(tvOS)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                                #endif
                        }
                        .font(.metaLine)
                    }
                }
                #if os(tvOS)
                // Across the whole screen a line ran past 250 characters, too long to follow.
                .frame(maxWidth: 1100, alignment: .leading)
                #endif
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
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Sort")
                .accessibilityValue(sort.rawValue)
            }
            if visible.isEmpty {
                Text("No credits in this category.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing, alignment: .top)],
                          alignment: .leading, spacing: Metrics.rowSpacing) {
                    ForEach(visible) { title in
                        // By value, as festival and genre tiles: a view-built destination left
                        // the links inside the resolved details dead.
                        NavigationLink(value: title) {
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
        formatter.locale = .interface
        formatter.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
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

    private var unlinked: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 20) {
                if let portrait = route.person.portraitURL {
                    Artwork(url: portrait)
                        .frame(width: Metrics.personSize * 1.4, height: Metrics.personSize * 2.1)
                        .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                        .accessibilityHidden(true)
                }
                Text(route.person.name).font(.sectionTitle)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tmdb.isConfigured ? "No filmography" : "Filmography needs TMDB").font(.sectionTitle)
                Text(tmdb.isConfigured
                     ? "TMDB doesn't link this credit to a person."
                     : "Connect TMDB in Settings to list \(route.person.name)'s films and series.")
                    .font(.synopsis)
                    .foregroundStyle(.secondary)
                    .readingWidth()
            }
            if let title = route.title {
                VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                    Text("Credited on").font(.sectionTitle)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing, alignment: .top)],
                              spacing: Metrics.rowSpacing) {
                        NavigationLink(value: title) {
                            PosterTile(meta: title, width: nil)
                        }
                        .tileButtonStyle()
                    }
                    #if os(tvOS)
                    .padding(.top, 20)
                    #endif
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 24)
    }
}
