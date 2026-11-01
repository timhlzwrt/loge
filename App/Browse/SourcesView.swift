import MediaCore
import SwiftUI

/// A movie or episode whose sources should be listed.
struct SourcesRoute: Hashable, Identifiable {
    let item: WatchItem
    /// "Lanterns · S1 E2", shown as the screen and player title.
    let title: String
    /// Start playing straight away with the source last used for this title, if there is
    /// one, rather than waiting for a choice. The list stays underneath as a fallback.
    var autoplay = false
    /// The movie's or series' listed runtime in seconds, to estimate bitrates from file sizes.
    var runtime: TimeInterval?

    var type: String { item.type }
    var id: String { item.id }
}

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
    @State private var results: [StreamProvider.ID: Result<[StreamSource], Error>] = [:]
    @State private var hasAutoplayed = false
    @State private var playedAutomatically = false
    @State private var sourceOrder = StreamDetails.SortOrder.cachedFirst
    @State private var secondaryOrder = StreamDetails.SortOrder.addonOrder
    @State private var maximumBitrate = 0
    #if os(macOS)
    @State private var selectedID: Entry.ID?
    #endif
    /// Chosen in the sheet, to play once it has closed.
    @State private var pendingPlay: Entry?
    @Environment(PlaybackSession.self) private var playback

    var body: some View {
        let providers = store.addons.streamProviders(type: route.type, id: route.id)
        Group {
            if providers.isEmpty {
                ContentUnavailableView(
                    "No stream addons",
                    systemImage: "play.slash",
                    description: Text("Install an addon that provides streams in Settings.")
                )
            } else {
                content(providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        #if !os(tvOS)
        .navigationTitle(route.title)
        #endif
        .task {
            playRememberedSourceIfPossible()
            await load(providers)
            if playedAutomatically, let current = playback.current, current.item?.id == route.id {
                playback.offerFallbacks(fallbacks(for: current), for: current)
            }
            playContinuingSourceIfPossible()
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
    private func count(_ groups: [SourceGroup]) -> String? {
        let count = groups.reduce(0) { $0 + $1.entries.count }
        return count == 0 ? nil : "\(count) \(count == 1 ? "source" : "sources")"
    }

    #if os(tvOS)
    /// The title over its dimmed backdrop on the left, the list on the right.
    private func tvLayout(_ groups: [SourceGroup], providers: [StreamProvider]) -> some View {
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
    private func phoneSheet(_ groups: [SourceGroup], providers: [StreamProvider]) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                VStack(spacing: 1) {
                    Text(route.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let count = count(groups) {
                        Text(count)
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
    private func macSheet(_ groups: [SourceGroup], providers: [StreamProvider]) -> some View {
        let selected = selectedID ?? lastPlayedID(in: groups) ?? groups.first?.entries.first?.id
        let entry = groups.lazy.flatMap(\.entries).first { $0.id == selected }
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Choose a Source")
                    .font(.headline)
                Text([route.title, count(groups)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            ScrollView {
                list(groups, providers: providers, selectedID: selected)
                    .padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    // The Mac fills glass buttons with the tint, which is white app-wide.
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
    }
    #endif

    // MARK: List

    /// The groups and the loading, failure and empty states around them.
    @ViewBuilder
    private func list(_ groups: [SourceGroup], providers: [StreamProvider], selectedID: Entry.ID? = nil) -> some View {
        let lastPlayed = lastPlayedID(in: groups)
        let failed = providers.filter { if case .failure = results[$0.id] { true } else { false } }
        let isLoading = providers.contains { results[$0.id] == nil }
        ListContainer {
            sourceOptions
            if maximumBitrate > 0 {
                Text("Up to \(maximumBitrate) Mbps, estimated from the size where not reported. Unknown bitrates stay visible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if route.autoplay && !hasAutoplayed && library.sources[route.item.metaID] != nil {
                Text("Starting with your last source…")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                SourceGroupView(title: group.title) {
                    ForEach(group.entries) { entry in
                        row(entry, isLastPlayed: entry.id == lastPlayed, isSelected: entry.id == selectedID)
                    }
                }
            }
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if !failed.isEmpty {
                HStack {
                    Text(groups.isEmpty ? "Couldn't load sources." : "Some sources couldn't be loaded.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        for provider in failed { results[provider.id] = nil }
                        Task { await load(failed) }
                    }
                }
            }
            if groups.isEmpty && !isLoading && failed.isEmpty {
                Text(maximumBitrate > 0 ? "No sources match this bitrate limit." : "No sources found.")
                    .foregroundStyle(.secondary)
            }
        }
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
            Label("Sort & Filter", systemImage: "line.3.horizontal.decrease")
                .frame(minHeight: 44)
        }
        .accessibilityValue("\(sourceOrder.rawValue), then \(secondaryOrder.rawValue), \(maximumBitrate == 0 ? "any bitrate" : "up to \(maximumBitrate) Mbps")")
    }

    @ViewBuilder
    private func row(_ entry: Entry, isLastPlayed: Bool, isSelected: Bool) -> some View {
        let label = StreamRow(entry: entry, isLastPlayed: isLastPlayed)
        #if os(macOS)
        if isChoosing {
            // Click selects and double-click plays, as in a Mac list; Play plays the selection.
            label
                .background(isSelected ? Color.white.opacity(0.12) : .clear)
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

    private func choose(_ entry: Entry) {
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

    fileprivate struct Entry: Identifiable {
        let id: String
        let stream: StreamSource
        let provider: StreamProvider
        let details: StreamDetails
    }

    fileprivate struct SourceGroup: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    /// Resolution stays explicit; sorting and the optional bitrate cap apply within it.
    private func groups(_ providers: [StreamProvider]) -> [SourceGroup] {
        let entries = providers.flatMap { provider -> [Entry] in
            guard case .success(let streams) = results[provider.id] else { return [] }
            return streams.enumerated()
                .filter { $0.element.playbackURL != nil }
                .map { Entry(id: "\(provider.id)#\($0.offset)", stream: $0.element, provider: provider, details: details($0.element)) }
                .filter { withinBitrateLimit($0.details) }
        }
        let listed = StreamDetails.listedResolutions
        let buckets = listed.map { resolution in
            SourceGroup(title: resolution.label, entries: entries.filter { $0.details.resolution == resolution })
        } + [SourceGroup(title: "Other", entries: entries.filter { entry in !listed.contains { $0 == entry.details.resolution } })]
        let orders = [sourceOrder, secondaryOrder]
        return buckets.filter { !$0.entries.isEmpty }.map { group in
            let sorted = group.entries.enumerated().sorted { lhs, rhs in
                if StreamDetails.SortOrder.precedes(lhs.element.details, rhs.element.details, by: orders) { return true }
                if StreamDetails.SortOrder.precedes(rhs.element.details, lhs.element.details, by: orders) { return false }
                return lhs.offset < rhs.offset
            }
            return SourceGroup(title: group.title, entries: sorted.map(\.element))
        }
    }

    /// The length of the file as last played here beats the listed runtime, which is rounded.
    private func details(_ stream: StreamSource) -> StreamDetails {
        let played = library.progress[route.id].flatMap { $0.isEstimated == true ? nil : $0.duration }
        return StreamDetails(stream, runtime: played ?? route.runtime)
    }

    /// Unknown bitrates pass, so a limit never hides sources that just don't say.
    private func withinBitrateLimit(_ details: StreamDetails) -> Bool {
        maximumBitrate == 0 || (details.listedBitrate ?? 0) <= Double(maximumBitrate) * 1_000_000
    }

    /// The remembered source: the same file, or for another episode the same release.
    private func lastPlayedID(in groups: [SourceGroup]) -> Entry.ID? {
        guard let remembered = library.sources[route.item.metaID] else { return nil }
        let entries = groups.flatMap(\.entries)
        let sameFile = entries.first { $0.stream.playbackURL == remembered.url }
        let sameRelease = entries.first {
            remembered.bingeGroup != nil && $0.provider.id == remembered.providerURL
                && $0.stream.behaviorHints?.bingeGroup == remembered.bingeGroup
        }
        return (sameFile ?? sameRelease)?.id
    }

    private func load(_ providers: [StreamProvider]) async {
        let route = route
        await withTaskGroup(of: (StreamProvider.ID, Result<[StreamSource], Error>).self) { group in
            for provider in providers where results[provider.id] == nil {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.streams(type: route.type, id: route.id)))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                results[id] = result
            }
        }
    }

    /// Resuming the item last played: its stream URL is already known.
    private func playRememberedSourceIfPossible() {
        // Limited series need fresh metadata because remembered URLs don't retain file sizes.
        guard maximumBitrate == 0,
              route.type != "series" || PlaybackPreferences.maximumAutomaticFileSize == 0,
              route.autoplay, !hasAutoplayed, let remembered = library.sources[route.item.metaID],
              remembered.itemID == route.id
        else { return }
        hasAutoplayed = true
        playedAutomatically = true
        playback.start(PlaybackRequest(
            title: route.title, url: remembered.url, headers: remembered.headers, item: route.item,
            startAt: library.resumePosition(for: route.id),
            providerURL: remembered.providerURL, bingeGroup: remembered.bingeGroup
        ))
    }

    /// Another episode of a series: the same addon's stream in the same binge group.
    private func playContinuingSourceIfPossible() {
        guard route.autoplay, !hasAutoplayed, let remembered = library.sources[route.item.metaID],
              case .success(let streams) = results[remembered.providerURL],
              let stream = streams.first(where: {
                  remembered.itemID == route.id && $0.playbackURL == remembered.url && permitsAutomaticPlayback($0)
              }) ?? StreamSource.continuing(bingeGroup: remembered.bingeGroup, in: streams.filter(permitsAutomaticPlayback)),
              let provider = store.addons.streamProviders(type: route.type, id: route.id)
                .first(where: { $0.id == remembered.providerURL })
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

    /// What to try if `request` doesn't open: the same release and quality first, then
    /// the rest in the user's addon order. Only a few, so a dead account doesn't spend
    /// minutes working through every link.
    private func fallbacks(for request: PlaybackRequest) -> [PlaybackRequest] {
        let all = store.addons.streamProviders(type: route.type, id: route.id).flatMap { provider in
            guard case .success(let streams) = results[provider.id] else { return [PlaybackRequest]() }
            return streams.filter(permitsAutomaticPlayback).compactMap { self.request(for: $0, from: provider) }
        }
        let others = all.filter { $0.url != request.url }
        let sameGroup = others.filter { request.bingeGroup != nil && $0.bingeGroup == request.bingeGroup }
        let rest = others.filter { request.bingeGroup == nil || $0.bingeGroup != request.bingeGroup }
        return Array((sameGroup + rest).prefix(3))
    }

    private func permitsAutomaticPlayback(_ stream: StreamSource) -> Bool {
        let details = details(stream)
        return withinBitrateLimit(details)
            && details.permitsAutomaticPlayback(type: route.type, maximumFileSize: PlaybackPreferences.maximumAutomaticFileSize)
    }
}

/// A resolution's heading and its rows, on a rounded panel except on tvOS, where the
/// rows are focus targets of their own.
private struct SourceGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        Section {
            content
        } header: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        rows[index]
                    }
                }
            }
            .background(.white.opacity(0.07), in: .rect(cornerRadius: Self.radius))
            .clipShape(.rect(cornerRadius: Self.radius))
        }
        #endif
    }

    #if os(macOS)
    private static var radius: CGFloat { 12 }
    #else
    private static var radius: CGFloat { 20 }
    #endif
}

/// One source: the release type, then codec, HDR and audio, with the size on the right.
/// Files the debrid service doesn't hold yet are dimmed, since they usually stall.
private struct StreamRow: View {
    let entry: SourcesView.Entry
    let isLastPlayed: Bool

    var body: some View {
        let details = entry.details
        let isCold = details.isCached == false
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(titleFont)
                    .lineLimit(1)
                if let summary = [details.summary, isCold ? "not cached" : nil].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(summary)
                        .font(summaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if details.bitrateLabel != nil || details.sizeLabel != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let bitrate = details.bitrateLabel {
                        Text(bitrate)
                            .accessibilityLabel(details.bitrate == nil ? "about \(bitrate.dropFirst())" : bitrate)
                    }
                    if let size = details.sizeLabel { Text(size) }
                }
                .font(sizeFont.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            }
            Image(systemName: "checkmark")
                .font(sizeFont.weight(.semibold))
                .frame(width: 18)
                .opacity(isLastPlayed ? 1 : 0)
                .accessibilityLabel("Last played")
                .accessibilityHidden(!isLastPlayed)
        }
        .opacity(isCold ? 0.45 : 1)
        #if !os(tvOS)
        .padding(.horizontal, 16)
        .frame(minHeight: rowHeight)
        #endif
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The release type, the resolution when that's all an addon says, or the addon's own
    /// name line for streams none of the tags fit.
    private var title: String {
        let details = entry.details
        return details.releaseType ?? (details.summary != nil ? details.resolution?.label : nil)
            ?? entry.stream.cleanName?.components(separatedBy: .newlines).joined(separator: " ")
            ?? "Source"
    }

    #if os(tvOS)
    private let titleFont = Font.headline
    private let summaryFont = Font.caption
    private let sizeFont = Font.callout
    #elseif os(macOS)
    private let titleFont = Font.body.weight(.semibold)
    private let summaryFont = Font.subheadline
    private let sizeFont = Font.body
    private let rowHeight: CGFloat = 50
    #else
    private let titleFont = Font.callout.weight(.semibold)
    private let summaryFont = Font.footnote
    private let sizeFont = Font.subheadline
    private let rowHeight: CGFloat = 60
    #endif
}

/// Stacks the groups on a phone or Mac; on tvOS they are already inside a `List`.
private struct ListContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        content
        #else
        VStack(alignment: .leading, spacing: 24) { content }
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
