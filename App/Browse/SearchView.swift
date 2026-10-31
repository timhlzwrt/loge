import MediaCore
import SwiftUI

struct SearchView: View {
    @Environment(AddonStore.self) private var store
    @State private var query = ""
    @State private var submittedQuery = ""
    /// Results per catalog for the current query, filled in as each one answers.
    @State private var resultCounts: [CatalogSource.ID: Int] = [:]
    /// Newest first, one per line.
    @AppStorage("recentSearches") private var recentSearches = ""

    var body: some View {
        let sources = store.addons.searchCatalogs
        ScrollView {
            if sources.isEmpty {
                ContentUnavailableView(
                    "No searchable catalogs",
                    systemImage: "magnifyingglass",
                    description: Text("None of your addons supports search.")
                )
            } else if query.isEmpty {
                recent
            } else if !submittedQuery.isEmpty {
                // Rows with no matches hide themselves, so without this an unsuccessful
                // search would look like it was still loading.
                if resultCounts.count == sources.count && resultCounts.values.allSatisfy({ $0 == 0 }) {
                    ContentUnavailableView.search(text: submittedQuery)
                        .padding(.top, 80)
                }
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(sources) { source in
                        CatalogRow(source: source, search: submittedQuery, onLoaded: { count in
                            resultCounts[source.id] = count
                        })
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        #if os(iOS)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movies and series")
        #else
        .searchable(text: $query, prompt: "Movies and series")
        #endif
        .onSubmit(of: .search) { remember(query) }
        // Opening a result also leaves this screen, which is when a search proved useful.
        .onDisappear { remember(submittedQuery) }
        .task(id: query) {
            // Wait for a pause in typing so each keystroke doesn't query every addon.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed != submittedQuery { resultCounts = [:] }
            submittedQuery = trimmed
        }
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
                    Button("Clear") { recentSearches = "" }
                        #if !os(tvOS)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        #endif
                }
                ForEach(recents, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
        }
    }

    /// Saves a search that found something; ones that didn't aren't worth repeating.
    private func remember(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2, term == submittedQuery, resultCounts.values.contains(where: { $0 > 0 }) else { return }
        let others = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentSearches = ([term] + others).prefix(10).joined(separator: "\n")
    }
}
