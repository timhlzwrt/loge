import LogeCore
import SwiftUI

/// TMDB member reviews. Without TMDB there's no section: the scores in the header link to
/// IMDb and Letterboxd, which used to be listed here as two rows of their own.
struct ReviewsSection: View {
    let preview: MetaPreview
    var showsAll = false
    /// Counts the details page's Retry, which reloads reviews that failed along with the rest.
    var pageRetries = 0
    /// The page shows its own Retry, so a second one here would be a duplicate.
    var pageOffersRetry = false
    @Environment(TMDBAccount.self) private var tmdb
    @State private var reviews: [TMDBReview] = []
    @State private var nextPage = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var failure: String?
    /// TMDB doesn't know the title, so it has no member reviews to promise.
    @State private var isOnTMDB = true
    @State private var activeRequestKey = ""

    private let previewCount = 2

    private var requestKey: String { "\(tmdb.revision):\(preview.type):\(preview.id)" }

    var body: some View {
        // TMDB is asked by IMDb ID.
        if tmdb.isConfigured, ReviewLinks.imdb(imdbID: preview.id) != nil {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                #if os(tvOS)
                // Also on the pushed list: the TV draws a page title over the content as it scrolls.
                Text("Reviews").font(.sectionTitle)
                #else
                // The pushed list has "Reviews" as its page title already.
                if !showsAll {
                    Text("Reviews").font(.sectionTitle)
                }
                #endif
                if isOnTMDB {
                    ForEach(Array(reviews.prefix(showsAll ? reviews.count : previewCount))) { review in
                        ReviewPreview(review: review)
                        Divider()
                    }
                    if loading {
                        ProgressView("Loading reviews…")
                    } else if let failure {
                        Text(failure).font(.metaLine).foregroundStyle(.secondary)
                        if !pageOffersRetry {
                            Button("Retry reviews") { Task { await loadPage() } }
                                .font(.metaLine)
                        }
                    } else if !showsAll && (reviews.count > previewCount || nextPage <= totalPages) {
                        #if os(tvOS)
                        NavigationLink("All reviews") { ReviewListView(preview: preview) }
                        #else
                        // A row with a chevron rather than bare text.
                        NavigationLink { ReviewListView(preview: preview) } label: {
                            HStack {
                                Text("All reviews")
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .font(.synopsis)
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        #endif
                    } else if showsAll && nextPage <= totalPages {
                        Button("More reviews") { Task { await loadPage() } }
                    } else if reviews.isEmpty {
                        Text("No English member reviews on TMDB yet.")
                            .font(.metaLine).foregroundStyle(.secondary)
                    }
                } else {
                    // Rather than a bare heading.
                    Text("TMDB has no member reviews for this title.")
                        .font(.metaLine).foregroundStyle(.secondary)
                }
            }
            .readingWidth()
            .padding(.horizontal, Metrics.gutter)
            #if os(tvOS)
            // "All reviews" sits at the left; without this, Down from the end of a row above skips it.
            .focusSection()
            #endif
            .task(id: requestKey) {
                // This also runs on returning from a pushed page. Starting over then would remove
                // the link that was opened, and focus would fall back to Play on tvOS.
                if requestKey != activeRequestKey {
                    activeRequestKey = requestKey
                    reviews = []
                    nextPage = 1
                    totalPages = 1
                    failure = nil
                    loading = false
                    isOnTMDB = true
                }
                if tmdb.isConfigured && reviews.isEmpty && nextPage == 1 { await loadPage() }
            }
            .onChange(of: pageRetries) {
                if failure != nil { Task { await loadPage() } }
            }
        }
    }

    @MainActor
    private func loadPage() async {
        guard !loading, tmdb.isConfigured else { return }
        let key = requestKey
        loading = true
        failure = nil
        defer { if key == activeRequestKey { loading = false } }
        do {
            let result = try await tmdb.reviews(imdbID: preview.id, type: preview.type, page: nextPage)
            try Task.checkCancellation()
            guard key == activeRequestKey else { return }
            let existing = Set(reviews.map(\.id))
            reviews += result.reviews.filter { !existing.contains($0.id) }
            totalPages = result.totalPages
            nextPage = result.page + 1
        } catch {
            guard key == activeRequestKey, !Task.isCancelled else { return }
            switch error as? TMDBError {
            case .notFound:
                totalPages = 0
                isOnTMDB = false
            case .unauthorized: failure = "TMDB didn't accept the saved token. Check Settings."
            case .rateLimited: failure = "TMDB is busy. Try again in a few minutes."
            default: failure = "Couldn't load member reviews. Try again."
            }
        }
    }
}

/// A review's first lines, with "Read review" only when they leave some of it out.
private struct ReviewPreview: View {
    let review: TMDBReview
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        // One paragraph: cut at a blank line, a preview kept an empty last line
        // and stood further from "Read review" than the next one.
        let content = review.plainText.replacing(/\s*\n+\s*/, with: " ")
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.author).font(.cardTitle).lineLimit(1)
                if let byline = Self.byline(review) {
                    Text(byline).font(.metaLine).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            // Measured against the unclamped text, as the person page's biography is.
            ReviewBody(content: content)
                .foregroundStyle(.secondary).lineLimit(4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .top) {
                    ReviewBody(content: content)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            // A link that opened the same text would only be a dead end; the full review page
            // has nothing more than the preview for a short one.
            // Both measured: until the preview is laid out, any text at all looked cut.
            if shownHeight > 0 && fullHeight > shownHeight + 1 {
                NavigationLink("Read review") { ReviewDetailView(review: review) }
                    .font(.metaLine)
                    // Several links in a row all read "Read review" to VoiceOver otherwise.
                    .accessibilityLabel("Read review by \(review.author)")
                    .accessibilityInputLabels(["Read review"])
                    .accessibilityIdentifier("Read review")
            }
        }
    }

