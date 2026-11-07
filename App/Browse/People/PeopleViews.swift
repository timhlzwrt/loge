import LogeCore
import SwiftUI

/// Credits can lack an IMDb ID, so these tiles never expose the library's save actions.
struct TMDBCreditTile: View {
    let title: TMDBCreditTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: title.posterURL)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                #if os(tvOS)
                // Only the poster lifts; a card around the text clipped its first letters.
                .hoverEffect(.highlight)
                #endif
            Text(title.name).font(.cardTitle).lineLimit(2)
            CreditMetaLines(title: title, roleLineLimit: 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// "Cast & Crew" on the details screen: everyone credited, each opening their titles.
struct PeopleRow: View {
    let people: [Person]
    let title: MetaPreview

    var body: some View {
        #if os(tvOS)
        // The remote moves between tiles, so the TV keeps them even without photos.
        tiles
        #else
        if people.contains(where: { $0.portraitURL != nil }) {
            tiles
        } else {
            CreditsList(people: people, title: title)
        }
        #endif
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Cast & Crew")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf("cast and crew") {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
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
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollClipDisabled()
        }
    }
}

#if !os(tvOS)
/// Names only, one per line as a film's credits read, for when no one has a photo: a row
/// of initials in grey circles said more about what was missing than about who was in it.
struct CreditsList: View {
    let people: [Person]
    let title: MetaPreview
    @Environment(TMDBAccount.self) private var tmdb

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Cast & Crew")
                .font(.sectionTitle)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                line("Starring", role: .actor)
                line("Director", role: .director)
                line("Writer", role: .writer)
            }
            .font(.synopsis)
            if !tmdb.isConfigured {
                Text("Connect TMDB in Settings for photos and character names.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    @ViewBuilder
    private func line(_ label: String, role: Person.Role) -> some View {
        let credited = people.filter { $0.roles.contains(role) }
        if !credited.isEmpty {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(credited) { person in
                        NavigationLink(value: PersonRoute(person: person, title: title)) {
                            Text(person.name)
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(minHeight: 32, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
#endif

/// TMDB portraits fall back to initials when no photo is available.
struct PersonTile: View {
    let person: Person
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        VStack(spacing: 10) {
            AsyncImage(url: person.portraitURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Text(initials)
                        .font(Self.initialsFont)
                        .foregroundStyle(isFocused ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
                }
            }
                .frame(width: Metrics.personSize, height: Metrics.personSize)
                .background(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.08)), in: .circle)
                .clipShape(.circle)
                #if os(tvOS)
                // The circle fills with the accent and lifts, as the glass buttons above it do.
                .scaleEffect(isFocused ? 1.08 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
            VStack(spacing: 2) {
                Text(person.name)
                    .font(Self.nameFont)
                    .lineLimit(2)
                if let character = person.character {
                    Text(character)
                        .font(Self.roleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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
        .accessibilityLabel([person.name, person.character, roles].compactMap { $0 }.joined(separator: ", "))
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
struct PersonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif
