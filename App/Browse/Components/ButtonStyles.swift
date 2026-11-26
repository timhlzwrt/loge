import LogeCore
import SwiftUI

/// The one accent-coloured call to action on a screen: Play or Resume. On iPhone and iPad
/// `.controlSize(.small)` draws it a size down, for a title page's centred row. On Apple TV
/// focus decides instead: the focused button is white, the others translucent.
struct PrimaryButtonStyle: ButtonStyle {
    /// Translucent white rather than the accent, for a second choice beside the primary one.
    var isTranslucent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isTranslucent: isTranslucent)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isTranslucent: Bool
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #elseif os(iOS)
        @Environment(\.controlSize) private var controlSize
        #endif

        var body: some View {
            configuration.label
                .font(font)
                .labelStyle(PlayLabelStyle())
                .foregroundStyle(isWhite ? .black : .white)
                .padding(.leading, height * 0.44)
                .padding(.trailing, height * 0.56)
                .frame(minHeight: height)
                .background(isWhite ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(Metrics.isTV ? 0.14 : 0.12)), in: shape)
                .opacity(configuration.isPressed ? 0.8 : 1)
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
        }

        #if os(tvOS)
        private var isWhite: Bool { isFocused }
        private let height: CGFloat = 78
        private let font = Font.system(size: 27, weight: .semibold)
        private let shape = RoundedRectangle(cornerRadius: 20)
        #else
        private var isWhite: Bool { !isTranslucent }
        #endif

        #if os(tvOS)
        #elseif os(macOS)
        private let height: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        private let shape = Capsule()
        #else
        // 44 pt is as small as a button stays comfortable to tap.
        private var height: CGFloat { controlSize == .small ? 44 : 50 }
        /// A phone stretches it across the page, where a capsule reads as a text field.
        private var shape: AnyShape { Metrics.isPhone ? AnyShape(.rect(cornerRadius: 14)) : AnyShape(.capsule) }
        private var font: Font { controlSize == .small ? .subheadline.weight(.semibold) : .headline }
        #endif
    }

    /// A smaller glyph than the text, as in the TV app.
    private struct PlayLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }
}

/// A title's other actions: a circle with its name under it, filled white while it's on
/// (saved to Watch Later, watched). On the Mac and Apple TV a button with icon and name in a
/// row beside Play.
struct RoundButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isOn: isOn)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            #if os(macOS) || os(tvOS)
            PrimaryButtonStyle(isTranslucent: true).makeBody(configuration: configuration)
            #else
            VStack(spacing: 6) {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? .black : .white)
                    .frame(width: 46, height: 46)
                    .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                    // The label is drawn twice; VoiceOver should say the name once.
                    .accessibilityHidden(true)
                configuration.label
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(.easeOut(duration: 0.15), value: isOn)
            #endif
        }
    }
}

/// One of a few choices side by side: seasons, genres, lists, roles. The chosen one is white;
/// on Apple TV the focused one is, and the chosen one keeps a translucent plate.
struct PillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isSelected: isSelected)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isSelected: Bool
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(isWhite ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(isSelected ? 1 : 0.7)))
                .padding(.horizontal, height * 0.4)
                .frame(minHeight: height)
                .background(plate, in: .capsule)
                .opacity(configuration.isPressed ? 0.7 : 1)
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #else
                // 44 pt to tap, without spacing the pills further apart.
                .padding(.vertical, 4)
                .contentShape(.rect)
                #endif
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var plate: AnyShapeStyle {
            isWhite ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(isSelected ? 0.16 : 0.08))
        }

        #if os(tvOS)
        private var isWhite: Bool { isFocused }
        private let height: CGFloat = 56
        private let font = Font.system(size: 24, weight: .semibold)
        #else
        private var isWhite: Bool { isSelected }
        private let height: CGFloat = 36
        private let font = Font.subheadline.weight(.semibold)
        #endif
    }
}

#if !os(tvOS)
/// Round, icon-only Liquid Glass buttons beside the primary one, as Watch Later in the wide
/// featured carousel. Drawn rather than using the `.glass` button style, which pads the circle
/// beyond the primary button's height. They follow `.controlSize(.small)` as that button does.
struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        #if os(iOS)
        @Environment(\.controlSize) private var controlSize
        #endif

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(font)
                .frame(width: size, height: size)
                .contentShape(.circle)
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive(), in: .circle)
        }

        #if os(macOS)
        private let size: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        #else
        private var size: CGFloat { controlSize == .small ? 44 : 50 }
        private var font: Font { controlSize == .small ? .body.weight(.semibold) : .title3.weight(.semibold) }
        #endif
    }
}
#endif

#if os(tvOS)
/// Apple TV's artwork tiles: the focused one lifts with a shadow, the others dim a little, so
/// focus reads from across the room without an outline. Each tile reads only its own focus.
struct LiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lifted(configuration: configuration)
    }

    private struct Lifted: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? 1.12 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 24, y: 18)
                .opacity(isFocused ? 1 : 0.8)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
#endif

extension View {
    /// Artwork tiles that open something: tvOS lifts them on focus; elsewhere the artwork
    /// itself carries `PointerHighlight`, so a caption under it stays clear.
    func tileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(LiftButtonStyle())
        #else
        buttonStyle(.plain)
        #endif
    }

    /// A 44 pt touch target for a one-line title that opens something ("Popular Movies ›",
    /// "Season 1 ⌄"), without moving what's around it.
    func titleTapTarget() -> some View {
        #if os(iOS)
        padding(.vertical, 8).contentShape(.rect).padding(.vertical, -8)
        #else
        self
        #endif
    }
}

/// Pointer feedback on artwork that opens something, which otherwise gives no sign in dense
/// rows of what can be clicked: the iPad pointer's highlight; on the Mac dimmed artwork, with
/// a white Play button only where clicking plays (an episode on the title page). Apple TV has
/// its focus effects instead.
struct PointerHighlight: ViewModifier {
    var plays = false
    #if os(macOS)
    @State private var isHovered = false
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.hoverEffect(.highlight)
        #elseif os(macOS)
        content
            .overlay {
                if isHovered {
                    ZStack {
                        Color.black.opacity(0.35)
                        if plays {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.black)
                                .offset(x: 2)
                                .frame(width: 52, height: 52)
                                .background(.white, in: .circle)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
        #else
        content
        #endif
    }
}