    /// "8/10 · January 15, 2026": TMDB's ratings are whole numbers, and reviews span years.
    private static func byline(_ review: TMDBReview) -> String? {
        let rating = review.rating.map { "\($0.formatted(.number.precision(.fractionLength(0...1)).locale(.interface)))/10" }
        let date = review.createdAt.flatMap { try? Date($0, strategy: .iso8601) }
            .map { $0.formatted(.dateTime.day().month(.wide).year().locale(.interface)) }
        let parts = [rating, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct ReviewDetailView: View {
    let review: TMDBReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(tvOS)
                // In the page rather than as its title, which the TV draws over the text as it scrolls.
                Text(review.author).font(.sectionTitle)
                #endif
                Text("TMDB member review").font(.metaLine).foregroundStyle(.secondary)
                #if os(tvOS)
                // A paragraph or line per focus stop: as one focusable block, a review taller than the
                // screen had no next stop, so the remote couldn't scroll to its end.
                ForEach(Array(review.plainText.split(separator: /\s*\n\s*/).enumerated()), id: \.offset) { _, paragraph in
                    ReviewBody(content: String(paragraph))
                        .focusable()
                }
                #else
                ReviewBody(content: review.plainText)
                    .textSelection(.enabled)
                #endif
                #if !os(tvOS)
                if let url = review.url { Link("View on TMDB", destination: url) }
                #endif
            }
            #if os(iOS)
            .readingWidth()
            #else
            // At the leading edge: as a narrower centred scroll view, the page behind showed at both sides.
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            .padding(Metrics.gutter)
        }
        .background(Color.canvas)
        .hidingPhoneTabBar()
        .pageTitle(review.author)
    }
}

private struct ReviewListView: View {
    let preview: MetaPreview

    var body: some View {
        ScrollView { ReviewsSection(preview: preview, showsAll: true).padding(.vertical, 24) }
            .background(Color.canvas)
            .hidingPhoneTabBar()
            .pageTitle("Reviews")
    }
}

private struct ReviewBody: View {
    let content: String

    var body: some View {
        Text(LocalizedStringKey(content))
            .font(.synopsis)
            .environment(\.openURL, OpenURLAction { url in
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.user == nil, url.password == nil else { return .discarded }
                return .systemAction
            })
    }
}
