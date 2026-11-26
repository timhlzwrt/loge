import SwiftUI

/// One sentence: plain words and controls, wrapping between them like running text.
struct Sentence<Content: View>: View {
    private let content: Content
    private let font: Font
    private let fixedWordSpace: CGFloat?
    #if os(tvOS)
    static var defaultFont: Font { .system(size: 38, weight: .semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 10
    #elseif os(macOS)
    static var defaultFont: Font { .system(size: 20, weight: .semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 5
    #else
    static var defaultFont: Font { .title.weight(.semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 7
    #endif

    /// Filters above what they narrow, a size below Settings' sentences.
    static func filters(@ViewBuilder content: () -> Content) -> Sentence {
        #if os(tvOS)
        // Wide enough that a focused value's plate clears the words beside it.
        Sentence(font: .system(size: 31, weight: .semibold), wordSpace: 12, content: content)
        #else
        Sentence(font: .title3.weight(.semibold), wordSpace: 5, content: content)
        #endif
    }

    /// A font other than the default needs its own word space, which scales with the text.
    init(font: Font = defaultFont, wordSpace: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.font = font
        fixedWordSpace = wordSpace
        self.content = content()
    }

    var body: some View {
        let space = fixedWordSpace ?? wordSpace
        SentenceLayout(wordSpace: space, lineSpacing: space * 0.4) { content }
            .font(font)
    }
}

/// Plain words, one layout item each so lines can break between them. VoiceOver skips them:
/// each control's label carries its setting's name.
struct Words: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
            Text(word)
                .layoutValue(key: FollowsWithoutSpace.self, value: word.first.map { ",.".contains($0) } ?? false)
        }
        #if os(iOS)
        // Dimmer than secondary text, so the white values carry the sentence.
        .foregroundStyle(.white.opacity(0.45))
        #else
        .foregroundStyle(.secondary)
        #endif
        .accessibilityHidden(true)
    }
}

/// Punctuation sits against the word before it.
struct FollowsWithoutSpace: LayoutValueKey {
    static let defaultValue = false
}

struct SentenceLayout: Layout {
    let wordSpace: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            // A control longer than a line, such as a long addon name, wraps inside itself.
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            let attached = subview[FollowsWithoutSpace.self]
            var gap = x == 0 || attached ? 0 : wordSpace
            if x > 0, !attached, x + gap + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                gap = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x + gap, y: y), size: size))
            x += gap + size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return (frames, CGSize(width: widest, height: y + lineHeight))
    }
}

/// A value in a sentence: white and underlined among grey words; on Apple TV, black on white
/// under focus, like the app's other focused controls.
struct TokenLabel: View {
    let text: String
    var isWarning = false
    var isUnderlined = true
    /// The value whose page is open beside the sentence, on a wide iPad.
    var isMarked = false
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    init(_ text: String, isWarning: Bool = false, isUnderlined: Bool = true, isMarked: Bool = false) {
        self.text = text
        self.isWarning = isWarning
        self.isUnderlined = isUnderlined
        self.isMarked = isMarked
    }

    var body: some View {
        Text(text)
            .foregroundStyle(isFocused ? Color.black : isWarning ? Color.orange : Color.white)
            .underline(isUnderlined && !isFocused, color: (isWarning ? Color.orange : Color.white).opacity(0.35))
            .padding(.horizontal, 8)
            .background(isFocused ? Color.white : isMarked ? Color.white.opacity(0.14) : Color.clear,
                        in: .rect(cornerRadius: 8))
            .padding(.horizontal, -8)
            .multilineTextAlignment(.leading)
    }
}

struct TokenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect)
    }
}
