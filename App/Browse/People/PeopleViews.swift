import LogeCore
import SwiftUI

/// Credits can lack an IMDb ID, so these tiles never expose the library's save actions.
struct TMDBCreditTile: View {
    let title: TMDBCreditTitle

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.liftedCaptionSpacing) {
            // Without a poster the tile names the title, as catalog posters do.
            ZStack {
                if title.posterURL == nil {
                    Color.white.opacity(0.06)
                    // The caption below already names it.
                    TitleCard(name: title.name).accessibilityHidden(true)
                } else {
                    Artwork(url: title.posterURL)
                }
            }
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
    /// Beside another column, where the shelf can't draw past its own edges.
    var staysInColumn = false

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
        let hasPortraits = people.contains { $0.portraitURL != nil }
        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Cast & Crew")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf("cast and crew") {
                // Not lazy: a lazy row took the first tile's height, which cut off the captions of a
                // longer name further along. TMDB's cast is capped to the top billed, so it stays short.
                HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(people) { person in
                        NavigationLink(value: PersonRoute(person: person, title: title)) {
                            PersonTile(person: person, showsPortrait: hasPortraits)
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
            .scrollClipDisabled(!staysInColumn)
        }
    }
}

#if !os(tvOS)
/// Names only, one per line as a film's credits read, for when no one has a photo: a row
/// of initials in grey circles said more about what was missing than about who was in it.
struct CreditsList: View {
    let people: [Person]
    let title: MetaPreview

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
                                .frame(minHeight: Self.nameHeight, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A full touch target on iPhone and iPad; the Mac's pointer needs less.
    #if os(macOS)
    private static let nameHeight: CGFloat = 32
    #else
    private static let nameHeight: CGFloat = 44
    #endif
}
#endif

/// TMDB portraits fall back to initials when no photo is available.
struct PersonTile: View {
    let person: Person
    /// False on the TV when no one in the row has a photo: a row of initials in grey
    /// circles read as placeholders, so the names stand alone there.
    var showsPortrait = true
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        VStack(spacing: 10) {
            if showsPortrait {
                ZStack {
                    Text(initials)
                        .font(Self.initialsFont)
                        .foregroundStyle(isFocused ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
                    // Through the decoded-image cache, so portraits don't flash initials again
                    // when the shelf brings a tile back.
                    if person.portraitURL != nil {
                        Artwork(url: person.portraitURL)
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
            }
            captions
        }
        .frame(width: Metrics.personSize * 1.3)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel([person.name, person.character, roles].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private var captions: some View {
        let lines = VStack(spacing: 2) {
            Text(person.name)
                .font(Self.nameFont)
                .lineLimit(2)
            if let character = person.character {
                Text(character)
                    .font(Self.roleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(showsPortrait ? 1 : 2)
            }
            if let roles {
                Text(roles)
                    .font(Self.roleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(showsPortrait ? 1 : 2)
            }
        }
        .multilineTextAlignment(.center)
        if showsPortrait {
            // Room for a two-line name and a role is kept under every portrait, so the row is
            // as tall whether or not a name in it wraps, and no name is cut to fit.
            ZStack(alignment: .top) {
                VStack(spacing: 2) {
                    Text(verbatim: "A\nA").font(Self.nameFont)
                    Text(verbatim: "A").font(Self.roleFont)
                }
                .hidden()
                lines
            }
        } else {
            // Without circles, focus fills the names' own space with the accent, as it fills the circle.
            lines
                .foregroundStyle(isFocused ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: Metrics.posterRadius))
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
        }
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
