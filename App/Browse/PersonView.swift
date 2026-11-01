import MediaCore
import SwiftUI

/// A person picked on a title's details.
struct PersonRoute: Hashable {
    let person: Person
    /// Kept among their titles, since a search by name can miss it.
    let title: MetaPreview
}

/// The movies and series a person is credited on. Without a people database this is a
/// search by name, as Stremio does for cast links, narrowed to the titles that credit them.
struct PersonView: View {
    let route: PersonRoute

    @State private var state = LoadState.loading

    private enum LoadState {
        case loading
        case loaded([MetaPreview])
        case failed
    }

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            case .failed:
                VStack(spacing: 8) {
                    Text("Couldn't load titles with \(route.person.name).")
                        .foregroundStyle(.secondary)
                    Button("Retry") { state = .loading }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            case .loaded(let titles):
                VStack(alignment: .leading, spacing: 32) {
                    section("Movies", titles.filter { $0.type == "movie" })
                    section("Series", titles.filter { $0.type == "series" })
                }
                .padding(.vertical, 24)
            }
        }
        .scrollClipDisabled()
        .background(Color.canvas)
        .navigationTitle(route.person.name)
        .task(id: isLoading) {
            guard isLoading else { return }
            do {
                let name = route.person.name
                let results = try await withThrowingTaskGroup(of: [MetaPreview].self) { group in
                    for source in DiscoveryCatalogs.search {
                        group.addTask { try await source.items(search: name) }
                    }
                    var results: [MetaPreview] = []
                    for try await titles in group { results += titles }
                    return results
                }
                state = .loaded(route.person.titles(in: results, foundOn: route.title))
            } catch is CancellationError {
                // Navigated away; nothing to show.
            } catch {
                state = .failed
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    @ViewBuilder
    private func section(_ title: String, _ titles: [MetaPreview]) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text(title)
                    .font(.sectionTitle)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                          spacing: Metrics.rowSpacing) {
                    ForEach(titles) { meta in
                        NavigationLink(value: meta) {
                            PosterTile(meta: meta, width: nil)
                        }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                // Room for the focus lift, which would otherwise cover the title.
                .padding(.top, 20)
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }
}

/// "Cast & Crew" on the details screen: everyone credited, each opening their titles.
struct PeopleRow: View {
    let people: [Person]
    let title: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Cast & Crew")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(people) { person in
                        NavigationLink(value: PersonRoute(person: person, title: title)) {
                            PersonTile(person: person)
                        }
                        #if os(tvOS)
                        .buttonStyle(PersonButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

/// Initials in a circle where a photo would be, since addons don't send any, then the
/// name and, for crew, what they did. Actors need no label under "Cast & Crew".
private struct PersonTile: View {
    let person: Person
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        VStack(spacing: 10) {
            Text(initials)
                .font(Self.initialsFont)
                .foregroundStyle(isFocused ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
                .frame(width: Metrics.personSize, height: Metrics.personSize)
                .background(.white.opacity(isFocused ? 1 : 0.08), in: .circle)
                #if os(tvOS)
                // The circle turns white and lifts, as the glass buttons above it do.
                .scaleEffect(isFocused ? 1.08 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
            VStack(spacing: 2) {
                Text(person.name)
                    .font(Self.nameFont)
                    .lineLimit(2)
                if let roles {
                    Text(roles)
                        .font(Self.roleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(width: Metrics.personSize * 1.3)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel([person.name, roles].compactMap { $0 }.joined(separator: ", "))
    }

    /// "MM" for Matthew McConaughey.
    private var initials: String {
        let words = person.name.split(separator: " ")
        return [words.first, words.count > 1 ? words.last : nil]
            .compactMap { $0?.first.map(String.init) }
            .joined()
    }

    /// "Director, Writer"
    private var roles: String? {
        let crew = person.roles.compactMap { role -> String? in
            switch role {
            case .actor: nil
            case .director: "Director"
            case .writer: "Writer"
            }
        }
        return crew.isEmpty ? nil : crew.joined(separator: ", ")
    }

    #if os(tvOS)
    private static let initialsFont = Font.system(size: 44, weight: .semibold)
    private static let nameFont = Font.system(size: 23, weight: .semibold)
    private static let roleFont = Font.system(size: 20)
    #elseif os(macOS)
    private static let initialsFont = Font.system(size: 22, weight: .semibold)
    private static let nameFont = Font.system(size: 13, weight: .semibold)
    private static let roleFont = Font.system(size: 12)
    #else
    private static let initialsFont = Font.title2.weight(.semibold)
    private static let nameFont = Font.footnote.weight(.semibold)
    private static let roleFont = Font.caption
    #endif
}

#if os(tvOS)
/// Leaves focus to `PersonTile`, which shows it on the circle alone; the system styles
/// would put a square platter behind it.
private struct PersonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif
