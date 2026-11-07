import LogeCore
import SwiftUI

/// TMDB member reviews, with the existing external sources retained for critics and Letterboxd.
struct ReviewsSection: View {
    let preview: MetaPreview
    var showsAll = false
    @Environment(TMDBAccount.self) private var tmdb
    @State private var reviews: [TMDBReview] = []
    @State private var nextPage = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var failure: String?
    @State private var activeRequestKey = ""

    private var requestKey: String { "\(tmdb.revision):\(preview.type):\(preview.id)" }

    var body: some View {
        if let critics = ReviewLinks.critics(imdbID: preview.id) {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Reviews").font(.sectionTitle)
                if tmdb.isConfigured {
                    Text("TMDB member reviews").font(.metaLine).foregroundStyle(.secondary)
                    ForEach(Array(reviews.prefix(showsAll ? reviews.count : 3))) { review in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(review.author).font(.cardTitle)
                                if let rating = review.rating {
                                    Text("\(rating, specifier: "%.1f")/10").font(.metaLine).foregroundStyle(.secondary)
                                }
                            }
                            ReviewBody(content: review.plainText)
                                .foregroundStyle(.secondary).lineLimit(4)
                            NavigationLink("Read review") { ReviewDetailView(review: review) }
                                .font(.metaLine)
                        }
                        Divider()
                    }
                    if loading {
                        ProgressView("Loading reviews…")
                    } else if let failure {
                        Text(failure).font(.metaLine).foregroundStyle(.secondary)
                        Button("Retry reviews") { Task { await loadPage() } }
                    } else if !showsAll && (reviews.count > 3 || nextPage <= totalPages) {
                        NavigationLink("All member reviews") { ReviewListView(preview: preview) }
                    } else if showsAll && nextPage <= totalPages {
                        Button("More reviews") { Task { await loadPage() } }
                    } else if reviews.isEmpty {
                        Text("No English member reviews on TMDB yet.")
                            .font(.metaLine).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Connect TMDB in Settings to read member reviews here.")
                        .font(.metaLine).foregroundStyle(.secondary)
                }
                #if os(tvOS)
                Text("External review sources for your phone or computer:")
                    .foregroundStyle(.secondary)
                Text("Critics · imdb.com/title/\(preview.id)/externalreviews")
                    .font(.subheadline)
                if ReviewLinks.letterboxd(imdbID: preview.id, type: preview.type) != nil {
                    Text("Letterboxd · letterboxd.com/imdb/\(preview.id)")
                        .font(.subheadline)
                }
                #else
                VStack(spacing: 0) {
                    reviewLink("Critic reviews", source: "IMDb", destination: critics)
                    if let letterboxd = ReviewLinks.letterboxd(imdbID: preview.id, type: preview.type) {
                        Divider()
                        reviewLink("Member reviews", source: "Letterboxd", destination: letterboxd)
                    }
                }
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
            .task(id: requestKey) {
                activeRequestKey = requestKey
                reviews = []
                nextPage = 1
                totalPages = 1
                failure = nil
                loading = false
                if tmdb.isConfigured { await loadPage() }
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
            if error as? TMDBError == .notFound {
                totalPages = 0
            } else {
                failure = error as? TMDBError == .unauthorized
                    ? "TMDB didn't accept the saved token. Check Settings."
                    : "Couldn't load member reviews. Try again."
            }
        }
    }

    #if !os(tvOS)
    /// A row whose arrow says it leaves the app, in place of an underlined link and a note.
    private func reviewLink(_ title: String, source: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(source)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.synopsis)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(source) in your browser")
    }
    #endif
}

private struct ReviewDetailView: View {
    let review: TMDBReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("TMDB member review").font(.metaLine).foregroundStyle(.secondary)
                ReviewBody(content: review.plainText)
                    #if os(tvOS)
                    .focusable()
                    #else
                    .textSelection(.enabled)
                    #endif
                #if !os(tvOS)
                if let url = review.url { Link("View on TMDB", destination: url) }
                #endif
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(Metrics.gutter)
        }
        .background(Color.canvas)
        .navigationTitle(review.author)
    }
}

private struct ReviewListView: View {
    let preview: MetaPreview

    var body: some View {
        ScrollView { ReviewsSection(preview: preview, showsAll: true).padding(.vertical, 24) }
            .background(Color.canvas)
            .navigationTitle("Reviews")
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
