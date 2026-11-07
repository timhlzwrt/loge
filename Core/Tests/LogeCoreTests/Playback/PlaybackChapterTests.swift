import Testing
@testable import LogeCore

struct PlaybackChapterTests {
    @Test func skipsOnlyTheCurrentNamedSegment() {
        let chapters = [PlaybackChapter(title: "Recap", start: 0), .init(title: "Intro", start: 30),
                        .init(title: "Chapter 3", start: 90), .init(title: "End Credits", start: 1_000)]
        #expect(PlaybackChapter.skip(at: 10, chapters: chapters, duration: 1_100) == .init(kind: .recap, end: 30))
        #expect(PlaybackChapter.skip(at: 30, chapters: chapters, duration: 1_100) == .init(kind: .intro, end: 90))
        #expect(PlaybackChapter.skip(at: 100, chapters: chapters, duration: 1_100) == nil)
        #expect(PlaybackChapter.skip(at: 1_010, chapters: chapters, duration: 1_100) == .init(kind: .credits, end: 1_100))
        #expect(PlaybackChapter.skip(at: 1_100, chapters: chapters, duration: 1_100) == nil)
    }

    @Test func requiresKnownBoundariesAndIgnoresInvalidMetadata() {
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Intro", start: 0), .init(title: "", start: 30)], duration: 100) == .init(kind: .intro, end: 30))
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Intro", start: 0)], duration: nil) == nil)
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Intro", start: 0)], duration: 100) == nil)
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Intro", start: 0), .init(title: "Story", start: 200)], duration: 100) == nil)
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Chapter 1", start: 0)], duration: 100) == nil)
        #expect(PlaybackChapter.skip(at: .nan, chapters: [.init(title: "Intro", start: 0)], duration: 100) == nil)
        #expect(PlaybackChapter.skip(at: 5, chapters: [.init(title: "Intro", start: .nan)], duration: 100) == nil)
    }
}
