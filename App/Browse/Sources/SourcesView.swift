import LogeCore
import SwiftUI

/// Every playable source from the user's stream addons, grouped by resolution.
/// Rows describe the file (release, codec, HDR, audio, bitrate, size) and never name the addon
/// or the file, whose names can carry account details.
struct SourcesView: View {
    let route: SourcesRoute
    /// Shown over the details screen to pick a source, rather than pushed by Play as the
    /// fallback underneath autoplay.
    var isChoosing = false

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// Each addon's playable streams, read into details once as they arrive.
    @State private var results: [StreamProvider.ID: Result<[ListedSource], Error>] = [:]
    @State private var hasAutoplayed = false
    @State private var playedAutomatically = false
    @State private var sourceOrder = StreamDetails.SortOrder.cachedFirst
    @State private var secondaryOrder = StreamDetails.SortOrder.addonOrder
    @State private var maximumBitrate = 0
    #if os(macOS)
    @State private var selectedID: ListedSource.ID?
    @FocusState private var isListFocused: Bool
    #endif
    /// Chosen in the sheet, to play once it has closed.
    @State private var pendingPlay: ListedSource?
    @State private var isAddingAddon = false
    /// Resolution groups showing every row rather than the first few.
    @State private var expandedGroups: Set<SourceSelection.Group.ID> = []
    @AppStorage(ConnectionSpeed.key) private var connectionSpeed = 0.0
    @Environment(PlaybackSession.self) private var playback

    var body: some View {
        let providers = store.addons.streamProviders(type: route.type, id: route.id)
        Group {
            if providers.isEmpty {
                // Installing one here, rather than a pointer to Settings, so the title is still
                // open once there's something to play it with.
                ContentUnavailableView {
                    Label("No playback addons", systemImage: "play.slash")
                } description: {
                    Text("Add a Stremio addon that provides streams to watch \(route.title).")
                } actions: {
                    Button("Add Addon") { isAddingAddon = true }
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(.black)
                    #if os(macOS)
                    // The sheet's only way out otherwise; iOS has its Close button.
                    if isChoosing {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.glass)
                            .tint(.clear)
                    }
                    #endif
                }
                #if os(iOS)
                .overlay(alignment: .topTrailing) {
                    if isChoosing {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .padding([.top, .trailing], 16)
                    }
                }
                #endif
                #if os(macOS)
                .frame(width: isChoosing ? 520 : nil, height: isChoosing ? 360 : nil)
                #endif
            } else {
                content(providers)
            }
        }
        // On the Group, so installing an addon swaps in the list without closing this sheet.
        .sheet(isPresented: $isAddingAddon) {
            NavigationStack {
                AddonsSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isAddingAddon = false }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .hidingPhoneTabBar()
        #if !os(tvOS)
        .navigationTitle(route.title)
        #endif
        // Keyed by the addons, so one added from the empty state is asked too.
        .task(id: providers.map(\.id)) {
            guard !providers.isEmpty else { return }
            await load(providers)
            // Leaving Sources cancels loading even when a shared prefetched request finishes later.
            guard !Task.isCancelled else { return }
            // Either way the attempt is over; without a match the list is the way forward.
            hasAutoplayed = true
        }
        .onDisappear {
            if let entry = pendingPlay { play(entry.stream, from: entry.provider) }
        }
        .onChange(of: playback.current == nil) { _, ended in
            // Playback started straight from Play or Continue Watching passed through
            // this list; ending it goes back to where that tap came from.
            if ended && route.autoplay && playedAutomatically { dismiss() }
        }
    }

    // MARK: Layouts

    @ViewBuilder
    private func content(_ providers: [StreamProvider]) -> some View {
        let groups = groups(providers)
        #if os(tvOS)
        tvLayout(groups, providers: providers)
        #elseif os(macOS)
        if isChoosing {
            macSheet(groups, providers: providers)
        } else {
            ScrollView { list(groups, providers: providers).padding(Metrics.gutter) }
        }
        #else
        if isChoosing {
            phoneSheet(groups, providers: providers)
        } else {
            ScrollView { list(groups, providers: providers).padding(.horizontal, 16).padding(.vertical, 8) }
        }
        #endif
    }

    /// "5 sources", once something has loaded.
    private func countLabel(_ groups: [SourceSelection.Group]) -> String? {
        let count = groups.reduce(0) { $0 + $1.entries.count }
        return count == 0 ? nil : "\(count) \(count == 1 ? "source" : "sources")"
    }

