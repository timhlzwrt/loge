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
    /// Audio and picture are chosen per list; the bitrate is the setting, so it carries over.
    @State private var audioLanguage: String?
    @State private var picture = SourceSelection.Filter.Picture.any
    @AppStorage(SyncedSettings.Key.maximumBitrate) private var maximumBitrate = SyncedSettings().maximumBitrate
    /// One addon's sources at a time unless combined; the one picked last, on this device.
    @AppStorage([StreamProvider].chosenAddonKey) private var chosenAddon: String?
    @AppStorage(SyncedSettings.Key.combinesAddonSources) private var combinesAddonSources = false
    /// Show all lifts the bitrate limit for this list without changing the setting.
    @State private var ignoresBitrateLimit = false
    /// Synced like the bitrate limit, and lifted by Show all the same way.
    @AppStorage(SyncedSettings.Key.cachedOnly) private var cachedOnly = false
    @State private var ignoresCachedOnly = false
    #if os(tvOS)
    @FocusState private var focusedSourceID: ListedSource.ID?
    @State private var initialFocusID: ListedSource.ID?
    @State private var hasPlacedFocus = false
    #endif
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
    /// Started as the list opens, so a resume position from another device is usually in by Play.
    @State private var progressRefresh: Task<Void, Never>?

    var body: some View {
        let providers = chosenProviders
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
        #if os(tvOS)
        // A sheet is a narrow panel there, with Done squeezed against the title; Menu closes this.
        .fullScreenCover(isPresented: $isAddingAddon) {
            NavigationStack { AddonsSettingsView() }
        }
        #else
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
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // An iPhone or iPad sheet keeps the system's plain sheet behind its list.
            if !isPhoneSheet { Color.canvas.ignoresSafeArea() }
        }
        .hidingPhoneTabBar()
        #if !os(tvOS)
        .navigationTitle(route.title)
        #endif
        // Again when the addons change: one installed from the empty state above has to be asked too.
        .task(id: providers.map(\.id)) {
            guard !providers.isEmpty else { return }
            await load(providers)
            // Leaving Sources cancels loading even when a shared prefetched request finishes later.
            guard !Task.isCancelled else { return }
            // Either way the attempt is over; without a match the list is the way forward.
            hasAutoplayed = true
            #if os(tvOS)
            if !hasPlacedFocus {
                let groups = groups(providers)
                if let id = lastPlayedID(in: groups) ?? recommendedID(in: groups) ?? groups.first?.entries.first?.id {
                    initialFocusID = id
                }
            }
            #endif
        }
        .onAppear {
            if progressRefresh == nil { progressRefresh = Task { await playback.refreshProgress() } }
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

    private var isPhoneSheet: Bool {
        #if os(iOS)
        isChoosing
        #else
        false
        #endif
    }

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
            ScrollView { list(groups, providers: providers).padding(.horizontal, Metrics.gutter).padding(.vertical, 8) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu(providers) }
                }
        }
        #endif
    }

    /// "5 found", or "5 of 47 shown" while filtered, once something has loaded.
    private func countLabel(_ groups: [SourceSelection.Group], providers: [StreamProvider]) -> String? {
        let total = listedSources(providers).count
        let shown = groups.reduce(0) { $0 + $1.entries.count }
        guard total > 0 else { return nil }
        return shown == total ? "\(total) found" : "\(shown) of \(total) shown"
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
            ScrollViewReader { proxy in
                List {
                    list(groups, providers: providers)
                }
                .task(id: initialFocusID) {
                    if let initialFocusID { proxy.scrollTo(initialFocusID) }
                }
            }
            .frame(width: 860)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    #endif

    #if os(iOS)
    /// "Sources" over what they're for and how many, with the filters at the other end.
    /// Swiping down closes it, as its grabber shows.
    private func phoneSheet(_ groups: [SourceSelection.Group], providers: [StreamProvider]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sources")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text([route.item.title, route.item.episodeCode, countLabel(groups, providers: providers)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                filterMenu(providers)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 24)
            .padding(.bottom, 8)
            ScrollView {
                list(groups, providers: providers)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The addon and the filters, each a submenu showing its value.
    private func filterMenu(_ providers: [StreamProvider]) -> some View {
        let available = availableProviders
        let marked = Set(listedSources(providers).flatMap(\.details.languages))
        return Menu {
            if available.count > 1, providers.count == 1, let chosen = providers.first {
                addonPicker(available, chosen: chosen).pickerStyle(.menu)
            }
            Group {
                audioPicker(PlaybackPreferences.languages.filter { marked.contains($0.code) })
                picturePicker
                bitratePicker
                cachedPicker
            }
            .pickerStyle(.menu)
        } label: {
            Text("Filter")
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
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
                Text([route.title, countLabel(groups, providers: providers)].compactMap { $0 }.joined(separator: " · "))
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
        let all = listedSources(providers)
        let hidden = all.count - groups.reduce(0) { $0 + $1.entries.count }
        ListContainer {
            #if !os(iOS)
            let available = availableProviders
            filterSentence(all, available: available,
                           chosen: available.count > 1 && providers.count == 1 ? providers.first : nil)
            #endif
            if hidden > 0 && !groups.isEmpty {
                messageRow("\(hidden) \(hidden == 1 ? "source" : "sources") hidden.", button: "Show all", action: showAll)
            }
            // Judged on every source: one the filters hide is still listed, behind Show all.
            if let status = autoplayStatus(providers: providers,
                                           lastPlayed: SourceSelection.remembered(library.sources[route.item.metaID], in: all)?.id) {
                Text(status)
                    .foregroundStyle(.secondary)
            }
            #if os(iOS)
            // What Play starts by itself, then the rest best first, each row saying its resolution.
            let pick = playPick(providers)
            if let pick { picked(pick) }
            VStack(alignment: .leading, spacing: 0) {
                if pick != nil, !groups.isEmpty {
                    Text("Other sources")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
                ForEach(groups) { group in
                    let (shown, isFoldable, isExpanded) = folded(group, keeping: kept)
                    ForEach(shown.filter { $0.id != pick?.id }) { entry in
                        Divider()
                        row(entry, isLastPlayed: entry.id == lastPlayed, isRecommended: entry.id == recommended,
                            isSelected: false)
                    }
                    if isFoldable {
                        Divider()
                        foldButton(group.id, label: isExpanded ? "Show fewer \(group.title)"
                                   : "Show \(group.entries.count - shown.count) more \(group.title)")
                    }
                }
            }
            #else
            ForEach(groups) { group in
                let (shown, isFoldable, isExpanded) = folded(group, keeping: kept)
                SourceGroupView(title: "\(group.title) · \(group.entries.count)") {
                    ForEach(shown) { entry in
                        row(entry, isLastPlayed: entry.id == lastPlayed, isRecommended: entry.id == recommended,
                            isSelected: entry.id == selectedID)
                    }
                    if isFoldable {
                        foldButton(group.id, label: isExpanded ? "Show fewer" : "Show \(group.entries.count - shown.count) more")
                    }
                }
            }
            #endif
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if !failed.isEmpty {
                // Named by host, so the user knows which addon to check.
                let hosts = failed.map { URL(string: $0.manifestURL)?.host() ?? $0.name }
                messageRow("Couldn't load sources from \(hosts.formatted(.list(type: .and).locale(.interface))).", button: "Retry") {
                    retry(failed)
                }
            }
            if groups.isEmpty && !isLoading && failed.isEmpty {
                if hidden > 0 {
                    messageRow("No sources match these filters.", button: "Show all", action: showAll)
                } else {
                    // An aggregator can come back empty when its own sources time out.
                    messageRow("No sources found.", button: "Retry") { retry(providers) }
                }
            }
        }
    }

    private func messageRow(_ message: String, button: String, action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        // A list row with a button focuses as a whole; outside the label, the message
        // would stay white on the focused white row.
        Button(action: action) {
            HStack {
                Text(message).foregroundStyle(.secondary)
                Spacer()
                Text(button)
            }
        }
        #else
        HStack {
            Text(message).foregroundStyle(.secondary)
            Spacer()
            Button(button, action: action)
        }
        #endif
    }

    /// Rows per resolution before the rest fold away; the order already puts cached ones first.
    private static let foldedLength = 5

    /// The rows a resolution shows: the first few unless unfolded, and always those `kept`.
    private func folded(_ group: SourceSelection.Group, keeping kept: Set<ListedSource.ID>)
        -> (shown: [ListedSource], isFoldable: Bool, isExpanded: Bool) {
        let isFoldable = group.entries.count > Self.foldedLength + 2
        let isExpanded = !isFoldable || expandedGroups.contains(group.id)
        let shown = isExpanded ? group.entries : group.entries.enumerated()
            .filter { $0.offset < Self.foldedLength || kept.contains($0.element.id) }
            .map(\.element)
        return (shown, isFoldable, isExpanded)
    }

    /// Stays in place when pressed, so tvOS focus keeps a target while rows appear above it.
    private func foldButton(_ id: SourceSelection.Group.ID, label: String) -> some View {
        Button {
            if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                #if os(macOS)
                .padding(.horizontal, 16)
                #endif
                #if !os(tvOS)
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
        // Still listed but not started (above the bitrate limit): its row reads "Last played".
        guard lastPlayed == nil, case .success = results[remembered.providerURL] else { return nil }
        return "Your last source isn't listed now. Choose one below."
    }

    private func retry(_ providers: [StreamProvider]) {
        for provider in providers { results[provider.id] = nil }
        Task { await load(providers) }
    }

    private var filter: SourceSelection.Filter {
        SourceSelection.Filter(audioLanguage: audioLanguage, picture: picture,
                               maximumBitrate: ignoresBitrateLimit ? 0 : maximumBitrate,
                               cachedOnly: cachedOnly && !ignoresCachedOnly)
    }

    private func showAll() {
        audioLanguage = nil
        picture = .any
        ignoresBitrateLimit = true
        ignoresCachedOnly = true
    }

    #if !os(iOS)
    /// The addon and filters as a sentence whose values are the menus that change them.
    private func filterSentence(_ sources: [ListedSource], available: [StreamProvider], chosen: StreamProvider?) -> some View {
        let marked = Set(sources.flatMap(\.details.languages))
        let languages = PlaybackPreferences.languages.filter { marked.contains($0.code) }
        let filter = filter
        let language = filter.audioLanguage.map { code in languages.first { $0.code == code }?.name ?? code }
        return Sentence.filters {
            Words("Sources")
            if let chosen {
                Words("from")
                Menu { addonPicker(available, chosen: chosen) } label: { TokenLabel(chosen.name) }
                    .accessibilityLabel("Addon")
                    .accessibilityValue(chosen.name)
            }
            if !languages.isEmpty {
                Words("in")
                Menu { audioPicker(languages) } label: { TokenLabel(language ?? "any language") }
                    .accessibilityLabel("Audio")
                    .accessibilityValue(language ?? "Any language")
                Words("and")
            } else {
                Words("in")
            }
            Menu { picturePicker } label: {
                TokenLabel(filter.picture == .hdr ? "HDR" : filter.picture == .sdr ? "SDR" : "any picture")
            }
            .accessibilityLabel("Picture")
            .accessibilityValue(filter.picture == .hdr ? "HDR or Dolby Vision" : filter.picture == .sdr ? "SDR" : "Any picture")
            Words(filter.maximumBitrate == 0 ? ", at" : ", up to")
            Menu { bitratePicker } label: {
                TokenLabel(filter.maximumBitrate == 0 ? "any bitrate" : "\(filter.maximumBitrate) Mbps")
            }
            .accessibilityLabel("Bitrate")
            .accessibilityValue(filter.maximumBitrate == 0 ? "Any bitrate" : "Up to \(filter.maximumBitrate) Mbps")
            Words(",")
            Menu { cachedPicker } label: {
                TokenLabel(filter.cachedOnly ? "cached only" : "cached or not")
            }
            .accessibilityLabel("Cached only")
            .accessibilityValue(filter.cachedOnly ? "On" : "Off")
            Words(".")
        }
        .buttonStyle(TokenButtonStyle())
        .menuStyle(.button)
        .padding(.vertical, 8)
    }
    #endif

    private func addonPicker(_ available: [StreamProvider], chosen: StreamProvider) -> some View {
        Picker("Addon", selection: Binding(get: { chosen.id }, set: { chosenAddon = $0 })) {
            ForEach(available) { Text($0.name).tag($0.id) }
        }
    }

    /// Only the languages the sources mark; nothing when none do.
    @ViewBuilder
    private func audioPicker(_ languages: [(code: String, name: String)]) -> some View {
        if !languages.isEmpty {
            Picker("Audio", selection: $audioLanguage) {
                Text("Any language").tag(String?.none)
                ForEach(languages, id: \.code) { Text($0.name).tag(Optional($0.code)) }
            }
        }
    }

    private var picturePicker: some View {
        Picker("Picture", selection: $picture) {
            Text("Any picture").tag(SourceSelection.Filter.Picture.any)
            Text("HDR or Dolby Vision").tag(SourceSelection.Filter.Picture.hdr)
            Text("SDR").tag(SourceSelection.Filter.Picture.sdr)
        }
    }

    private var bitratePicker: some View {
        Picker("Bitrate", selection: Binding(get: { filter.maximumBitrate },
                                             set: { maximumBitrate = $0; ignoresBitrateLimit = false })) {
            Text("Any bitrate").tag(0)
            ForEach(SyncedSettings.maximumBitrateOptions.filter { $0 > 0 }, id: \.self) {
                Text("\($0) Mbps").tag($0)
            }
        }
    }

    private var cachedPicker: some View {
        Picker("Cached", selection: Binding(get: { filter.cachedOnly },
                                            set: { cachedOnly = $0; ignoresCachedOnly = false })) {
            Text("Cached only").tag(true)
            Text("Cached or not").tag(false)
        }
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
            #if os(tvOS)
            .id(entry.id)
            .focused($focusedSourceID, equals: entry.id)
            .task(id: initialFocusID) {
                // The list must mount the row before the focus engine can select it.
                if !hasPlacedFocus, initialFocusID == entry.id {
                    hasPlacedFocus = true
                    focusedSourceID = entry.id
                }
            }
            #else
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
        let filter = filter
        return SourceSelection.grouped(listedSources(providers).filter { filter.matches($0.details) })
    }

    /// In the user's addon order.
    private func listedSources(_ providers: [StreamProvider]) -> [ListedSource] {
        providers.flatMap { provider -> [ListedSource] in
            guard case .success(let entries) = results[provider.id] else { return [] }
            return entries
        }
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
        let runtime = route.bitrateRuntime(in: library)
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

    private func playContinuingSourceIfPossible() {
        guard route.autoplay, !hasAutoplayed, let source = continuingSource() else { return }
        hasAutoplayed = true
        playedAutomatically = true
        play(source.stream, from: source.provider)
    }

    /// What Play starts by itself: the remembered source as the addon lists it now, the same
    /// file or the same release. Never its saved URL, since a stream host can refuse an old link.
    private func continuingSource() -> ListedSource? {
        guard let remembered = library.sources[route.item.metaID],
              case .success(let entries) = results[remembered.providerURL] else { return nil }
        let allowed = automatic(entries)
        guard let stream = SourceSelection.continuing(remembered, itemID: route.id, in: allowed.map(\.stream))
        else { return nil }
        return allowed.first { $0.stream.playbackURL == stream.playbackURL }
    }

    #if os(iOS)
    /// Play's choice, when its addon is among those listed.
    private func playPick(_ providers: [StreamProvider]) -> ListedSource? {
        continuingSource().flatMap { pick in providers.contains { $0.id == pick.provider.id } ? pick : nil }
    }

    /// Play's choice on its own panel, with Play, so the usual source is one tap away.
    private func picked(_ entry: ListedSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Play picks")
                .font(.footnote)
                .foregroundStyle(.secondary)
            StreamRow(entry: entry, isLastPlayed: false, connectionSpeed: nil)
            Button { choose(entry) } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(16)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 16))
    }
    #endif

    /// After the progress refresh, which waits at most a second, picks the resume position.
    private func play(_ stream: StreamSource, from provider: StreamProvider) {
        let refresh = progressRefresh
        Task {
            await refresh?.value
            guard let request = request(for: stream, from: provider) else { return }
            playback.start(request, fallbacks: fallbacks(for: request))
        }
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

    /// Every addon with streams for the title, in the user's order.
    private var availableProviders: [StreamProvider] {
        store.addons.streamProviders(type: route.type, id: route.id)
    }

    /// The ones listed and played from.
    private var chosenProviders: [StreamProvider] {
        availableProviders.chosen(chosenAddon, combined: combinesAddonSources)
    }

    /// What to try if `request` doesn't open, among the sources allowed to play automatically.
    private func fallbacks(for request: PlaybackRequest) -> [PlaybackRequest] {
        let providers = chosenProviders
        return SourceSelection.fallbacks(for: request.url, bingeGroup: request.bingeGroup,
                                         among: automatic(listedSources(providers)))
            .compactMap { self.request(for: $0.stream, from: $0.provider) }
    }

    /// Always by the setting: the list's filters and Show all only change what's listed.
    private func automatic(_ sources: [ListedSource]) -> [ListedSource] {
        SourceSelection.automatic(sources, maximumBitrate: maximumBitrate, cachedOnly: cachedOnly) { $0.details }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
