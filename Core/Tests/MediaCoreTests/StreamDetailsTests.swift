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
        #expect(details.audio == ["TrueHD", "Atmos", "7.1"])
        #expect(details.releaseType == "Remux")
        #expect(details.size == Measurement(value: 58.2, unit: .gigabytes))
        #expect(details.isCached == true)
        #expect(details.summary == "HEVC · Dolby Vision · TrueHD Atmos 7.1")
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
        #expect(details.audio == ["DD+", "5.1"])
        #expect(details.releaseType == "WEB-DL")
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
        #expect(details.summary == nil)
        #expect(details.sizeLabel == nil)
        #expect(details.isCached == nil)
    }

    @Test func doesNotMistakeWordsForTags() {
        // "DV" and "SD" inside other words, and "uncached", shouldn't count.
        let details = StreamDetails(text: "Advent.Wisdom.Uncached.mkv")
        #expect(details.dynamicRange.isEmpty)
        #expect(details.resolution == nil)
        #expect(details.isCached == false)
    }

    @Test func readsTagsWrittenAgainstChannels() {
        let details = StreamDetails(text: "Show.S02E01.720p.WEBRip.AAC2.0.x264-GROUP 310 MB")
        #expect(details.resolution == .hd)
        #expect(details.releaseType == "WEB")
        #expect(details.audio == ["AAC", "2.0"])
        #expect(details.summary == "AVC · AAC 2.0")
        #expect(StreamDetails(text: "1080p BluRay DTS5.1").audio == ["DTS", "5.1"])
        #expect(StreamDetails(text: "1080p DD5.1").audio == ["DD", "5.1"])
    }

    @Test func namesTheReleaseType() {
        #expect(StreamDetails(text: "Movie.2019.1080p.BluRay.x264").releaseType == "BluRay")
        #expect(StreamDetails(text: "Movie.2019.1080p.BDRip").releaseType == "BluRay")
        #expect(StreamDetails(text: "Show.S01E01.2160p.WEB.H265").releaseType == "WEB")
        #expect(StreamDetails(text: "Show S01E01 WEB DL").releaseType == "WEB-DL")
        #expect(StreamDetails(text: "Website.Story.1080p").releaseType == nil)
    }

    @Test func listsSizesInTheirOwnUnits() {
        #expect(StreamDetails(text: "640 MB").sizeLabel == "640 MB")
        #expect(StreamDetails(text: "1.2 TB").size == Measurement(value: 1.2, unit: .terabytes))
    }

    @Test func sortsLargerFilesFirst() {
        let small = StreamDetails(text: "2160p 10 GB")
        let big = StreamDetails(text: "2160p 40 GB")
        let megabytes = StreamDetails(text: "2160p 900 MB")
        let unknown = StreamDetails(text: "2160p")

        let sorted = [unknown, small, megabytes, big].sorted(by: StreamDetails.largerFirst)
        #expect(sorted == [big, small, megabytes, unknown])
    }
}