    #if os(tvOS)
    /// The title over its dimmed backdrop on the left, the list on the right.
    private func tvLayout(_ groups: [SourceSelection.Group], providers: [StreamProvider]) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: route.item.background)
                .overlay(Color.black.opacity(0.55))
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .canvas.opacity(0), location: 0.2), .init(color: .canvas, location: 0.6)],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(route.item.title)
                    .font(.system(size: 76, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let subtitle = [route.item.episodeCode, route.item.episodeTitle].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(subtitle)
                        .font(.metaLine)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            List {
                list(groups, providers: providers)
            }
            .frame(width: 860)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    #endif

    #if os(iOS)
    private func phoneSheet(_ groups: [SourceSelection.Group], providers: [StreamProvider]) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                // The episode code goes under the series, where truncating the long name can't cut it off.
                VStack(spacing: 1) {
                    Text(route.item.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let detail = [route.item.episodeCode, countLabel(groups)].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 64)
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, 16)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)
            ScrollView {
                list(groups, providers: providers)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    #endif

    #if os(macOS)
    private func macSheet(_ groups: [SourceSelection.Group], providers: [StreamProvider]) -> some View {
        let selected = selectedID ?? lastPlayedID(in: groups) ?? groups.first?.entries.first?.id
        let entry = groups.lazy.flatMap(\.entries).first { $0.id == selected }
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Choose a Source")
                    .font(.headline)
                Text([route.title, countLabel(groups)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    list(groups, providers: providers, selectedID: selected)
                        .padding(.horizontal, 20)
                }
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    // The Mac fills glass buttons with the tint, the accent app-wide.
                    .tint(.clear)
                Button("Play") {
                    if let entry { choose(entry) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .foregroundStyle(.black)
                .disabled(entry == nil)
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520, height: 600)
        .background(Color.canvas)
        // The arrow keys move the selection, as in a Mac list, so Return can play any row.
        .focusable()
        .focusEffectDisabled()
        .focused($isListFocused)
        .onAppear { isListFocused = true }
        .onMoveCommand { direction in
            let ids = groups.flatMap(\.entries).map(\.id)
            guard let index = selected.flatMap(ids.firstIndex(of:)) else { return }
            switch direction {
            case .up: selectedID = ids[max(index - 1, 0)]
            case .down: selectedID = ids[min(index + 1, ids.count - 1)]
            default: break
            }
        }
    }
    #endif

    // MARK: List

    /// The groups and the loading, failure and empty states around them.
    @ViewBuilder
    private func list(_ groups: [SourceSelection.Group], providers: [StreamProvider], selectedID: ListedSource.ID? = nil) -> some View {
        let lastPlayed = lastPlayedID(in: groups)
        let recommended = recommendedID(in: groups)
        let failed = providers.filter { if case .failure = results[$0.id] { true } else { false } }
        let isLoading = providers.contains { results[$0.id] == nil }
        // Folding never hides the rows the list points out.
        let kept = Set([lastPlayed, recommended, selectedID].compactMap { $0 })
        ListContainer {
            sourceOptions
            if maximumBitrate > 0 {
                Text("Up to \(maximumBitrate) Mbps, estimated from the size where not reported. Unknown bitrates stay visible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let status = autoplayStatus(providers: providers, lastPlayed: lastPlayed) {
                Text(status)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                let isFoldable = group.entries.count > Self.foldedLength + 2
                let isExpanded = !isFoldable || expandedGroups.contains(group.id)
                let shown = isExpanded ? group.entries : group.entries.enumerated()
                    .filter { $0.offset < Self.foldedLength || kept.contains($0.element.id) }
                    .map(\.element)
                SourceGroupView(title: "\(group.title) · \(group.entries.count)") {
                    ForEach(shown) { entry in
                        row(entry, isLastPlayed: entry.id == lastPlayed, isRecommended: entry.id == recommended,
                            isSelected: entry.id == selectedID)
                    }
                    if isFoldable {
                        foldButton(group.id, hidden: group.entries.count - shown.count, isExpanded: isExpanded)
                    }
                }
            }
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if !failed.isEmpty {
                HStack {
                    // Named by host, so the user knows which addon to check.
                    let hosts = failed.map { URL(string: $0.manifestURL)?.host() ?? $0.name }
                    Text("Couldn't load sources from \(hosts.formatted(.list(type: .and).locale(.interface))).")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { retry(failed) }
                }
            }
            if groups.isEmpty && !isLoading && failed.isEmpty {
                if maximumBitrate > 0 {
                    Text("No sources match this bitrate limit.")
                        .foregroundStyle(.secondary)
                } else {
                    // An aggregator can come back empty when its own sources time out.
                    HStack {
                        Text("No sources found.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { retry(providers) }
                    }
                }
            }
        }
    }

    /// Rows per resolution before the rest fold away; the sort already puts the best first.
    private static let foldedLength = 5

    /// Stays in place when pressed, so tvOS focus keeps a target while rows appear above it.
    private func foldButton(_ id: SourceSelection.Group.ID, hidden: Int, isExpanded: Bool) -> some View {
        Button {
            if isExpanded { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        } label: {
            Text(isExpanded ? "Show fewer" : "Show \(hidden) more")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                #if !os(tvOS)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                #endif
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }

    /// What autoplay is waiting for, or that it can't continue, so the list underneath
    /// isn't mistaken for a start that's still coming.
    private func autoplayStatus(providers: [StreamProvider], lastPlayed: ListedSource.ID?) -> String? {
        guard route.autoplay, !playedAutomatically, let remembered = library.sources[route.item.metaID],
              providers.contains(where: { $0.id == remembered.providerURL })
        else { return nil }
        if !hasAutoplayed {
            let host = URL(string: remembered.providerURL)?.host() ?? "your addon"
            return "Waiting for \(host) to start your last source…"
        }
        // Still listed but not started (too large to start by itself): its row reads "Last played".
        guard lastPlayed == nil, case .success = results[remembered.providerURL] else { return nil }
        return "Your last source isn't listed now. Choose one below."
    }

    private func retry(_ providers: [StreamProvider]) {
        for provider in providers { results[provider.id] = nil }
        Task { await load(providers) }
    }

    private var sourceOptions: some View {
        Menu {
            // Submenus, so each list is named; inline, the two sort lists read as one
            // repeated list.
            Group {
                Picker("Sort by", selection: $sourceOrder) {
                    ForEach(StreamDetails.SortOrder.allCases) { order in Text(order.rawValue).tag(order) }
                }
                Picker("Then by", selection: $secondaryOrder) {
                    ForEach(StreamDetails.SortOrder.allCases) { order in Text(order.rawValue).tag(order) }
                }
                Picker("Maximum bitrate", selection: $maximumBitrate) {
                    Text("Any bitrate").tag(0)
                    ForEach([10, 25, 50, 100], id: \.self) { Text("Up to \($0) Mbps").tag($0) }
                }
            }
            .pickerStyle(.menu)
        } label: {
            // Says how the list is ordered now, rather than only that it can be.
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sourceOrder.rawValue)
                if maximumBitrate > 0 {
                    Text("· up to \(maximumBitrate) Mbps")
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Sort & Filter")
        .accessibilityValue("\(sourceOrder.rawValue), then \(secondaryOrder.rawValue), "
                                + (maximumBitrate == 0 ? "any bitrate" : "up to \(maximumBitrate) Mbps"))
    }

    @ViewBuilder
    private func row(_ entry: ListedSource, isLastPlayed: Bool, isRecommended: Bool, isSelected: Bool) -> some View {
        let label = StreamRow(entry: entry, isLastPlayed: isLastPlayed,
                              connectionSpeed: isRecommended ? connectionSpeed : nil)
        #if os(macOS)
        if isChoosing {
            // Click selects and double-click plays, as in a Mac list; Play plays the selection.
            label
                .background(isSelected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear))
                .contentShape(.rect)
                .onTapGesture(count: 2) { choose(entry) }
                .onTapGesture { selectedID = entry.id }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { choose(entry) }
        } else {
            Button { choose(entry) } label: { label }
                .buttonStyle(.plain)
        }
        #else
        Button { choose(entry) } label: { label }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
        #endif
    }

    private func choose(_ entry: ListedSource) {
        guard isChoosing else {
            play(entry.stream, from: entry.provider)
            return
        }
        // The sheet has done its job. The player is presented from the root, which can't
        // happen while this sheet is still going away, so playback waits for it to close.
        pendingPlay = entry
        dismiss()
    }

    // MARK: Data

    private func groups(_ providers: [StreamProvider]) -> [SourceSelection.Group] {
        SourceSelection.grouped(listedSources(providers).filter { withinBitrateLimit($0.details) },
                                by: [sourceOrder, secondaryOrder])
    }

    /// In the user's addon order.
    private func listedSources(_ providers: [StreamProvider]) -> [ListedSource] {
        providers.flatMap { provider -> [ListedSource] in
            guard case .success(let entries) = results[provider.id] else { return [] }
            return entries
        }
    }

    /// Unknown bitrates pass, so a limit never hides sources that just don't say.
    private func withinBitrateLimit(_ details: StreamDetails) -> Bool {
        maximumBitrate == 0 || (details.listedBitrate ?? 0) <= Double(maximumBitrate) * 1_000_000
    }

    /// The best source for the speed playback has measured here; only marked, never played
    /// by itself.
    private func recommendedID(in groups: [SourceSelection.Group]) -> ListedSource.ID? {
        let entries = groups.flatMap(\.entries)
        return StreamDetails.recommendedIndex(in: entries.map(\.details), connectionSpeed: connectionSpeed)
            .map { entries[$0].id }
    }

    private func lastPlayedID(in groups: [SourceSelection.Group]) -> ListedSource.ID? {
        SourceSelection.remembered(library.sources[route.item.metaID], in: groups.flatMap(\.entries))?.id
    }

    private func load(_ providers: [StreamProvider]) async {
        let route = route
        // The length of the file as last played here beats the listed runtime, which is rounded.
        let runtime = library.progress[route.id].flatMap { $0.isEstimated == true ? nil : $0.duration } ?? route.runtime
        let rememberedProvider = library.sources[route.item.metaID]?.providerURL
        await withTaskGroup(of: (StreamProvider.ID, Result<[ListedSource], Error>).self) { group in
            for provider in providers where results[provider.id] == nil {
                group.addTask {
                    do {
                        // Awaited on its own line: wrapped directly in `.success(...)`, the Release
                        // build never delivered the result and the list kept loading.
                        let streams = try await provider.streams(type: route.type, id: route.id)
                        // Read into details once here: in the view body, every redraw re-ran the
                        // tag patterns over every stream, during playback too.
                        let listed = streams.enumerated()
                            .filter { $0.element.playbackURL != nil }
                            .map {
                                ListedSource(id: "\(provider.id)#\($0.offset)", stream: $0.element, provider: provider,
                                             details: StreamDetails($0.element, runtime: runtime))
                            }
                        return (provider.id, .success(listed))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                guard !Task.isCancelled else { return }
                results[id] = result
                // Autoplay needs only the remembered addon, not the slowest of the others.
                if id == rememberedProvider {
                    playContinuingSourceIfPossible()
                    hasAutoplayed = true
                }
            }
        }
    }

    /// The remembered source as the addon lists it now: the same file or the same release.
    /// Never its saved URL, since a stream host can refuse an old link.
    private func playContinuingSourceIfPossible() {
        guard route.autoplay, !hasAutoplayed, let remembered = library.sources[route.item.metaID],
              case .success(let entries) = results[remembered.providerURL],
              let stream = SourceSelection.continuing(
                remembered, itemID: route.id, in: entries.filter { permitsAutomaticPlayback($0.details) }.map(\.stream)),
              let provider = entries.first?.provider
        else { return }
        hasAutoplayed = true
        playedAutomatically = true
        play(stream, from: provider)
    }

    private func play(_ stream: StreamSource, from provider: StreamProvider) {
        guard let request = request(for: stream, from: provider) else { return }
        playback.start(request, fallbacks: fallbacks(for: request))
    }

    private func request(for stream: StreamSource, from provider: StreamProvider) -> PlaybackRequest? {
        guard let url = stream.playbackURL else { return nil }
        return PlaybackRequest(
            title: route.title,
            url: url,
            headers: stream.requestHeaders,
            item: route.item,
            startAt: library.resumePosition(for: route.id),
            providerURL: provider.manifestURL,
            bingeGroup: stream.behaviorHints?.bingeGroup,
            subtitles: stream.subtitles ?? [],
            filename: stream.behaviorHints?.filename
        )
    }

    /// What to try if `request` doesn't open, among the sources allowed to play automatically.
    private func fallbacks(for request: PlaybackRequest) -> [PlaybackRequest] {
        let providers = store.addons.streamProviders(type: route.type, id: route.id)
        let candidates = listedSources(providers).filter { permitsAutomaticPlayback($0.details) }
        return SourceSelection.fallbacks(for: request.url, bingeGroup: request.bingeGroup, among: candidates)
            .compactMap { self.request(for: $0.stream, from: $0.provider) }
    }

    private func permitsAutomaticPlayback(_ details: StreamDetails) -> Bool {
        withinBitrateLimit(details)
            && details.permitsAutomaticPlayback(type: route.type, maximumFileSize: PlaybackPreferences.maximumAutomaticFileSize)
    }
}
