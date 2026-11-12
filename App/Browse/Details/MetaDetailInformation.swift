import LogeCore
import SwiftUI

/// Facts the hero's meta line leaves out, as label and value pairs in as many columns as fit.
struct InformationSection: View {
    let meta: Meta
    let details: TMDBDetails?

    var body: some View {
        let facts = facts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Information")
                    .font(.sectionTitle)
                if let tagline = details?.tagline {
                    Text(tagline).font(.synopsis).italic().foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.infoColumnWidth), spacing: 24, alignment: .topLeading)],
                          alignment: .leading, spacing: 20) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fact.label)
                                .font(.metaLine)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.synopsis)
                                .foregroundStyle(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            // At the reviews' width, so the page's text ends on one line on a portrait iPad.
            .readingWidth()
            .padding(.horizontal, Metrics.gutter)
            #if os(tvOS)
            // Without a focus stop down here, the remote can't scroll to this section.
            .focusable()
            #endif
        }
    }

    /// Runtime, year and rating are already in the meta line; the line shows only the first genres.
    private var facts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = []
        if let genres = meta.genres, !genres.isEmpty {
            facts.append(("Genres", genres.joined(separator: ", ")))
        }
        if let date = details?.releaseDate {
            facts.append((meta.type == MediaType.series ? "First Aired" : "Released", formattedDate(date)))
        } else if let date = meta.releaseDate {
            facts.append((meta.type == MediaType.series ? "First Aired" : "Released",
                          date.formatted(.dateTime.day().month(.wide).year().locale(.interface))))
        }
        if let status = details?.status { facts.append(("Status", status)) }
        if let seasons = details?.seasonCount {
            let episodes = details?.episodeCount.map { " · \($0) \($0 == 1 ? "episode" : "episodes")" } ?? ""
            facts.append(("Series", "\(seasons) \(seasons == 1 ? "season" : "seasons")\(episodes)"))
        }
        if let lastAirDate = details?.lastAirDate { facts.append(("Last Aired", formattedDate(lastAirDate))) }
        if let originalTitle = details?.originalTitle, originalTitle != meta.name {
            facts.append(("Original Title", originalTitle))
        }
        if let language = details?.originalLanguage {
            facts.append(("Original Language", Locale.interface.localizedString(forLanguageCode: language) ?? language))
        }
        if let countries = details?.countries, !countries.isEmpty {
            facts.append(("Country", countries.joined(separator: ", ")))
        } else if let country = meta.country, !country.isEmpty {
            facts.append(("Country", country))
        }
        if let studios = details?.studios, !studios.isEmpty { facts.append(("Production", studios.joined(separator: ", "))) }
        if let rating = details?.rating, let votes = details?.voteCount {
            facts.append(("TMDB Rating", "\(rating.formatted(.number.precision(.fractionLength(1)).locale(.interface)))/10 · "
                + "\(votes.formatted(.number.locale(.interface))) votes"))
        }
        let dollars = IntegerFormatStyle<Int>.Currency(code: "USD", locale: .interface).precision(.fractionLength(0))
        if let budget = details?.budget { facts.append(("Budget", budget.formatted(dollars))) }
        if let revenue = details?.revenue { facts.append(("Box Office", revenue.formatted(dollars))) }
        if let awards = meta.awards, !awards.isEmpty {
            facts.append(("Awards", awards))
        }
        return facts
    }

    private func formattedDate(_ value: String) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar(identifier: .gregorian)
                .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return value }
        return date.formatted(.dateTime.day().month(.wide).year().locale(.interface))
    }
}

/// A description clamped to two lines, with "More" under it when it overflows.
struct ExpandableText: View {
    let text: String
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        let isTruncated = !isExpanded && fullHeight > shownHeight + 1
        Button {
            if isTruncated || isExpanded { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(.synopsis)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(isExpanded ? nil : 2)
                    // Otherwise the hero's stack squeezes the expanded text back to a few lines.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                    .background(alignment: .top) {
                        // The unclamped text, measured to tell whether two lines cut it short.
                        Text(text)
                            .font(.synopsis)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                // Under the text rather than over its end: a fade to the canvas showed as a
                // dark patch where the hero's backdrop is still behind the synopsis.
                if isTruncated {
                    Text("More")
                        .font(.synopsis.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isTruncated ? "Shows the whole description" : "")
        // A short synopsis has nothing to expand, so it isn't announced as a button.
        .accessibilityRemoveTraits(isTruncated || isExpanded ? [] : .isButton)
    }
}
