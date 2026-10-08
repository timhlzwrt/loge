import MediaCore
import SwiftUI

struct SearchView: View {
    @Environment(AddonStore.self) private var store
    @State private var query = ""
    @State private var submittedQuery = ""

    var body: some View {
        let sources = store.addons.searchCatalogs
        ScrollView {
            if sources.isEmpty {
                ContentUnavailableView(
                    "No searchable catalogs",
                    systemImage: "magnifyingglass",
                    description: Text("None of your addons supports search.")
                )
            } else if !submittedQuery.isEmpty {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(sources) { CatalogRow(source: $0, search: submittedQuery) }
                }
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .searchable(text: $query, prompt: "Movies and series")
        .task(id: query) {
            // Wait for a pause in typing so each keystroke doesn't query every addon.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            submittedQuery = query.trimmingCharacters(in: .whitespaces)
        }
    }
}
