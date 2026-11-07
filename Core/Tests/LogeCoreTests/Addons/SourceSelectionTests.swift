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
        let groups = SourceSelection.grouped([source("a"), source("b", title: "2160p"), source("c", title: "Unknown"), source("d")],
                                             by: [.addonOrder])
        #expect(groups.map(\.title).last == "Other")
        #expect(groups.first?.entries.map(\.id) == ["b"])
        #expect(groups.first { $0.entries.contains { $0.id == "a" } }?.entries.map(\.id) == ["a", "d"])
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
