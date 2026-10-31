import Foundation
import Testing
@testable import MediaCore

struct StreamDetailsTests {
    @Test func readsAnAIOStreamsStyleRemux() {
        let details = StreamDetails(text: """
            [RD+] AIOStreams 2160p
            🎞️ BluRay REMUX 📺 DV HDR10 🎧 Atmos TrueHD 7.1
            📦 58.2 GB
            Movie.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.TrueHD.7.1.Atmos-GROUP.mkv
            """)

        #expect(details.resolution == .ultraHD)
        #expect(details.dynamicRange == ["Dolby Vision", "HDR10"])
        #expect(details.codec == "HEVC")
        #expect(details.audio == ["Atmos", "TrueHD", "7.1"])
        #expect(details.source == "Remux")
        #expect(details.size == Measurement(value: 58.2, unit: .gigabytes))
        #expect(details.isCached == true)
        #expect(details.picture == "4K · Dolby Vision · HDR10 · HEVC")
    }

    @Test func readsATorrentioStyleWebRelease() {
        let details = StreamDetails(text: """
            [RD download] Torrentio
            1080p
            Show.S01E02.1080p.WEB-DL.DDP5.1.H.264-GROUP
            👤 120 💾 2,4 GB ⚙️ ThePirateBay
            """)

        #expect(details.resolution == .fullHD)
        #expect(details.dynamicRange.isEmpty)
        #expect(details.codec == "AVC")
        #expect(details.audio == ["Dolby Digital Plus", "5.1"])
        #expect(details.source == "WEB-DL")
        #expect(details.size == Measurement(value: 2.4, unit: .gigabytes))
        #expect(details.isCached == false)
    }

    @Test func tellsHDR10PlusFromHDR10() {
        #expect(StreamDetails(text: "2160p HDR10+ x265").dynamicRange == ["HDR10+"])
        #expect(StreamDetails(text: "2160p HDR x265").dynamicRange == ["HDR10"])
    }

    @Test func leavesUnknownsEmpty() {
        let details = StreamDetails(text: "Debrid\nSome file")
        #expect(details.resolution == nil)
        #expect(details.picture == nil)
        #expect(details.file == nil)
        #expect(details.isCached == nil)
    }

    @Test func doesNotMistakeWordsForTags() {
        // "DV" and "SD" inside other words, and "uncached", shouldn't count.
        let details = StreamDetails(text: "Advent.Wisdom.Uncached.mkv")
        #expect(details.dynamicRange.isEmpty)
        #expect(details.resolution == nil)
        #expect(details.isCached == false)
    }

    @Test func sortsByResolutionThenCacheThenSize() {
        let small4K = StreamDetails(text: "2160p 10 GB")
        let big4K = StreamDetails(text: "2160p 40 GB")
        let cached1080 = StreamDetails(text: "[RD+] 1080p 2 GB")
        let uncached1080 = StreamDetails(text: "[RD download] 1080p 20 GB")
        let unknown = StreamDetails(text: "file")

        let sorted = [unknown, uncached1080, small4K, cached1080, big4K].sorted(by: StreamDetails.bestFirst)
        #expect(sorted == [big4K, small4K, cached1080, uncached1080, unknown])
    }
}
