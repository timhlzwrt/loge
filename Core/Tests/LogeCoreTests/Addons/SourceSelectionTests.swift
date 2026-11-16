import Foundation
import Testing
@testable import LogeCore

struct SourceSelectionTests {
    let addon = StreamProvider(manifestURL: "https://a.example/manifest.json", name: "A")
    let other = StreamProvider(manifestURL: "https://b.example/manifest.json", name: "B")

    func source(_ id: String, title: String = "1080p", binge: String? = nil, from provider: StreamProvider? = nil) -> ListedSource {
        let stream = StreamSource(title: title, url: "https://cdn.example/\(id).mkv",
                                  behaviorHints: binge.map { StreamSource.BehaviorHints(bingeGroup: $0) })
        return ListedSource(id: id, stream: stream, provider: provider ?? addon, details: StreamDetails(stream))
    }

    func remembered(_ id: String, item: String = "tt1", binge: String? = nil) -> RememberedSource {
        RememberedSource(itemID: item, providerURL: addon.manifestURL, url: URL(string: "https://cdn.example/\(id).mkv")!,
                         headers: [:], bingeGroup: binge)
    }

    @Test func groupsByResolutionBestFirstWithOtherLastAndKeepsAddonOrderForTies() {
        let groups = SourceSelection.grouped([source("a"), source("b", title: "2160p"), source("c", title: "Unknown"), source("d")])
        #expect(groups.map(\.title).last == "Other")
        #expect(groups.first?.entries.map(\.id) == ["b"])
        #expect(groups.first { $0.entries.contains { $0.id == "a" } }?.entries.map(\.id) == ["a", "d"])
    }

    @Test func ordersCachedThenUnsaidThenUncachedWithinAResolution() {
        let groups = SourceSelection.grouped([
            source("uncached", title: "[RD download] 1080p"), source("unsaid"), source("cached", title: "[RD+] 1080p"),
            source("cached2", title: "[RD+] 1080p"), source("cached4K", title: "[RD+] 2160p"),
        ])
        #expect(groups.map(\.title) == ["4K", "1080p"])
        #expect(groups[1].entries.map(\.id) == ["cached", "cached2", "unsaid", "uncached"])
    }

    @Test func filtersKeepSourcesThatDontSay() {
        let german = StreamDetails(text: "🇩🇪 1080p 8 Mbps"), english = StreamDetails(text: "🇬🇧 2160p HDR 40 Mbps")
        let unsaid = StreamDetails(text: "Stream 3")
        func kept(_ filter: SourceSelection.Filter) -> [StreamDetails] { [german, english, unsaid].filter(filter.matches) }
        #expect(kept(.init()) == [german, english, unsaid])
        #expect(kept(.init(audioLanguage: "de")) == [german, unsaid])
        #expect(kept(.init(picture: .hdr)) == [english, unsaid])
        #expect(kept(.init(picture: .sdr)) == [german, unsaid])
        #expect(kept(.init(maximumBitrate: 25)) == [german, unsaid])
        #expect(kept(.init(audioLanguage: "en", picture: .sdr)) == [unsaid])
    }

    @Test func automaticPlaybackPrefersKnownBitratesWithinTheLimitAndNeverExceedsIt() {
        let sources = [source("unknown", title: "1080p"), source("high", title: "2160p 80 Mbps"),
                       source("low", title: "1080p 20 Mbps"), source("unknown2", title: "720p")]
        #expect(SourceSelection.automatic(sources, maximumBitrate: 50) { $0.details }.map(\.id) == ["low", "unknown", "unknown2"])
        #expect(SourceSelection.automatic(sources, maximumBitrate: 0) { $0.details }.map(\.id) == ["unknown", "high", "low", "unknown2"])
        // The remembered release continues even when only an unknown-bitrate copy of it is listed.
        let release = [source("other", title: "1080p 20 Mbps"), source("same", title: "1080p", binge: "g"),
                       source("sameHigh", title: "2160p 80 Mbps", binge: "g")]
        let allowed = SourceSelection.automatic(release, maximumBitrate: 50) { $0.details }.map(\.stream)
        #expect(SourceSelection.continuing(remembered("gone", binge: "g"), itemID: "tt1", in: allowed)?.url?.hasSuffix("same.mkv") == true)
    }

    @Test func remembersTheSameFileBeforeTheSameRelease() {
        let sources = [source("release", binge: "g"), source("file")]
        #expect(SourceSelection.remembered(remembered("file", binge: "g"), in: sources)?.id == "file")
        #expect(SourceSelection.remembered(remembered("gone", binge: "g"), in: sources)?.id == "release")
        #expect(SourceSelection.remembered(remembered("gone"), in: sources) == nil)
        #expect(SourceSelection.remembered(nil, in: sources) == nil)
    }

    @Test func continuesWithTheSameFileOnlyForTheSameItem() {
        let streams = [source("next", binge: "g").stream, source("file").stream]
        #expect(SourceSelection.continuing(remembered("file", binge: "g"), itemID: "tt1", in: streams)?.url?.hasSuffix("file.mkv") == true)
        #expect(SourceSelection.continuing(remembered("file", binge: "g"), itemID: "tt2", in: streams)?.url?.hasSuffix("next.mkv") == true)
    }

    @Test func fallbacksPreferTheSameReleaseAndStopAtThree() {
        let sources = [source("failed", binge: "g"), source("x"), source("y", binge: "g", from: other),
                       source("z"), source("w")]
        let fallbacks = SourceSelection.fallbacks(for: URL(string: "https://cdn.example/failed.mkv")!, bingeGroup: "g", among: sources)
        #expect(fallbacks.map(\.id) == ["y", "x", "z"])
    }
}
