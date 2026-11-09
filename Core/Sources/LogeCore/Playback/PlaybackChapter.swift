import Foundation

/// Chapter boundaries supplied by the media file; no timing is inferred from its runtime.
public struct PlaybackChapter: Sendable, Equatable {
    public var title: String
    public var start: Double

    public init(title: String, start: Double) {
        self.title = title
        self.start = start
    }

    public enum SkipKind: String, Sendable {
        case intro = "Skip Intro"
        case recap = "Skip Recap"
        case credits = "Skip Credits"
    }

    public struct Skip: Sendable, Equatable {
        public var kind: SkipKind
        public var end: Double
    }

    /// A skip lands on the frame showing at its end, which starts a little before it; the
    /// offer would otherwise stay up after skipping while paused. Within this many seconds
    /// of the end there's nothing left worth skipping.
    static let skipEndTolerance = 0.5

    /// Only explicitly named segments are skippable. Generic numbered chapters stay untouched.
    public static func skip(at position: Double, chapters: [Self], duration: Double?) -> Skip? {
        guard position.isFinite, position >= 0 else { return nil }
        let ordered = chapters.filter { $0.start.isFinite && $0.start >= 0 }.sorted { $0.start < $1.start }
        guard let index = ordered.lastIndex(where: { $0.start <= position }) else { return nil }
        let title = ordered[index].title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: SkipKind
        switch title {
        case "intro", "opening", "opening credits", "opening titles": kind = .intro
        case "recap", "previously", "previously on": kind = .recap
        case "credits", "end credits", "closing credits", "ending": kind = .credits
        default: return nil
        }
        // A final intro/recap chapter has no reliable end; never skip the entire title.
        let end = index + 1 < ordered.count ? ordered[index + 1].start : (kind == .credits ? duration : nil)
        guard let end, end.isFinite, end - position > skipEndTolerance,
              duration.map({ $0.isFinite && end <= $0 }) ?? true else { return nil }
        return Skip(kind: kind, end: end)
    }
}
