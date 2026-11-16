import Foundation
import Testing
@testable import LogeCore

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

    @Test func recommendsTheBestSourceTheConnectionKeepsUpWith() {
        let sources = [
            StreamDetails(text: "[RD+] 2160p REMUX\nOverall: 60 Mbps"),
            StreamDetails(text: "[RD download] 2160p WEB-DL\nOverall: 18 Mbps"),
            StreamDetails(text: "[RD+] 2160p WEB-DL\nOverall: 16 Mbps"),
            StreamDetails(text: "[RD+] 2160p WEB-DL\nOverall: 12 Mbps"),
            StreamDetails(text: "[RD+] 1080p BluRay\nOverall: 20 Mbps"),
            StreamDetails(text: "[RD+] 2160p WEB-DL"),
        ]
        // 30 Mbps leaves 22.5 for the file: the cached 4K files under that, the larger first.
        #expect(StreamDetails.recommendedIndex(in: sources, connectionSpeed: 30_000_000) == 2)
        // Too slow for any 4K file here.
        #expect(StreamDetails.recommendedIndex(in: sources, connectionSpeed: 15_000_000) == nil)
        #expect(StreamDetails.recommendedIndex(in: sources, connectionSpeed: 18_000_000) == 3)
    }

    @Test func recommendsNothingWhenEverySourceFits() {
        let sources = [StreamDetails(text: "1080p\nOverall: 8 Mbps"), StreamDetails(text: "720p\nOverall: 4 Mbps")]
        #expect(StreamDetails.recommendedIndex(in: sources, connectionSpeed: 100_000_000) == nil)
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

    @Test func preservesBinaryFileSizeUnits() {
        #expect(StreamDetails(text: "1 MiB").size?.converted(to: .bytes).value == 1_048_576)
        #expect(StreamDetails(text: "1 GiB").size?.converted(to: .bytes).value == 1_073_741_824)
        #expect(StreamDetails(text: "1 TiB").size?.converted(to: .bytes).value == 1_099_511_627_776)
    }

    @Test func readsExplicitBitrateUnitsWithoutEstimatingFromSizes() {
        #expect(StreamDetails(text: "HEVC · 25.5 Mbps · 633 GB Season Pack").bitrate == 25_500_000)
        #expect(StreamDetails(text: "Bitrate: 12,4 Mbit/s").bitrate == 12_400_000)
        #expect(StreamDetails(text: "Video: 8500 kbps").bitrate == 8_500_000)
        #expect(StreamDetails(text: "1.2 Gb/s").bitrate == 1_200_000_000)
        #expect(StreamDetails(text: "25 MBps · 4K · 58 GB").bitrate == nil)
        #expect(StreamDetails(text: "2160p 633 GB 60 minutes").bitrate == nil)
        #expect(StreamDetails(text: "Bitrate: 0 Mbps").bitrate == nil)
        #expect(StreamDetails(text: "Bitrate: -25 Mbps").bitrate == nil)
    }

    @Test func doesNotReportAudioOrConflictingRatesAsTheVideoBitrate() {
        #expect(StreamDetails(text: "Audio: AAC 640 kbps").bitrate == nil)
        #expect(StreamDetails(text: "AAC 640 kbps").bitrate == nil)
        #expect(StreamDetails(text: "DTS-HD MA 5.1 1500 kbps").bitrate == nil)
        #expect(StreamDetails(text: "Video: HEVC 25 Mbps AAC").bitrate == 25_000_000)
        #expect(StreamDetails(text: "Video: 25 Mbps\nAudio: AAC 640 kbps").bitrate == 25_000_000)
        #expect(StreamDetails(text: "Video: 25 Mbps · overall 26 Mbps").bitrate == nil)
        #expect(StreamDetails(text: "25 Mbps\n25 Mbps").bitrate == 25_000_000)
    }

    @Test func readsLanguagesFromFlagsOnly() {
        #expect(StreamDetails(text: "🇬🇧 🇩🇪 🇬🇧 🇺🇸").languages == ["en", "de"])
        #expect(StreamDetails(text: "Multi Audio / 🇮🇹").languages == ["it"])
        // A language named in the title says nothing about the audio.
        #expect(StreamDetails(text: "The.French.Dispatch.2021.1080p").languages.isEmpty)
        #expect(StreamDetails(text: "Multi 🌐").languages.isEmpty)
    }

    @Test func tellsSDRFromAPictureNobodyDescribed() {
        #expect(StreamDetails(text: "2160p DV HDR10").isHDR == true)
        #expect(StreamDetails(text: "HLG").isHDR == true)
        #expect(StreamDetails(text: "1080p WEB-DL").isHDR == false)
        #expect(StreamDetails(text: "SDR").isHDR == false)
        #expect(StreamDetails(text: "Stream 2 · 4 GB").isHDR == nil)
    }

    @Test func comparesBitratesWithTheLimitAndLeavesUnknownOnesOpen() {
        #expect(StreamDetails(text: "50 Mbps").isWithin(maximumBitrate: 50) == true)
        #expect(StreamDetails(text: "50.1 Mbps").isWithin(maximumBitrate: 50) == false)
        #expect(StreamDetails(text: "633 GB Season Pack").isWithin(maximumBitrate: 50) == nil)
        #expect(StreamDetails(text: "900 Mbps").isWithin(maximumBitrate: 0) == true)
    }

    private func stream(_ json: String) throws -> StreamSource {
        try JSONDecoder().decode(StreamSource.self, from: Data(json.utf8))
    }

    @Test func estimatesAMovieBitrateFromItsSizeAndRuntime() throws {
        // 18 GB over two hours.
        let details = StreamDetails(try stream(#"{"title":"Movie 2160p HEVC 18 GB"}"#), runtime: 7200)
        #expect(details.bitrate == nil)
        #expect(details.estimatedBitrate == 20_000_000)
        #expect(details.listedBitrate == 20_000_000)
        #expect(details.bitrateLabel == "≈20 Mbps")
    }

    @Test func estimatesAnEpisodeBitrateFromItsOwnVideoSize() throws {
        let details = StreamDetails(
            try stream(#"{"title":"Show Season Pack 633 GB", "behaviorHints":{"videoSize":2700000000}}"#),
            runtime: 45 * 60)
        #expect(details.estimatedBitrate == 8_000_000)
        #expect(details.bitrateLabel == "≈8 Mbps")
    }

    @Test func doesNotEstimateFromPacksOrWithoutARuntime() throws {
        #expect(StreamDetails(try stream(#"{"title":"Show 1080p Season Pack 60 GB"}"#), runtime: 2700).estimatedBitrate == nil)
        #expect(StreamDetails(try stream(#"{"title":"Movie 1080p 10 GB"}"#)).estimatedBitrate == nil)
        #expect(StreamDetails(try stream(#"{"title":"Movie 1080p 10 GB"}"#), runtime: 0).estimatedBitrate == nil)
        #expect(StreamDetails(try stream(#"{"title":"Movie 1080p"}"#), runtime: 7200).estimatedBitrate == nil)
        // A whole season that isn't labelled as a pack can't be one episode's rate.
        #expect(StreamDetails(try stream(#"{"title":"Show 2160p 633 GB"}"#), runtime: 2700).estimatedBitrate == nil)
        // Nor can a 30 MB sample be a two-hour film.
        #expect(StreamDetails(try stream(#"{"title":"Movie 1080p 30 MB"}"#), runtime: 7200).estimatedBitrate == nil)
    }

    @Test func prefersTheReportedBitrateOverAnEstimate() throws {
        let details = StreamDetails(try stream(#"{"title":"Movie 2160p 25 Mbps 18 GB"}"#), runtime: 7200)
        #expect(details.bitrate == 25_000_000)
        #expect(details.estimatedBitrate == nil)
        #expect(details.listedBitrate == 25_000_000)
        #expect(details.bitrateLabel == "25 Mbps")
    }

    @Test func capsEstimatedAndReportedBitratesAlike() throws {
        // 9 GB over two hours is 10 Mbps.
        #expect(StreamDetails(try stream(#"{"title":"4K 9 GB"}"#), runtime: 7200).isWithin(maximumBitrate: 10) == true)
        #expect(StreamDetails(try stream(#"{"title":"4K 30 Mbps"}"#), runtime: 7200).isWithin(maximumBitrate: 25) == false)
    }

    @Test func usesIndividualVideoSizeInsteadOfSeasonPackTotal() throws {
        let stream = try JSONDecoder().decode(StreamSource.self, from: Data("""
            {"title":"Show Season Pack 633 GB", "behaviorHints":{"videoSize":8000000000}}
            """.utf8))
        let details = StreamDetails(stream)
        #expect(details.size?.converted(to: .bytes).value == 8_000_000_000)
        #expect(!details.isPackageSize)
    }

    @Test func labelsPackTotalsWithoutRankingThemAsLargeVideoFiles() {
        let pack = StreamDetails(text: "2160p Season Pack 633 GB")
        let episode = StreamDetails(text: "2160p S01E02 8 GB")
        #expect(pack.isPackageSize)
        #expect(pack.sizeLabel?.hasSuffix(" pack") == true)
        #expect(!episode.isPackageSize)
        let ambiguous = StreamDetails(text: "Episode 8 GB · Season Pack 633 GB")
        #expect(!ambiguous.isPackageSize)
        #expect(ambiguous.size == nil)
    }
}
